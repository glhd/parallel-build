#!/bin/sh
# shellcheck shell=sh
# Run chains of commands in parallel. POSIX sh: no bashisms, no arrays.
#
#   chain <label> <command> [command...]
#   run
#
# Commands in a chain run in order and stop at the first failure. Separate
# chains run at the same time. The first failure anywhere cancels the rest.
# `run` blocks, prints what the chains write under the label of the chain
# that wrote it, and returns the exit code of the chain that failed.
#
# With STREAM=0 the output is held instead, and printed in one block a chain
# in declaration order.
#
# Every name this file defines starts with an underscore, apart from `chain`
# and `run`. A calling script and the commands in a chain are free to use
# anything else; anything starting with an underscore is this file's.

POLL=${POLL:-0.1}           # seconds between checks
POLL_WHOLE=${POLL_WHOLE:-1} # used instead if this sleep rejects fractions
STREAM=${STREAM:-1}         # 0 to hold the output and print it grouped
COLOR=${COLOR:-auto}        # 1 to colour the labels, 0 to leave them plain

# How many polls a cancelled chain gets to leave on its own before it is
# killed outright, which comes to about GRACE times POLL seconds: ten of them
# by default. A chain that ignores SIGTERM would otherwise hold `run` open for
# ever, and a build that hangs is worse than one that is rude.
GRACE=${GRACE:-100}

# The bar between a label and its line. A box drawing character reads as
# three bytes of noise in a terminal that is not expecting UTF-8, and the
# locale is what says whether it is, so the default follows the locale and
# an ASCII pipe stands in everywhere else.
#
# The character is written as its bytes rather than as itself, because this
# file has to be readable as text by whatever shell sources it: yash in the
# C locale refuses to read a script with a byte sequence the locale cannot
# make a character of, and a build container without a locale set is exactly
# where that happens. Everything here is ASCII for that reason.
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
*[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) STREAM_SEP=${STREAM_SEP:-$(printf '\342\224\202')} ;;
*) STREAM_SEP=${STREAM_SEP:-'|'} ;;
esac

# The colours the labels are given, as SGR parameters, one a chain in the
# order the chains were declared and round again from the top once a build has
# more chains than this has colours.
#
# Cyan, magenta, green, yellow, blue: the colours a terminal has had since it
# had eight of them, less red, which belongs to what a build says about its
# own failures, and less black and white, which the rest of the line already
# is. An entry is whatever SGR takes, so `1;36` is bold cyan, and a palette
# with nothing in it is another way of asking for no colour at all: the
# default fills in for a palette that was never set, and not for one that was
# deliberately emptied.
COLOR_PALETTE=${COLOR_PALETTE-'36 35 32 33 34'}

# Somewhere to keep what has to travel between the chains and the script that
# started them: a chain's log, and the status it ended on. What only this
# shell ever looks at, a chain's label and its pid, is kept in a variable.
#
# An
# explicit template because BSD mktemp wants one, and a check because
# without the directory every path below is a bare filename and the library
# would quietly write its bookkeeping into the working directory.
_work=$(mktemp -d "${TMPDIR:-/tmp}/parallel.XXXXXX") || _work=''
if [ -z "$_work" ] || [ ! -d "$_work" ]; then
	printf 'parallel.sh: could not create a temporary directory\n' >&2
	exit 1
fi

_count=0
_failed=0
_signal=0      # what to exit with if a signal arrives; 0 until one does
_fractional='' # whether sleep takes POLL; unknown until the first nap
_groups=''     # whether a chain can have its own process group; unknown
_monitor=''    # whether the calling shell had job control on already
_colored=''    # whether the labels are coloured; unknown until `run` looks
_esc=''        # the escape character, once there is a use for one
_reset=''      # what closes a colour, and nothing where there is none

# POSIX sh has no arrays, so what a chain has one of is kept in a name with
# the chain's number on the end of it, written and read through `eval`:
# _label_1, _pid_1, _prefix_1, _seen_1, _color_1. These are where one comes
# back out.
_label=''
_pid=''
_prefix=''
_seen=''
_color=''

_cleanup() { rm -rf "$_work" || :; }

# Every exit goes through _finish, which is what makes the status the same
# everywhere. Shells disagree about traps: a plain `exit 130` from the INT
# trap comes back as 0 under mksh, which takes the status of the last command
# the trap ran, and as 2 under ksh93; zsh does not always run the exit trap
# for a signal at all, so the signal traps clean up and exit themselves; and
# a trap whose test fails is abandoned under set -e, so _finish decides with
# a case, which cannot fail, rather than a test, which can.
#
# Nothing here has anything to say, and one shell has: ksh93 reports the
# chains this trap killed, on the way out, on the stderr of a script that is
# already leaving. That is what the redirection is for.
_finish() {
	_ec=$1
	case $_signal in
	0) ;;
	*) _ec=$_signal ;;
	esac
	_stop_chains
	_cleanup
	exit "$_ec"
} 2>/dev/null # job control's last word on the chains, and not the script's

# Take the chains down on the way out. Nothing else does: a chain is its own
# process, so an interrupted build that only cleaned up after itself would
# leave the compiler it started still running, and a script that gave up
# before it reached `run` would leave the lot. Every chain that reported a
# status is finished already, and killing a process that has gone is not an
# error worth reporting, so this cannot fail and cannot abandon the trap
# that called it.
_stop_chains() {
	_i=1
	while [ "$_i" -le "$_count" ]; do
		# No pid where the script gave up between counting a chain and
		# starting it, and nothing to kill in that case either.
		eval "_pid=\${_pid_$_i:-}"
		if [ ! -f "$_work/$_i.code" ] && [ -n "$_pid" ]; then
			_kill_chain "$_pid" now
		fi
		_i=$((_i + 1))
	done
}

# Stop one chain, and with it everything the chain started where the shell
# was able to give the chain a process group of its own.
#
# The chain's own shell goes first, on its pid. Killing the group outright
# would work as well, but the chain would still be there to see the command
# it was running killed, and shells report that: what it came to was a
# `Terminated` in the middle of a cancelled chain's output under bash and
# mksh, and a line about the job from ksh93. So `quietly` waits for the
# chain's shell to go before taking the group, and once it has gone there is
# nobody left to report anything. What is left in the group is what the
# chain started, however deep it goes: a group outlives its leader for
# exactly as long as one of them is still running, which is as long as there
# is anything in it worth killing.
#
# `now` skips that wait, and the exit trap uses it. Nothing that trap kills
# will be printed, so it has nothing to keep quiet for, and the script is
# already leaving, so there is nothing left to wait for it to be quiet for
# either.
#
# Neither kill can fail: cancelling races the chain finishing on its own,
# and this is called from the exit trap, which a failure would abandon.
_kill_chain() {
	kill "$1" 2>/dev/null || :
	case $2 in
	quietly) _await_exit "$1" ;;
	esac
	case $_groups in
	yes) kill -- "-$1" 2>/dev/null || : ;;
	esac
}

# Wait for a chain's shell to go, but not for ever. A chain that ignores
# SIGTERM, whether it is a build step with a shutdown handler of its own or
# one that has simply gone deaf, would otherwise hold `run` open with no way
# out but Ctrl-C, so it gets GRACE polls and then the signal no process can
# ignore.
#
# The kill is inside the loop, where the process was alive a moment ago,
# rather than after it, where the chain may have gone and been reaped and
# its pid handed to somebody else. `wait` afterwards reaps ours, and is the
# reason `kill -0` keeps answering for a chain that is finished but not yet
# collected.
_await_exit() {
	_left=$GRACE
	while kill -0 "$1" 2>/dev/null; do
		if [ "$_left" -le 0 ]; then
			kill -9 "$1" 2>/dev/null || :
			break
		fi
		_nap
		_left=$((_left - 1))
	done
	wait "$1" 2>/dev/null || :
}

# Whether this shell will put a background job in a process group of its own,
# which is what makes it possible to cancel a chain's children along with the
# chain. Job control is POSIX, but a non-interactive shell is allowed to
# leave it out: dash and busybox ash take `set -m` and start the job in the
# shell's own group anyway, and zsh refuses the option outright unless it has
# a terminal to hand the group the foreground with.
#
# The probe starts its job here, in the shell that will be starting the
# chains, and not in a subshell: a subshell is a different place to ask from
# and gives different answers. mksh says the group is there and then will not
# kill it, and FreeBSD's sh answered for a subshell what was not true of the
# script, which is a probe reporting on itself rather than on the chains.
#
# A job that was given its own group leads that group, so a group with its
# pid for an id exists. A job that was not is in the shell's group, and no
# other group can have that id while the job itself holds the pid, so asking
# after the group is the whole of the test and `ps` is not needed for it.
_probe_groups() {
	case $- in
	*m*) _monitor=yes ;;
	*) _monitor=no ;;
	esac
	_groups=no

	# Whether the option can be set at all is a question for a subshell,
	# because `set` is a special builtin and a special builtin that fails
	# takes a non-interactive shell down with it: zsh, which refuses -m
	# without a terminal, would end the build script rather than answer.
	(set -m) 2>/dev/null || return 0
	set -m 2>/dev/null # dash says out loud that it has no terminal for it

	# Braces and a redirection for the same reason `chain` has them: a shell
	# with job control announces the jobs it starts, and this one is not the
	# script's news. SIGKILL because the probe must not be able to hang.
	{ sleep 1 & } >/dev/null 2>&1
	_p=$!
	if kill -0 -- "-$_p" 2>/dev/null; then _groups=yes; fi
	kill -9 -- "-$_p" 2>/dev/null || kill -9 "$_p" 2>/dev/null
	wait "$_p" 2>/dev/null || :

	case $_monitor in no) set +m 2>/dev/null ;; esac
}

trap '_finish $?' EXIT
trap '_signal=130; _finish 130' INT
trap '_signal=143; _finish 143' TERM

chain() {
	if [ "$#" -eq 0 ]; then
		printf 'parallel.sh: chain needs a label\n' >&2
		return 2
	fi

	_count=$((_count + 1))
	_n=$_count
	eval "_label_$_n=\$1"
	shift

	# Job control decides which process group a job starts in, and decides it
	# when the job starts, so the option only has to be on across the fork
	# below. It goes back afterwards, because this is the calling script's
	# shell: under job control that script would find its own background jobs
	# taken out of its process group too.
	case $_groups in '') _probe_groups ;; esac
	case $_groups in yes) set -m ;; esac

	# The braces are for zsh, which announces every job it starts once it has
	# job control, on the calling script's stdout, in the middle of the report
	# the script is there to print. The announcement is this shell's, not the
	# chain's, so it is this shell's stdout that has to point elsewhere while
	# the chain starts. The chain's own output goes to its log either way, and
	# a fork that fails still has stderr to say so on.
	#
	# stdin comes from /dev/null, and is the one thing here that is not about
	# a shell being awkward. A background job in a shell without job control
	# gets /dev/null anyway, and one in a shell with job control keeps the
	# script's stdin and will read it: what that came to was a chain eating
	# the input of the script that started it, on every shell with job
	# control and on none of the ones without. Nothing a chain runs has any
	# business reading the build's stdin, and now none of them can.
	{
		(
			trap - INT TERM # don't inherit the parent's handlers

			# The chain has the group; it does not need job control of
			# its own, and is worse off with it. A chain that kept it
			# would give a group of its own to what it started, putting
			# it outside the group that cancelling kills. Off on what
			# the library turned on, not on what `$-` reports: dash
			# leaves `m` out of `$-` with monitor mode set, and the
			# ash-derived shells it is one of are exactly the ones this
			# would be wrong about.
			case $_groups in yes) set +m ;; esac

			# Always leave a status behind, even for a command that calls
			# exit itself: whatever ends this shell, the trap sees the
			# status it ended on. Write, then rename, so a reader never
			# sees a half-written file.
			trap '_ec=$?
				printf "%s" "$_ec" >"$_work/$_n.code.part"
				mv "$_work/$_n.code.part" "$_work/$_n.code"' EXIT

			# ${1+"$@"} rather than "$@", because a chain may have
			# been given a label and nothing to do: posh in a
			# script that set -u calls $@ with no arguments behind
			# it an unset parameter, and stops there.
			for _cmd in ${1+"$@"}; do
				eval "$_cmd" || exit $?
			done
		) >"$_work/$_n.log" 2>&1 </dev/null &
	} >/dev/null

	eval "_pid_$_n=\$!"

	if [ "$_groups" = yes ] && [ "$_monitor" = no ]; then set +m; fi
}

run() {
	_probe_color
	_colors
	if _streaming; then _prefixes; fi
	_await
	_cancel
	if _streaming; then _emit_all last; fi
	_report
	return "$_failed"
}

# Fractional sleeps are not POSIX. Probe once, remember the answer, and fall
# back to whole seconds on a sleep that rejects them.
#
# The naps swallow their status. A signal that arrives here kills the sleep
# as well, and ksh93 in a script that set -e quits on that failure before it
# ever runs the trap that cleans up.
_nap() {
	case $_fractional in
	yes) sleep "$POLL" || : ;;
	no) sleep "$POLL_WHOLE" || : ;;
	*)
		if sleep "$POLL" 2>/dev/null; then
			_fractional=yes
		else
			_fractional=no
			sleep "$POLL_WHOLE" || :
		fi
		;;
	esac
}

# Wait for everything, or return early as soon as one chain fails
_await() {
	while :; do
		if _streaming; then _emit_all now; fi
		_pending=0
		_i=1
		while [ "$_i" -le "$_count" ]; do
			_note_if_killed "$_i"
			if [ -f "$_work/$_i.code" ]; then
				_failed=$(cat "$_work/$_i.code")
				# `return 0`, not a bare `return`: a bare one hands back
				# the status of the test above, which aborts `run` in a
				# script that set -e.
				[ "$_failed" -eq 0 ] || return 0
			else
				_pending=$((_pending + 1))
			fi
			_i=$((_i + 1))
		done
		if [ "$_pending" -eq 0 ]; then return 0; fi
		_nap
	done
}

# A chain that is gone without having left a status behind was killed from
# outside: the signal no process can catch, or the machine running out of
# memory. Nothing is going to write that status now, so the wait above would
# be for ever; the run has to end, and it has to end as a failure, because a
# chain that was killed did not do the work it was given.
#
# Asked only of a chain that has not reported, and the report is looked for
# again afterwards: a chain that finished in between wrote its status just
# after we found the process gone, and that status is the true one. `kill -0`
# is the whole of the test, because a chain of ours that has ended goes on
# answering it until it is reaped, and `_cancel` is what reaps.
_note_if_killed() {
	if [ -f "$_work/$1.code" ]; then return 0; fi
	eval "_pid=\$_pid_$1"
	if kill -0 "$_pid" 2>/dev/null; then return 0; fi
	if [ -f "$_work/$1.code" ]; then return 0; fi

	: >"$_work/$1.killed"
	# 137 is what a shell reports for a child that SIGKILL took, and the
	# report says `killed` rather than this number, which the chain never
	# chose. It is here because `run` has to return something.
	printf '%s' 137 >"$_work/$1.code.part"
	mv "$_work/$1.code.part" "$_work/$1.code"
}

# Stop whatever is still running, and leave every chain with either a status
# or a cancellation, which is what lets the report read one or the other
# without having to allow for neither.
_cancel() {
	_i=1
	while [ "$_i" -le "$_count" ]; do
		if [ ! -f "$_work/$_i.code" ]; then
			: >"$_work/$_i.cancelled"
			eval "_pid=\$_pid_$_i"
			_kill_chain "$_pid" quietly
		fi
		_i=$((_i + 1))
	done
	wait 2>/dev/null || : # a killed job must not abort a script that set -e
}

# Whether output is streamed as it arrives rather than held and grouped.
_streaming() {
	case $STREAM in
	'' | 0 | no | off | false) return 1 ;;
	*) return 0 ;;
	esac
}

# Whether the labels are coloured, asked here at `run` rather than when the
# library is sourced: the answer is about the stream `run` prints to, and a
# build script is free to redirect its own output before it gets that far.
#
# Four things have a say, and each one overrules the one before it: the
# terminal, then NO_COLOR, then FORCE_COLOR, then COLOR. The two environment
# variables are the convention the rest of the tools in a build already
# follow, and COLOR is last because it is the only one of the four aimed at
# this library in particular.
_probe_color() {
	_colored=no

	# A terminal, and one with colours to give. terminfo is what knows how
	# many, and `tput` is what asks it; where there is no `tput`, a TERM
	# that is set and is not `dumb` is taken at its word.
	if [ -t 1 ]; then
		if command -v tput >/dev/null 2>&1; then
			_ncolors=$(tput colors 2>/dev/null) || _ncolors=0
		else
			_ncolors=8
		fi
		case ${TERM:-} in '' | dumb) _ncolors=0 ;; esac
		# `tput` answers -1 for a terminal with no colours at all and
		# nothing whatever for a TERM terminfo has not heard of, and
		# `[` either compares numbers or fails, which under set -e
		# takes the build with it.
		case $_ncolors in '' | *[!0-9]*) _ncolors=0 ;; esac
		if [ "$_ncolors" -ge 8 ]; then _colored=yes; fi
	fi

	# Set at all, whatever it is set to, which is what everything else
	# reading it in the same build takes it as.
	if [ -n "${NO_COLOR+set}" ]; then _colored=no; fi

	# The same, but for the 0 that means the opposite: FORCE_COLOR=0 is how
	# a good many tools are told to stop, and reading it as `start` on the
	# grounds that the name is set would be exactly the wrong way round.
	case ${FORCE_COLOR-} in
	'') ;;
	0) _colored=no ;;
	*) _colored=yes ;;
	esac

	case $COLOR in
	1 | yes | on | true | always) _colored=yes ;;
	0 | no | off | false | never) _colored=no ;;
	esac

	case $_colored in
	no) return 0 ;;
	esac

	# Written as its bytes for the same reason the bar above is: the escape
	# character is not ASCII either, and this file has to stay readable as
	# text by a shell in a locale that can make nothing of it.
	_esc=$(printf '\033')
	_reset="${_esc}[0m"
}

# One colour a chain, handed out here rather than at `chain` because whether
# there are any to hand out is not known until `run` has looked at where the
# output is going.
#
# The palette is a list in a string, POSIX sh having nothing better, and it is
# taken a word at a time with the expansions that trim a string rather than by
# letting the shell split it on the spaces: zsh does not split an unquoted
# expansion at all, and what that came to was the whole palette arriving as
# one colour. Refilled each time it runs out, which is what makes a sixth
# chain cyan again.
_colors() {
	case $_colored in
	no) return 0 ;;
	esac

	_rest=$COLOR_PALETTE
	_trim_palette
	# Nothing to hand out, so nothing is coloured, and the reset that
	# closes a colour has nothing left to close.
	if [ -z "$_rest" ]; then
		_colored=no
		_reset=''
		return 0
	fi

	_i=1
	while [ "$_i" -le "$_count" ]; do
		if [ -z "$_rest" ]; then
			_rest=$COLOR_PALETTE
			_trim_palette
		fi
		_sgr=${_rest%% *}
		_rest=${_rest#"$_sgr"}
		_trim_palette
		_open="${_esc}[${_sgr}m"
		eval "_color_$_i=\$_open"
		_i=$((_i + 1))
	done
}

# The spaces off the front of what is left of the palette, so that the next
# word off it is a colour and never the nothing between two spaces, and so
# that a palette of nothing but spaces reads as the empty one it is.
_trim_palette() {
	while :; do
		case $_rest in
		' '*) _rest=${_rest# } ;;
		*) return 0 ;;
		esac
	done
}

# The label a streamed line carries, one per chain, right aligned to the
# longest of them so that the bars line up under each other. Every label is
# known by the time `run` is called, which is the first moment a width can be
# worked out at all.
_prefixes() {
	_pad=0
	_i=1
	while [ "$_i" -le "$_count" ]; do
		eval "_label=\$_label_$_i"
		if [ "${#_label}" -gt "$_pad" ]; then _pad=${#_label}; fi
		_i=$((_i + 1))
	done

	_i=1
	while [ "$_i" -le "$_count" ]; do
		eval "_label=\$_label_$_i"
		_prefix=$(printf "%${_pad}s" "$_label")
		eval "_prefix_$_i=\$_prefix"
		_i=$((_i + 1))
	done
}

# What every chain has written since the last look round, or, with `last`,
# the rest of it, once the chains are done. The poll is the only thing
# printing, so two chains that write at the same moment come out as whole
# lines one after the other rather than mixed into each other.
#
# Its own counter, because the wait loop calls this from inside a loop of
# its own and POSIX sh has no local variables.
_emit_all() {
	_e=1
	while [ "$_e" -le "$_count" ]; do
		_emit "$_e" "$1"
		_e=$((_e + 1))
	done
}

# One chain's new output. The count of lines already printed is the whole of
# the reader's position: `tail` starts from the line after it, and a line
# that has no newline yet is left where it is, so a line written in two goes
# out in one piece instead of as two labelled halves. `read` fails on that
# partial line without counting it, which is what leaves it to be read again
# next time round, until `last`, when there is no next time and what is
# there is all there will be.
#
# The loop reads a file rather than a pipe on purpose: a pipe would put it
# in a subshell in most shells, and the count it keeps would go with it. The
# chunk is the one file here that is written more than once, so it is the one
# redirection that has to say it means to overwrite: a calling script that
# set -C would otherwise lose every line after the first poll.
_emit() {
	_n=$1
	eval "_seen=\${_seen_$_n:-0}"
	eval "_prefix=\$_prefix_$_n"
	eval "_color=\${_color_$_n:-}"
	tail -n "+$((_seen + 1))" "$_work/$_n.log" \
		>|"$_work/$_n.chunk" 2>/dev/null || return 0

	# The colour runs from the start of the label to the end of the bar and
	# closes there, so the bars make a column in the chain's colour and
	# what the command wrote goes out exactly as it wrote it.
	_line=''
	while IFS= read -r _line; do
		printf '%s%s %s%s %s\n' "$_color" "$_prefix" "$STREAM_SEP" "$_reset" "$_line"
		_seen=$((_seen + 1))
		_line=''
	done <"$_work/$_n.chunk"

	if [ -n "$_line" ] && [ "$2" = last ]; then
		printf '%s%s %s%s %s\n' "$_color" "$_prefix" "$STREAM_SEP" "$_reset" "$_line"
		_seen=$((_seen + 1))
	fi

	eval "_seen_$_n=\$_seen"
}

_report() {
	# The blank line only when there is a line to put under it. A streamed
	# run says nothing at the end about a chain that finished, and chains
	# are cancelled by a failure and by nothing else, so a run that failed
	# is exactly a run with something left to say.
	if _streaming && [ "$_failed" -ne 0 ]; then printf '\n'; fi

	_i=1
	while [ "$_i" -le "$_count" ]; do
		if _streaming; then
			# Only what the output did not already say. A chain that
			# finished said so line by line as it went, and a heading with
			# nothing under it is a heading for nothing; what is left is
			# the chain that failed and the chains that went down with it.
			_outcome "$_i"
		else
			_group "$_i"
		fi
		_i=$((_i + 1))
	done
}

# How a chain ended, or nothing at all if it simply worked. Both reports end
# a chain on this line, so a build that greps for one finds it either way.
_outcome() {
	eval "_label=\$_label_$1"
	eval "_color=\${_color_$1:-}"
	# The label carries the colour and the mark in front of it does not:
	# the colour says which chain, and nothing else, here as above.
	if [ -f "$_work/$1.cancelled" ]; then
		printf '[.] %s%s%s cancelled\n' "$_color" "$_label" "$_reset"
	elif [ -f "$_work/$1.killed" ]; then
		printf '[!] %s%s%s killed\n' "$_color" "$_label" "$_reset"
	else
		_code=$(cat "$_work/$1.code")
		case $_code in
		0) ;;
		*) printf '[!] %s%s%s exited %s\n' "$_color" "$_label" "$_reset" "$_code" ;;
		esac
	fi
}

# One chain's whole output under a heading of its own, which is what STREAM=0
# asks for.
_group() {
	if [ -f "$_work/$1.cancelled" ]; then
		_mark='...'
	elif [ "$(cat "$_work/$1.code")" = 0 ]; then
		_mark='---'
	else
		_mark='[!]'
	fi

	eval "_label=\$_label_$1"
	eval "_color=\${_color_$1:-}"
	printf '\n%s %s%s%s\n' "$_mark" "$_color" "$_label" "$_reset"
	cat "$_work/$1.log"
	# A chain whose last line never got a newline would otherwise have the
	# line below glued onto the end of it.
	case $(tail -c 1 "$_work/$1.log" 2>/dev/null) in
	'') ;;
	*) printf '\n' ;;
	esac
	_outcome "$1"
}

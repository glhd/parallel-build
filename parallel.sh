#!/bin/sh
# shellcheck shell=sh
# Run chains of commands in parallel. POSIX sh — no bashisms, no arrays.
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

POLL=${POLL:-0.1}           # seconds between checks
POLL_WHOLE=${POLL_WHOLE:-1} # used instead if this sleep rejects fractions
STREAM=${STREAM:-1}         # 0 to hold the output and print it grouped

# The bar between a label and its line. A box drawing character reads as
# three bytes of noise in a terminal that is not expecting UTF-8, and the
# locale is what says whether it is, so the default follows the locale and
# an ASCII pipe stands in everywhere else.
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
*[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) STREAM_SEP=${STREAM_SEP:-'│'} ;;
*) STREAM_SEP=${STREAM_SEP:-'|'} ;;
esac

_work=$(mktemp -d)
_count=0
_failed=0
_signal=0      # what to exit with if a signal arrives; 0 until one does
_fractional='' # whether sleep takes POLL; unknown until the first nap
_groups=''     # whether a chain can have its own process group; unknown
_monitor=''    # whether the calling shell had job control on already

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
	i=1
	while [ "$i" -le "$_count" ]; do
		if [ ! -f "$_work/$i.code" ] && [ -f "$_work/$i.pid" ]; then
			_kill_chain "$(cat "$_work/$i.pid")" now
		fi
		i=$((i + 1))
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
# will be printed, so it has nothing to keep quiet for, and a chain that has
# made itself deaf to the signal must not be able to hold the trap — and the
# script — open while it waits for a shell that is not going to go.
#
# Neither kill can fail: cancelling races the chain finishing on its own,
# and this is called from the exit trap, which a failure would abandon.
_kill_chain() {
	kill "$1" 2>/dev/null || :
	case $_groups in
	yes)
		case $2 in
		quietly) wait "$1" 2>/dev/null || : ;;
		esac
		kill -- "-$1" 2>/dev/null || :
		;;
	esac
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
# script — which is a probe reporting on itself rather than on the chains.
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
	_count=$((_count + 1))
	n=$_count
	printf '%s' "$1" >"$_work/$n.label"
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

			code=0
			# Always leave a status behind, even if a command calls
			# exit. Write, then rename, so the reader never sees a
			# half-written file.
			# shellcheck disable=SC2154 # ec is assigned in the same trap
			trap 'ec=$?; [ "$code" -ne 0 ] || code=$ec
				printf "%s" "$code" >"$_work/$n.code.part"
				mv "$_work/$n.code.part" "$_work/$n.code"' EXIT

			for cmd in "$@"; do
				eval "$cmd" || {
					code=$?
					break
				}
			done
		) >"$_work/$n.log" 2>&1 &
	} >/dev/null

	printf '%s' "$!" >"$_work/$n.pid"

	if [ "$_groups" = yes ] && [ "$_monitor" = no ]; then set +m; fi
}

run() {
	_streaming && _prefixes
	_await
	_cancel
	_streaming && _flush
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
		_streaming && _pump
		pending=0
		i=1
		while [ "$i" -le "$_count" ]; do
			if [ -f "$_work/$i.code" ]; then
				_failed=$(cat "$_work/$i.code")
				# `return 0`, not a bare `return`: a bare one hands back
				# the status of the test above, which aborts `run` in a
				# script that set -e.
				[ "$_failed" -eq 0 ] || return 0
			else
				pending=$((pending + 1))
			fi
			i=$((i + 1))
		done
		[ "$pending" -eq 0 ] && return 0
		_nap
	done
}

_cancel() {
	i=1
	while [ "$i" -le "$_count" ]; do
		if [ ! -f "$_work/$i.code" ]; then
			: >"$_work/$i.cancelled"
			_kill_chain "$(cat "$_work/$i.pid")" quietly
		fi
		i=$((i + 1))
	done
	wait 2>/dev/null || : # a killed job must not abort a script that set -e
}

# Whether output is streamed as it arrives rather than held and grouped.
_streaming() {
	case ${STREAM:-1} in
	'' | 0 | no | off | false) return 1 ;;
	*) return 0 ;;
	esac
}

# The label a streamed line carries, one per chain, right aligned to the
# longest of them so that the bars line up under each other. Labels are
# known by the time `run` is called, which is the first moment a width can
# be worked out, and they are kept in variables because the pump wants them
# on every poll.
_prefixes() {
	_pad=0
	i=1
	while [ "$i" -le "$_count" ]; do
		label=$(cat "$_work/$i.label")
		[ "${#label}" -gt "$_pad" ] && _pad=${#label}
		i=$((i + 1))
	done

	i=1
	while [ "$i" -le "$_count" ]; do
		label=$(cat "$_work/$i.label")
		while [ "${#label}" -lt "$_pad" ]; do label=" $label"; done
		eval "_label_$i=\$label"
		i=$((i + 1))
	done
}

# What every chain has written since the last look round. The poll is the
# only thing printing, so two chains that write at the same moment come out
# as whole lines one after the other rather than mixed into each other.
_pump() {
	i=1
	while [ "$i" -le "$_count" ]; do
		_emit "$i" now
		i=$((i + 1))
	done
}

# The rest of it, once the chains are done: what the last poll did not get
# to, and the final line of a chain that ended without a newline.
_flush() {
	i=1
	while [ "$i" -le "$_count" ]; do
		_emit "$i" last
		i=$((i + 1))
	done
}

# One chain's new output. The count of lines already printed is the whole of
# the reader's position: `tail` starts from the line after it, and a line
# that has no newline yet is left where it is, so a line written in two goes
# out in one piece instead of as two labelled halves. `read` fails on that
# partial line without counting it, which is what leaves it to be read again
# next time round — until `last`, when there is no next time and what is
# there is all there will be.
#
# The loop reads a file rather than a pipe on purpose: a pipe would put it
# in a subshell in most shells, and the count it keeps would go with it.
_emit() {
	n=$1
	eval "seen=\${_seen_$n:-0} label=\$_label_$n"
	tail -n "+$((seen + 1))" "$_work/$n.log" \
		>"$_work/$n.chunk" 2>/dev/null || return 0

	line=''
	while IFS= read -r line; do
		printf '%s %s %s\n' "$label" "$STREAM_SEP" "$line"
		seen=$((seen + 1))
		line=''
	done <"$_work/$n.chunk"

	if [ -n "$line" ] && [ "$2" = last ]; then
		printf '%s %s %s\n' "$label" "$STREAM_SEP" "$line"
		seen=$((seen + 1))
	fi

	eval "_seen_$n=\$seen"
}

_report() {
	# The blank line only when there is a line to put under it. A streamed
	# run says nothing at the end about a chain that finished, and chains
	# are cancelled by a failure and by nothing else, so a run that failed
	# is exactly a run with something left to say.
	_streaming && [ "$_failed" -ne 0 ] && printf '\n'
	i=1
	while [ "$i" -le "$_count" ]; do
		label=$(cat "$_work/$i.label")
		code=""
		[ -f "$_work/$i.code" ] && code=$(cat "$_work/$i.code")

		if [ -f "$_work/$i.cancelled" ]; then
			mark="..."
			code=""
		elif [ "$code" = 0 ]; then
			mark="---"
		else
			mark="[!]"
		fi

		if _streaming; then
			# Only what the output did not already say. A chain that
			# finished said so line by line as it went, and a heading with
			# nothing under it is a heading for nothing; what is left is
			# the chain that failed and the chains that went down with it.
			# The lines are the ones the grouped report ends a chain on, so
			# a build that greps for one finds it either way.
			if [ -f "$_work/$i.cancelled" ]; then
				printf '[.] %s cancelled\n' "$label"
			elif [ -n "$code" ] && [ "$code" -ne 0 ]; then
				printf '[!] %s exited %s\n' "$label" "$code"
			fi
		else
			printf '\n%s %s\n' "$mark" "$label"
			cat "$_work/$i.log"
			[ -n "$code" ] && [ "$code" -ne 0 ] &&
				printf '[!] %s exited %s\n' "$label" "$code"
			[ -f "$_work/$i.cancelled" ] && printf '[.] %s cancelled\n' "$label"
		fi
		i=$((i + 1))
	done
}

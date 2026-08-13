#!/bin/sh
# shellcheck shell=sh
# Run chains of commands in parallel. POSIX sh — no bashisms, no arrays.
#
#   chain <label> <command> [command...]
#   run
#
# Commands in a chain run in order and stop at the first failure. Separate
# chains run at the same time. The first failure anywhere cancels the rest.
# `run` blocks, prints each chain's output in declaration order, and returns
# the exit code of the chain that failed.

POLL=${POLL:-0.1}           # seconds between checks
POLL_WHOLE=${POLL_WHOLE:-1} # used instead if this sleep rejects fractions

_work=$(mktemp -d)
_count=0
_failed=0
_signal=0      # what to exit with if a signal arrives; 0 until one does
_fractional='' # whether sleep takes POLL; unknown until the first nap

_cleanup() { rm -rf "$_work" || :; }

# Every exit goes through _finish, which is what makes the status the same
# everywhere. Shells disagree about traps: a plain `exit 130` from the INT
# trap comes back as 0 under mksh, which takes the status of the last command
# the trap ran, and as 2 under ksh93; zsh does not always run the exit trap
# for a signal at all, so the signal traps clean up and exit themselves; and
# a trap whose test fails is abandoned under set -e, so _finish decides with
# a case, which cannot fail, rather than a test, which can.
_finish() {
	_ec=$1
	case $_signal in
	0) ;;
	*) _ec=$_signal ;;
	esac
	_stop_chains
	_cleanup
	exit "$_ec"
}

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
			kill "$(cat "$_work/$i.pid")" 2>/dev/null || :
		fi
		i=$((i + 1))
	done
}

trap '_finish $?' EXIT
trap '_signal=130; _finish 130' INT
trap '_signal=143; _finish 143' TERM

chain() {
	_count=$((_count + 1))
	n=$_count
	printf '%s' "$1" >"$_work/$n.label"
	shift

	(
		trap - INT TERM # don't inherit the parent's handlers
		code=0
		# Always leave a status behind, even if a command calls exit.
		# Write, then rename, so the reader never sees a half-written file.
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

	printf '%s' "$!" >"$_work/$n.pid"
}

run() {
	_await
	_cancel
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
			kill "$(cat "$_work/$i.pid")" 2>/dev/null
		fi
		i=$((i + 1))
	done
	wait 2>/dev/null || : # a killed job must not abort a script that set -e
}

_report() {
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

		printf '\n%s %s\n' "$mark" "$label"
		cat "$_work/$i.log"
		[ -n "$code" ] && [ "$code" -ne 0 ] &&
			printf '[!] %s exited %s\n' "$label" "$code"
		[ -f "$_work/$i.cancelled" ] && printf '[.] %s cancelled\n' "$label"
		i=$((i + 1))
	done
}

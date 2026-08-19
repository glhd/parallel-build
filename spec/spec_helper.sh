# shellcheck shell=sh
#
# Every example writes a small driver script, runs it in a separate process
# under the shell being tested, and asserts on what that process printed and
# on which marker files it left behind. Nothing asserts on elapsed time.

spec_helper_precheck() {
	minimum_version "0.28.1"
}

spec_helper_loaded() {
	:
}

spec_helper_configure() {
	before_each 'setup_workdir'
	after_each 'teardown_workdir'
}

# The library under test, and a fast poll so the suite does not crawl.
LIB="$SHELLSPEC_PROJECT_ROOT/parallel.sh"
POLL="${SPEC_POLL:-0.02}"
export LIB POLL

# Seconds any single driver may run before it is killed. A hang has to fail
# the suite, not stall CI until the job timeout.
DRIVER_TIMEOUT="${SPEC_DRIVER_TIMEOUT:-30}"

# Scratch space for the driver script and for the marker files the fake
# commands touch. Drivers get it as $WORK.
setup_workdir() {
	WORK=$(mktemp -d "${TMPDIR:-/tmp}/parallel-spec.XXXXXX")
	export WORK
}

teardown_workdir() {
	[ -n "${WORK:-}" ] && rm -rf "$WORK"
	WORK=''
}

# Cancelling a chain leaves a process behind by design, and so does a driver
# that is interrupted mid-run. Anything that can outlive an example is
# started through one of these two, with fds 3 through 9 closed: those are
# shellspec's own pipes, and it waits on them for as long as a stray holds
# them open. Closing an fd that was never open is not an error in any of the
# shells this suite runs under.
start_driver() {
	"$SHELLSPEC_SHELL" "$WORK/driver.sh" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
}

# The same driver, but for the background, and `exec` is the whole point of
# the second copy. `start_driver &` forks a subshell that then waits on the
# driver, so $! names the subshell and not the driver: killing it reaps the
# wrapper and leaves the driver running, holding the pipes shellspec reads
# the example's output from. The watchdog below then has nothing to kill,
# and one driver that hangs hangs the whole suite instead of failing its own
# example. Replacing the subshell with the driver keeps the pid the same one
# the watchdog was given.
spawn_driver() {
	exec "$SHELLSPEC_SHELL" "$WORK/driver.sh" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
}

detach() {
	"$@" >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
}

# Read a driver script from stdin (a Data block), then run it under the shell
# being tested. $LIB and $WORK are in its environment.
#
# When the driver is finished, $WORK/done appears. A fake command that has to
# stay busy for a while waits for that file to arrive or for $WORK itself to
# go, so a stray goes away on its own shortly after the example that made it.
# Waiting on the file alone is not enough: teardown takes $WORK away moments
# after the marker lands, and a fake that was mid-nap then waits forever for
# a file that can no longer appear. The macOS runner does not finish a step
# while a process it started is still alive, so one immortal stray is a
# fifteen-minute job timeout there, long after the suite itself has passed.
driver() {
	cat >"$WORK/driver.sh"
	rm -f "$WORK/done" "$WORK/timed-out"
	spawn_driver &
	_child=$!
	detach watchdog "$_child"
	_watchdog=$!
	wait "$_child"
	_status=$?
	: >"$WORK/done"
	stop "$_watchdog"
	report_timeout
	return "$_status"
}

# Same, but send the driver a SIGINT once it reports it has started working.
#
# The driver runs in the foreground and a helper in the background does the
# signalling, not the other way around: a shell without job control starts
# background jobs with SIGINT ignored, and a signal ignored on entry cannot
# be trapped, so a backgrounded driver would never see the interrupt. The
# driver publishes its own pid for the helper to aim at.
driver_interrupted() {
	cat >"$WORK/driver.sh"
	rm -f "$WORK/done" "$WORK/timed-out"
	detach interrupter
	_interrupter=$!
	start_driver
	_status=$?
	: >"$WORK/done"
	stop "$_interrupter"
	report_timeout
	return "$_status"
}

# Say so when a driver had to be killed. Without this the example fails on a
# status it never chose, which reads like the library returning the wrong
# code rather than the driver never returning at all.
report_timeout() {
	[ -e "$WORK/timed-out" ] || return 0
	printf 'driver did not finish within %ss and was killed\n' "$DRIVER_TIMEOUT" >&2
}

# Shut a helper down and reap it. Left running, it would still be a child of
# the shell shellspec waits on at the end of the example, and every example
# would pay the full timeout.
stop() {
	kill "$1" 2>/dev/null
	wait "$1" 2>/dev/null
	return 0
}

# The driver here runs in the foreground, so this helper is the only thing
# that can end it: a driver that never reports it started, or that sits
# through the interrupt, has to be killed anyway rather than left to run.
interrupter() {
	if await_file "$WORK/started"; then
		kill -INT "$(cat "$WORK/pid")" 2>/dev/null
	elif [ -e "$WORK/done" ]; then
		return 0 # it finished on its own; there is nothing to interrupt
	fi
	countdown || return 0
	: >"$WORK/timed-out"
	kill -9 "$(cat "$WORK/pid" 2>/dev/null)" 2>/dev/null
}

# Kill a driver that outstays its welcome.
watchdog() {
	countdown || return 0
	: >"$WORK/timed-out"
	kill -9 "$1" 2>/dev/null
}

# Sleep out the timeout a second at a time, stopping early once the driver is
# done. Returns 0 only if the whole timeout elapsed.
countdown() {
	_left=$DRIVER_TIMEOUT
	while [ "$_left" -gt 0 ]; do
		sleep 1
		[ -e "$WORK/done" ] && return 1
		_left=$((_left - 1))
	done
	return 0
}

# Wait for a marker file to appear, giving up rather than hanging.
await_file() {
	_waited=0
	while [ ! -e "$1" ]; do
		[ -e "$WORK/done" ] && return 1
		_waited=$((_waited + 1))
		[ "$_waited" -gt "$DRIVER_TIMEOUT" ] && return 1
		sleep 1
	done
	return 0
}

# The temp directory a finished driver reported through $WORK/workdir.
reported_workdir() {
	cat "$WORK/workdir"
}

# Whether the chain a finished driver reported through $WORK/chainpid is
# still running.
chain_state() {
	process_state "$WORK/chainpid"
}

# The same for any pid a driver left in a file, which is how a chain's own
# children are asked after. A process that has just been killed can sit as a
# zombie until whatever adopted it reaps it, so this waits a few seconds for
# an answer rather than believing the first one, and reads a pid that is
# still answering as stopped once it has become a zombie: a zombie is a
# process that has died, whatever `kill -0` makes of it. Not every `ps` here
# takes -p, and the ones that do not simply leave the wait to decide.
process_state() {
	_pid=$(cat "$1")
	_waited=0
	while kill -0 "$_pid" 2>/dev/null; do
		case $(ps -o stat= -p "$_pid" 2>/dev/null) in
		*Z*) break ;;
		esac
		if [ "$_waited" -ge 5 ]; then
			printf 'running'
			return 0
		fi
		_waited=$((_waited + 1))
		sleep 1
	done
	printf 'stopped'
}

# Whether the shell under test leaves a background job in the shell's own
# process group, which is the library's own test for whether it can take a
# chain's children down with the chain. Job control is optional in a
# non-interactive shell: dash and busybox ash take `set -m` and ignore it,
# and zsh refuses it outright without a terminal.
no_process_groups() {
	# shellcheck disable=SC2016 # the probe is the other shell's to expand
	! "$SHELLSPEC_SHELL" -c '
		set -m 2>/dev/null || exit 1
		sleep 1 &
		p=$!
		kill -0 -- "-$p" 2>/dev/null
		ok=$?
		kill -9 -- "-$p" 2>/dev/null || kill -9 "$p" 2>/dev/null
		wait "$p" 2>/dev/null
		exit "$ok"
	' 2>/dev/null
}

lines_in() {
	wc -l <"$1" | tr -d ' '
}

# True when this shell runs `sleep` from PATH, which is what lets a spec put
# a fake one in front of it. ksh93 has sleep as a builtin, and busybox ash
# runs its own applet, so on those two a fake is simply not reachable.
sleep_is_builtin() {
	_probe=$(mktemp -d "${TMPDIR:-/tmp}/parallel-probe.XXXXXX")
	printf '#!/bin/sh\nexit 42\n' >"$_probe/sleep"
	chmod +x "$_probe/sleep"
	(
		PATH="$_probe:$PATH"
		export PATH
		sleep 0
	)
	_probe_status=$?
	rm -rf "$_probe"
	[ "$_probe_status" -ne 42 ]
}

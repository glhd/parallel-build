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

detach() {
	"$@" >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
}

# Read a driver script from stdin (a Data block), then run it under the shell
# being tested. $LIB and $WORK are in its environment.
#
# When the driver is finished, $WORK/done appears. A fake command that has to
# stay busy for a while waits on that file, so a stray goes away on its own
# shortly after the example that made it.
driver() {
	cat >"$WORK/driver.sh"
	rm -f "$WORK/done"
	start_driver &
	_child=$!
	detach watchdog "$_child"
	_watchdog=$!
	wait "$_child"
	_status=$?
	: >"$WORK/done"
	stop "$_watchdog"
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
	rm -f "$WORK/done"
	detach interrupter
	_interrupter=$!
	start_driver
	_status=$?
	: >"$WORK/done"
	stop "$_interrupter"
	return "$_status"
}

# Shut a helper down and reap it. Left running, it would still be a child of
# the shell shellspec waits on at the end of the example, and every example
# would pay the full timeout.
stop() {
	kill "$1" 2>/dev/null
	wait "$1" 2>/dev/null
	return 0
}

interrupter() {
	await_file "$WORK/started" || return 0
	kill -INT "$(cat "$WORK/pid")" 2>/dev/null
	countdown && kill -9 "$(cat "$WORK/pid" 2>/dev/null)" 2>/dev/null
}

# Kill a driver that outstays its welcome.
watchdog() {
	countdown && kill -9 "$1" 2>/dev/null
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

# shellcheck shell=sh
#
# Every example writes the driver script in its Data block, runs it in a
# separate process under the shell being tested, and asserts on that
# process's output, exit status, and the marker files its commands left
# behind. Nothing asserts on elapsed time: a marker either exists or it
# does not, and that is the same answer on a loaded CI runner as it is on
# an idle laptop.
#
# Drivers run under `set -eu` throughout, because a build script that
# sources this library is likely to, and the library has to survive it.

Describe 'parallel.sh'
	Describe 'chains that succeed'
		It 'runs two chains and reports both, in declaration order'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "first" "printf 'one output\n'"
				#|chain "second" "printf 'two output\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should match pattern "*--- first*one output*--- second*two output*"
		End

		It 'handles a single chain with a single command'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "only" "printf 'the one output\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 2 of output should equal "--- only"
			The line 3 of output should equal "the one output"
		End
	End

	Describe 'ordering within a chain'
		It 'runs each command only after the one before it finished'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "ordered" \
				#|	"printf 'first\n' >>'$WORK/log'; touch '$WORK/first'" \
				#|	"test -f '$WORK/first' && printf 'second\n' >>'$WORK/log' && touch '$WORK/second'"
				#|run
				#|cat "$WORK/log"
			End

			When call driver
			The status should equal 0
			# The second command's marker exists at all only because it
			# checked for the first command's marker before touching it.
			The file "$WORK/first" should be exist
			The file "$WORK/second" should be exist
			The output should match pattern "*first*second*"
		End
	End

	Describe 'failure'
		It 'stops a chain at its first failing command'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "stops" \
				#|	"touch '$WORK/before'" \
				#|	"false" \
				#|	"touch '$WORK/after'"
				#|run
			End

			When call driver
			The status should equal 1
			The file "$WORK/before" should be exist
			The file "$WORK/after" should not be exist
			The output should include "[!] stops exited 1"
		End

		It 'propagates the exit code of the failing command'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "seven" "sh -c 'exit 7'"
				#|run
			End

			When call driver
			The status should equal 7
			The output should include "[!] seven exited 7"
		End

		It 'reports a command that exits the chain outright'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "quits" \
				#|	"printf 'before the exit\n'; exit 3" \
				#|	"touch '$WORK/after'"
				#|run
			End

			When call driver
			The status should equal 3
			The output should include "before the exit"
			The output should include "[!] quits exited 3"
			The file "$WORK/after" should not be exist
		End
	End

	Describe 'cancellation'
		# The slow chain naps a second at a time and waits on the flag the
		# harness raises when the driver is done. Cancelling a chain kills
		# its shell but not the sleep it is blocked in, so one long sleep
		# here would leave a stray process running well past the example.
		It 'cancels a running chain when another chain fails'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "slow" \
				#|	"touch '$WORK/slow-started'" \
				#|	"until [ -f '$WORK/done' ]; do sleep 1; done" \
				#|	"touch '$WORK/slow-finished'"
				#|chain "quick" \
				#|	"until [ -f '$WORK/slow-started' ]; do sleep 1; done" \
				#|	"exit 4"
				#|run
			End

			When call driver
			The status should equal 4
			The file "$WORK/slow-started" should be exist
			The file "$WORK/slow-finished" should not be exist
			The output should include "... slow"
			The output should include "[.] slow cancelled"
		End
	End

	Describe 'output grouping'
		It "collects a command's stdout and stderr into its own group"
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "noisy" "printf 'went to stdout\n'; printf 'went to stderr\n' >&2"
				#|chain "quiet" "printf 'other chain\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should match pattern "*--- noisy*went to stdout*went to stderr*--- quiet*"
			The stderr should equal ""
		End

		It 'passes command strings through untouched'
			Data
				#|set -eu
				#|. "$LIB"
				#|cd "$WORK"
				#|touch alpha beta
				#|chain "quoting" \
				#|	"printf '%s\n' 'single quoted'" \
				#|	"printf '%s\n' \"double quoted\"" \
				#|	"printf '%s\n' 'it'\''s'" \
				#|	"printf '%s\n' '*'" \
				#|	"printf '%s\n' 'two  spaces'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 3 of output should equal "single quoted"
			The line 4 of output should equal "double quoted"
			The line 5 of output should equal "it's"
			# Still a bare asterisk, though the chain ran in a directory
			# with files in it.
			The line 6 of output should equal "*"
			The line 7 of output should equal "two  spaces"
		End
	End

	Describe 'polling'
		# The fake sleep rejects fractions, the way a sleep without the
		# GNU or BSD extension does. The chain uses /bin/sleep directly,
		# so everything the fake records came from the library.
		It 'falls back to whole seconds when sleep rejects fractions'
			Skip if "this shell's sleep is built in, so a fake cannot stand in for it" sleep_is_builtin

			Data
				#|set -eu
				#|mkdir -p "$WORK/bin"
				#|cat >"$WORK/bin/sleep" <<'FAKE'
				#|#!/bin/sh
				#|case $1 in
				#|*.*)
				#|	printf '%s\n' "$1" >>"$WORK/rejected"
				#|	printf 'sleep: invalid time interval %s\n' "$1" >&2
				#|	exit 1
				#|	;;
				#|esac
				#|printf '%s\n' "$1" >>"$WORK/slept"
				#|exec /bin/sleep "$1"
				#|FAKE
				#|chmod +x "$WORK/bin/sleep"
				#|PATH="$WORK/bin:$PATH"
				#|export PATH
				#|. "$LIB"
				#|chain "quick" "printf 'quick done\n'"
				#|chain "slow" "/bin/sleep 1; printf 'slow done\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "slow done"
			# Whole seconds after the fraction was refused, and the
			# refusal happened once: the answer is remembered.
			The file "$WORK/slept" should be exist
			The value "$(lines_in "$WORK/rejected")" should equal 1
		End
	End

	Describe 'cleanup'
		It 'removes its temp directory on a normal exit'
			Data
				#|set -eu
				#|. "$LIB"
				#|printf '%s\n' "$_work" >"$WORK/workdir"
				#|chain "brief" "printf 'done\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "done"
			The directory "$(reported_workdir)" should not be exist
		End

		It 'removes its temp directory on SIGINT'
			Data
				#|set -eu
				#|. "$LIB"
				#|printf '%s\n' "$_work" >"$WORK/workdir"
				#|printf '%s\n' "$$" >"$WORK/pid"
				#|chain "slow" \
				#|	"touch '$WORK/started'" \
				#|	"until [ -f '$WORK/done' ]; do sleep 1; done"
				#|run
			End

			When call driver_interrupted
			The status should equal 130
			The directory "$(reported_workdir)" should not be exist
		End
	End
End

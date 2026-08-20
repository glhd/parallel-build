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
		# Output is labelled and printed as it arrives unless a build asks
		# for it grouped, so this is what a build sees by default.
		It 'labels every line with the chain it came from'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "first" "printf 'one output\n'"
				#|chain "second" "printf 'two output\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include " first | one output"
			The output should include "second | two output"
			# And that is the whole of it. A chain that finished said so as
			# it went, so there is nothing to add under its name at the end.
			The output should not include "--- first"
			The output should not include "--- second"
		End

		It 'handles a single chain with a single command'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "only" "printf 'the one output\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "only | the one output"
			The output should not include "--- only"
		End

		# The label and the bar are the only thing added to a line. What a
		# command wrote is what comes out, whatever it happens to look like:
		# a printf format, an option, a backslash, the spaces at either end.
		It 'prints what a chain wrote and nothing else'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "odd" "printf '%s\n' '100% sure' '-n' 'a\\backslash' '  indented' 'two  spaces'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "odd | 100% sure"
			The line 2 of output should equal "odd | -n"
			The line 3 of output should equal "odd | a\\backslash"
			The line 4 of output should equal "odd |   indented"
			The line 5 of output should equal "odd | two  spaces"
		End
	End

	# What a build declares, and the answers to declaring nothing much at all.
	Describe 'declaring chains'
		It 'has nothing to say when no chain was declared'
			Data
				#|set -eu
				#|. "$LIB"
				#|run
				#|printf 'run returned %s\n' "$?"
			End

			When call driver
			The status should equal 0
			The output should equal "run returned 0"
		End

		It 'runs a chain that was given nothing to do'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "idle"
				#|run
				#|printf 'run returned %s\n' "$?"
			End

			When call driver
			The status should equal 0
			The output should equal "run returned 0"
		End

		# A chain needs a label, because the label is how its output is
		# named. Saying so beats the shell's own complaint about $1.
		It 'refuses a chain with no label'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain || printf 'chain returned %s\n' "$?"
				#|run
			End

			When call driver
			The status should equal 0
			The output should equal "chain returned 2"
			The stderr should include "chain needs a label"
		End

		It 'keeps a dozen chains apart'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|i=1
				#|while [ "$i" -le 12 ]; do
				#|	chain "chain-$i" "printf 'from %s\n' $i"
				#|	i=$((i + 1))
				#|done
				#|run >"$WORK/out"
				#|cat "$WORK/out"
				#|printf 'lines %s\n' "$(grep -c 'from ' "$WORK/out")"
			End

			When call driver
			The status should equal 0
			The output should include " chain-1 | from 1"
			The output should include "chain-12 | from 12"
			# One line a chain, and every one of them accounted for.
			The output should include "lines 12"
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
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done" \
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
			The output should include "[.] slow cancelled"
		End

		# The chain is a shell of its own, so killing it on its pid alone
		# leaves whatever it was running still running: the compiler
		# outlives the build that gave up on it. Where the shell can put a
		# chain in a process group of its own, the whole group goes, and
		# what the chain started goes with it however deep it is.
		It "kills what a cancelled chain started, not only the chain"
			Skip if "this shell leaves a background job in its own process group" no_process_groups

			Data
				#|set -eu
				#|. "$LIB"
				#|chain "slow" \
				#|	"sh -c 'sleep 30 & printf %s \$! >\"$WORK/childpid\"; sleep 30'"
				#|chain "quick" \
				#|	"until [ -f '$WORK/childpid' ]; do sleep 1; done" \
				#|	"exit 4"
				#|run
			End

			When call driver
			The status should equal 4
			The output should include "[.] slow cancelled"
			The value "$(process_state "$WORK/childpid")" should equal "stopped"
		End

		# Cancelling asks a chain to go and then waits for it, so that the
		# chain is gone before the group it leads is taken and there is
		# nobody left to announce the killing. A chain that never answers
		# would hold that wait, and the build, open for ever. It gets GRACE
		# polls and then the signal nothing can ignore.
		#
		# GRACE is five here only so the example does not sit through the
		# default; what is being tested is that the wait ends at all.
		It 'gives up on a chain that will not answer the signal'
			Data
				#|set -eu
				#|GRACE=5
				#|. "$LIB"
				#|chain "deaf" \
				#|	"trap '' TERM; touch '$WORK/deaf-started'" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|chain "quick" \
				#|	"until [ -f '$WORK/deaf-started' ]; do sleep 1; done" \
				#|	"exit 8"
				#|run
			End

			When call driver
			The status should equal 8
			The output should include "[.] deaf cancelled"
			# The driver reached its own end rather than being killed by
			# the harness, which is the whole of the claim.
			The stderr should not include "did not finish within"
		End
	End

	# A chain is a process, and a process can be taken away: the signal no
	# process can catch, the machine running out of memory. It leaves no
	# status behind when it goes, and nothing is ever going to write one, so
	# waiting for one is waiting for ever.
	Describe 'a chain that is killed from outside'
		It 'reports it rather than waiting for a status that will never come'
			Data
				#|set -eu
				#|. "$LIB"
				#|chain "victim" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|printf '%s\n' "$!" >"$WORK/chainpid"
				#|( sleep 1; kill -9 "$(cat "$WORK/chainpid")" ) &
				#|run
			End

			When call driver
			# 137 is what a shell reports for a child SIGKILL took, and is
			# here because `run` has to return something. What the report
			# says is that the chain was killed, which is what happened.
			The status should equal 137
			The output should include "[!] victim killed"
			The stderr should not include "did not finish within"
		End
	End

	# A build script is entitled to its own shell options and its own
	# variables, and the library is a guest in that shell.
	Describe 'the script that sourced it'
		It "leaves the caller's own variables alone"
			Data
				#|set -eu
				#|. "$LIB"
				#|i=alpha n=beta cmd=gamma code=delta label=epsilon
				#|mark=zeta seen=eta line=theta pending=iota pad=kappa ec=lambda
				#|chain "guest" "printf 'ran\n'"
				#|run >/dev/null
				#|printf '%s\n' "$i $n $cmd $code $label $mark $seen $line $pending $pad $ec"
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal \
				"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
		End

		# noclobber turns every plain > into a refusal to overwrite, and the
		# library rewrites one file on every poll. Without saying that it
		# means to, a build that set -C would lose every line after the
		# first one and get a complaint a poll instead.
		It 'streams under a caller that set -C'
			Data
				#|set -euC
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "first" "printf 'the first line\n'"
				#|chain "second" \
				#|	"until grep -q 'the first line' '$WORK/out' 2>/dev/null ||
				#|		[ ! -d '$WORK' ]; do sleep 1; done" \
				#|	"printf 'the second line\n'"
				#|run >"$WORK/out"
				#|cat "$WORK/out"
			End

			When call driver
			The status should equal 0
			# The second chain only writes once it has seen the first
			# chain's line already printed, so both lines here means at
			# least two polls wrote a chunk, and the second one worked.
			The output should include " first | the first line"
			The output should include "second | the second line"
			The stderr should equal ""
		End

		It 'groups under a caller that set -C'
			Data
				#|set -euC
				#|STREAM=0
				#|. "$LIB"
				#|chain "slow" \
				#|	"touch '$WORK/slow-started'" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|chain "broken" \
				#|	"until [ -f '$WORK/slow-started' ]; do sleep 1; done" \
				#|	"exit 2"
				#|run
			End

			When call driver
			The status should equal 2
			The output should include "[.] slow cancelled"
			The output should include "[!] broken exited 2"
			The stderr should equal ""
		End

		# Nothing a chain runs has any business reading the build's input,
		# and a shell with job control would otherwise hand it over: the
		# chain would eat what the script was going to read.
		It "leaves the build's stdin to the build"
			Data
				#|set -eu
				#|printf 'first line\nsecond line\n' >"$WORK/input"
				#|exec <"$WORK/input"
				#|. "$LIB"
				#|chain "greedy" "cat >'$WORK/eaten'"
				#|run >/dev/null
				#|printf 'the script read: '
				#|head -n 1
			End

			When call driver
			The status should equal 0
			The output should equal "the script read: first line"
			The value "$(cat "$WORK/eaten")" should equal ""
		End
	End

	# A command in a chain runs in the chain's own shell, so the names that
	# shell is using are names the command can take away. Everything the
	# library keeps there starts with an underscore for that reason: a build
	# step counting with `i`, or keeping a status in `code`, would otherwise
	# move the file the chain reports itself through and leave `run` waiting
	# on a chain that had already finished.
	Describe 'a chain command that uses ordinary variable names'
		It 'runs and reports like any other'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "common" \
				#|	"i=3 n=99 code=7 cmd=x label=y work=z; printf 'one\n'" \
				#|	"printf 'two\n'"
				#|run
				#|printf 'run returned %s\n' "$?"
			End

			When call driver
			The status should equal 0
			The output should include "common | one"
			The output should include "common | two"
			The output should include "run returned 0"
			The stderr should not include "did not finish within"
		End
	End

	# The bar between a label and its line is a box drawing character where
	# the locale says the terminal can show one, and an ASCII pipe where it
	# does not. The library reads the locale rather than assuming it, and it
	# is written in ASCII itself so that a shell reading it in the C locale
	# has nothing to choke on.
	Describe 'the locale'
		It 'uses an ASCII bar where the locale is not UTF-8'
			Data
				#|set -eu
				#|LC_ALL=C
				#|export LC_ALL
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "one | a line"
		End

		It 'uses a box drawing bar where the locale is UTF-8'
			Data
				#|set -eu
				#|LC_ALL=C.UTF-8
				#|export LC_ALL
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "one $(printf '\342\224\202') a line"
			# A shell without that locale installed says so, and the bar is
			# chosen from the name rather than from the locale itself, so
			# the complaint changes nothing here.
			The stderr should not include "did not finish within"
		End
	End

	# A colour a chain, so a line's chain reads without reading the label.
	# Nothing here has a terminal to be asked about, and every example
	# below asks for colour outright and reads the escapes back out.
	Describe 'colour'
		It 'gives each chain a colour of its own'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|COLOR=1
				#|. "$LIB"
				#|chain "one" "printf 'first line\n'"
				#|chain "two" "printf 'second line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			# The colour opens before the label and closes after the bar,
			# so what the command wrote is left exactly as it wrote it.
			The output should include "$(sgr 36)one |$(sgr 0) first line"
			The output should include "$(sgr 35)two |$(sgr 0) second line"
		End

		# The default, and what a build gets when it pipes its output
		# somewhere or reads it back from a file: the plain text, which is
		# also what greps for the outcome lines rely on.
		It 'leaves the labels plain where the output is not a terminal'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should equal "one | a line"
		End

		It 'starts the palette again once it runs out'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|COLOR=1
				#|COLOR_PALETTE='31 32'
				#|. "$LIB"
				#|chain "one" "printf 'a\n'"
				#|chain "two" "printf 'b\n'"
				#|chain "the" "printf 'c\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "$(sgr 31)one |$(sgr 0) a"
			The output should include "$(sgr 32)two |$(sgr 0) b"
			The output should include "$(sgr 31)the |$(sgr 0) c"
		End

		# An entry is passed to the terminal as it stands, so anything SGR
		# understands is a colour a build can ask for.
		It 'takes the colours from COLOR_PALETTE'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|COLOR=1
				#|COLOR_PALETTE='1;35'
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should equal "$(sgr '1;35')one |$(sgr 0) a line"
		End

		# A palette emptied on purpose is a build asking for no colour by
		# another name, and there is nothing left for the reset to close.
		It 'colours nothing where the palette is empty'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|COLOR=1
				#|COLOR_PALETTE=''
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should equal "one | a line"
		End

		It 'colours the label a chain ended on, and not the mark'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|COLOR=1
				#|. "$LIB"
				#|chain "one" "exit 3"
				#|run || printf 'run returned %s\n' "$?"
			End

			When call driver
			The status should equal 0
			The output should include "[!] $(sgr 36)one$(sgr 0) exited 3"
			The output should include "run returned 3"
		End

		It 'colours the heading of a grouped chain'
			Data
				#|set -eu
				#|STREAM=0
				#|COLOR=1
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "--- $(sgr 36)one$(sgr 0)"
			The output should include "a line"
		End

		# The four say so in this order, each overruling the one before it,
		# and only the last two can be tested without a terminal to be
		# asked about.
		Describe 'what decides'
			It 'is turned on by FORCE_COLOR where there is no terminal'
				Data
					#|set -eu
					#|STREAM_SEP='|'
					#|FORCE_COLOR=1
					#|. "$LIB"
					#|chain "one" "printf 'a line\n'"
					#|run
				End

				When call driver
				The status should equal 0
				The output should equal "$(sgr 36)one |$(sgr 0) a line"
			End

			# FORCE_COLOR=0 is how a good many tools are told to stop, so
			# it is read as a refusal and not as the name being set.
			It 'is turned off by FORCE_COLOR=0'
				Data
					#|set -eu
					#|STREAM_SEP='|'
					#|COLOR=auto
					#|FORCE_COLOR=0
					#|. "$LIB"
					#|chain "one" "printf 'a line\n'"
					#|run
				End

				When call driver
				The status should equal 0
				The output should equal "one | a line"
			End

			It 'has FORCE_COLOR overrule NO_COLOR'
				Data
					#|set -eu
					#|STREAM_SEP='|'
					#|NO_COLOR=1
					#|FORCE_COLOR=1
					#|. "$LIB"
					#|chain "one" "printf 'a line\n'"
					#|run
				End

				When call driver
				The status should equal 0
				The output should equal "$(sgr 36)one |$(sgr 0) a line"
			End

			It 'has COLOR overrule both'
				Data
					#|set -eu
					#|STREAM_SEP='|'
					#|COLOR=0
					#|NO_COLOR=1
					#|FORCE_COLOR=1
					#|. "$LIB"
					#|chain "one" "printf 'a line\n'"
					#|run
				End

				When call driver
				The status should equal 0
				The output should equal "one | a line"
			End
		End
	End

	# STREAM=0 holds each chain's output and prints it in one block instead,
	# in declaration order, which is what a build that would rather read the
	# whole of a chain at once asks for.
	Describe 'grouped output'
		It "prints each chain's output in one block"
			Data
				#|set -eu
				#|STREAM=0
				#|. "$LIB"
				#|chain "first" "printf 'one output\n'"
				#|chain "second" "printf 'two output\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should match pattern "*--- first*one output*--- second*two output*"
		End

		It 'marks a chain that failed and one that was cancelled'
			Data
				#|set -eu
				#|STREAM=0
				#|. "$LIB"
				#|chain "slow" \
				#|	"touch '$WORK/slow-started'" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|chain "broken" \
				#|	"until [ -f '$WORK/slow-started' ]; do sleep 1; done" \
				#|	"printf 'the reason\n'; exit 2"
				#|run
			End

			When call driver
			The status should equal 2
			# Grouped output is in declaration order all the way down, so
			# every line of it is known. Lines rather than a pattern: a
			# bracket is a set in a glob, `[!]` a set that opens by
			# negating itself, and ksh93 will not match a pattern of
			# several parts against a subject this long anyway.
			The line 2 of output should equal "... slow"
			The line 3 of output should equal "[.] slow cancelled"
			The line 5 of output should equal "[!] broken"
			The line 6 of output should equal "the reason"
			The line 7 of output should equal "[!] broken exited 2"
		End

		# A chain whose last line never got a newline would otherwise have
		# the line below it printed onto the end of it.
		It 'keeps the closing line off the end of an unfinished one'
			Data
				#|set -eu
				#|STREAM=0
				#|. "$LIB"
				#|chain "abrupt" "printf 'no newline here'; exit 5"
				#|run
			End

			When call driver
			The status should equal 5
			The line 2 of output should equal "[!] abrupt"
			The line 3 of output should equal "no newline here"
			The line 4 of output should equal "[!] abrupt exited 5"
		End

		It "collects a command's stdout and stderr into its own group"
			Data
				#|set -eu
				#|STREAM=0
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
				#|STREAM=0
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
		# Everything the library keeps is under one directory, so there is
		# nowhere for its bookkeeping to go if it cannot have one. Without
		# saying so it would write `1.log` and `1.code` into whatever
		# directory the build happened to be run from.
		It 'stops rather than scatter its files when it can have no temp directory'
			Skip if "this shell brings its own mktemp, so a fake cannot stand in for it" mktemp_is_builtin

			Data
				#|set -eu
				#|mkdir -p "$WORK/bin"
				#|printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/mktemp"
				#|chmod +x "$WORK/bin/mktemp"
				#|PATH="$WORK/bin:$PATH"
				#|export PATH
				#|cd "$WORK"
				#|. "$LIB"
				#|printf 'kept going\n'
			End

			When call driver
			The status should equal 1
			The output should not include "kept going"
			The stderr should include "could not create a temporary directory"
			The file "$WORK/1.log" should not be exist
		End

		# TMPDIR is wherever the machine says, and on a laptop that is a
		# path with a space in it often enough.
		It 'works where the temp directory has a space in its path'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|mkdir -p "$WORK/a spaced dir"
				#|TMPDIR="$WORK/a spaced dir"
				#|export TMPDIR
				#|. "$LIB"
				#|printf '%s\n' "$_work" >"$WORK/workdir"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "one | a line"
			The value "$(reported_workdir)" should include "a spaced dir"
			The directory "$(reported_workdir)" should not be exist
		End

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
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|run
			End

			When call driver_interrupted
			The status should equal 130
			The directory "$(reported_workdir)" should not be exist
		End

		# A signal is the one way out that the cancel path never sees, so
		# unless the library stops the chains itself an interrupted build
		# leaves whatever it started still running. That is its own bug,
		# since the point of Ctrl-C is that the compiler stops too, and it
		# is also what stalls CI: a macOS runner does not finish a step while
		# a process the step started is alive, so a chain nobody killed
		# holds the job open until it times out, minutes after the suite
		# has passed.
		It 'stops the chain it started when it is interrupted'
			Data
				#|set -eu
				#|. "$LIB"
				#|printf '%s\n' "$$" >"$WORK/pid"
				#|chain "slow" \
				#|	"touch '$WORK/started'" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|printf '%s\n' "$!" >"$WORK/chainpid"
				#|run
			End

			When call driver_interrupted
			The status should equal 130
			The value "$(chain_state)" should equal "stopped"
		End
	End

	# What `run` does unless a build asks for grouping: each line as it
	# arrives, under the label of the chain it came from.
	Describe 'streaming'
		It 'labels every line with the chain it came from'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "npm" "printf 'one\n'; printf 'two\n'"
				#|chain "composer" "printf 'three\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "     npm | one"
			The output should include "     npm | two"
			The output should include "composer | three"
		End

		# The labels are right aligned to the longest of them, so the bars
		# line up whatever the chains are called.
		It 'pads the labels to the same width'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "a" "printf 'short\n'"
				#|chain "a-much-longer-one" "printf 'long\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "                a | short"
			The line 2 of output should equal "a-much-longer-one | long"
		End

		# The point of it: the parent prints what a chain wrote while the
		# other chains are still going. The second chain here waits to see
		# the first chain's line in what `run` has already printed, which it
		# can only do if the line was printed before either chain finished.
		It 'prints a line while the chains are still running'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "first" "printf 'the first line\n'"
				#|chain "second" \
				#|	"until grep -q 'the first line' '$WORK/out' 2>/dev/null ||
				#|		[ ! -d '$WORK' ]; do sleep 1; done" \
				#|	"printf 'saw it\n'"
				#|run >"$WORK/out"
				#|cat "$WORK/out"
			End

			When call driver
			The status should equal 0
			The output should include "second | saw it"
		End

		# A line is a line once it has its newline. A chain that writes one
		# in two goes gets one labelled line, not two.
		It 'waits for a half-written line to be finished'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "half" "printf 'a line'; sleep 1; printf ' in two writes\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "half | a line in two writes"
		End

		It 'prints a last line that never got its newline'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "abrupt" "printf 'no newline here'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "abrupt | no newline here"
		End

		# What is left to say when the output has gone by: the chain that
		# failed, and the chains that were cancelled with it. Nothing about
		# the chain that finished, which said so as it went.
		It 'ends on what failed and what was cancelled with it'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "fine" "printf 'all good\n'"
				#|chain "slow" \
				#|	"touch '$WORK/slow-started'" \
				#|	"until [ -f '$WORK/done' ] || [ ! -d '$WORK' ]; do sleep 1; done"
				#|chain "broken" \
				#|	"until [ -f '$WORK/slow-started' ]; do sleep 1; done" \
				#|	"exit 3"
				#|run
			End

			When call driver
			The status should equal 3
			The output should include "fine | all good"
			The output should not include "--- fine"
			The output should include "[.] slow cancelled"
			The output should include "[!] broken exited 3"
		End

		# The poll is the only thing printing, so two chains that write at
		# the same moment come out as whole lines one after the other
		# rather than as halves of each other.
		It 'keeps the lines whole when two chains write at once'
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "aaa" \
				#|	"i=0; while [ \$i -lt 300 ]; do printf 'AAAAAAAAAA\n'; i=\$((i + 1)); done"
				#|chain "bbb" \
				#|	"i=0; while [ \$i -lt 300 ]; do printf 'BBBBBBBBBB\n'; i=\$((i + 1)); done"
				#|run >"$WORK/out"
				#|printf 'lines %s, malformed %s\n' \
				#|	"$(grep -c . "$WORK/out")" \
				#|	"$(grep -cv '^\(aaa\|bbb\) | [AB]\{10\}$' "$WORK/out" || true)"
			End

			When call driver
			The status should equal 0
			The output should equal "lines 600, malformed 0"
		End

		It "labels what a command writes to stderr as well"
			Data
				#|set -eu
				#|STREAM_SEP='|'
				#|. "$LIB"
				#|chain "noisy" "printf 'to stdout\n'; printf 'to stderr\n' >&2"
				#|run
			End

			When call driver
			The status should equal 0
			The output should include "noisy | to stdout"
			The output should include "noisy | to stderr"
			The stderr should equal ""
		End

		It 'takes the bar between label and line from STREAM_SEP'
			Data
				#|set -eu
				#|STREAM_SEP='>>'
				#|. "$LIB"
				#|chain "one" "printf 'a line\n'"
				#|run
			End

			When call driver
			The status should equal 0
			The line 1 of output should equal "one >> a line"
		End
	End
End

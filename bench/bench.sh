#!/bin/sh
# shellcheck shell=sh
# Benchmarks for parallel.sh. POSIX sh, like the library it measures.
#
# A scenario is a build, described as the chains it is made of, and every
# step in it is a `sleep` as long as that step usually takes. The same steps
# then run twice: once in declaration order, the way a `set -e` script runs
# them, and once as chains. The difference between the two is the whole of
# what this measures.
#
# Sleeps stand in for the work because the shape of a build is what changes
# here, not the work in it: `sleep` waits without competing for a core, a
# disk or a network link, so these numbers are the ones a build gets when
# its steps are mostly waiting on something other than each other. Steps
# that each saturate the machine will not see them.
#
#   ./bench/bench.sh              every scenario, three runs each
#   REPS=1 ./bench/bench.sh       one run each
#   SCALE=0.25 ./bench/bench.sh   a quarter of every duration
#   SHELL_UNDER_TEST=/bin/bash ./bench/bench.sh
#
# It exits non-zero if a scenario was not faster in chains than in order,
# which is the only assertion here: the times themselves are a report, and
# a machine slow enough to change them by a few percent should not fail a
# build over it.

set -u

REPS=${REPS:-3}
SCALE=${SCALE:-1}
SHELL_UNDER_TEST=${SHELL_UNDER_TEST:-/bin/sh}

_here=$(dirname "$0")
LIB=${LIB:-$_here/../parallel.sh}
if [ ! -f "$LIB" ]; then
	printf 'no parallel.sh at %s\n' "$LIB" >&2
	exit 1
fi
# The generated scripts are run from elsewhere, so the library needs a path
# that does not depend on where they run from.
LIB=$(cd "$(dirname "$LIB")" && pwd)/$(basename "$LIB")

_work=$(mktemp -d "${TMPDIR:-/tmp}/parallel-bench.XXXXXX")
trap 'rm -rf "$_work"' EXIT
trap 'rm -rf "$_work"; exit 130' INT
trap 'rm -rf "$_work"; exit 143' TERM

_slower='' # scenarios that chains did not help, filled in as they run

# Milliseconds since the epoch, from whatever this machine happens to have.
# GNU date takes %3N and BSD date does not, so the clock is chosen once, by
# trying each candidate and keeping the first that answers with a plausible
# number of digits. Whole seconds are the last resort: the report says which
# clock it used, because a scenario timed to the second is worth less than
# one timed to the millisecond.
_clock=seconds
_now() {
	case $_clock in
	date) date +%s%3N ;;
	perl) perl -MTime::HiRes -e 'printf "%.0f", Time::HiRes::time() * 1000' ;;
	python) python3 -c 'import time; print(int(time.time() * 1000))' ;;
	*) printf '%s000' "$(date +%s)" ;;
	esac
}

_pick_clock() {
	for _c in date perl python; do
		_clock=$_c
		_t=$(_now 2>/dev/null) || _t=''
		case $_t in
		'' | *[!0-9]*) continue ;;
		esac
		[ "${#_t}" -ge 13 ] && return 0
	done
	_clock=seconds
}

# A chain is written "label:seconds|label:seconds": steps in order, each one
# the length it takes. A duration ending in ! is a step that fails when it
# is done, which is how a scenario says where the failure is.
_steps() { printf '%s\n' "$1" | tr '|' '\n'; }

_label() {
	_first=${1%%|*}
	printf '%s' "${_first%:*}"
}

_seconds() {
	_d=${1##*:}
	_d=${_d%!}
	awk -v d="$_d" -v s="$SCALE" 'BEGIN { printf "%g", d * s }'
}

_command() {
	case ${1##*:} in
	*!) printf 'sleep %s; exit 1' "$(_seconds "$1")" ;;
	*) printf 'sleep %s' "$(_seconds "$1")" ;;
	esac
}

# The build as a script that runs its steps in order and stops at the first
# failure, which is what it looked like before.
_write_ordered() {
	{
		printf '#!/bin/sh\nset -e\n'
		for _chain in "$@"; do
			_steps "$_chain" | while IFS= read -r _step; do
				printf '%s\n' "$(_command "$_step")"
			done
		done
	} >"$_work/ordered.sh"
}

# The same build as chains.
_write_chained() {
	{
		printf '#!/bin/sh\n. "%s"\n' "$LIB"
		for _chain in "$@"; do
			printf 'chain "%s"' "$(_label "$_chain")"
			_steps "$_chain" | while IFS= read -r _step; do
				printf ' "%s"' "$(_command "$_step")"
			done
			printf '\n'
		done
		printf 'run\n'
	} >"$_work/chained.sh"
}

# One run, in milliseconds. A scenario that ends in a failure exits
# non-zero by design, so the status is not the point and is thrown away.
_time() {
	_start=$(_now)
	"$SHELL_UNDER_TEST" "$1" >/dev/null 2>&1 || :
	_end=$(_now)
	printf '%s' "$((_end - _start))"
}

# The best of REPS runs, not the mean: a run can only be made slower by
# whatever else the machine was doing, so the fastest one is the closest to
# what was actually being measured.
_best() {
	_min=''
	_i=1
	while [ "$_i" -le "$REPS" ]; do
		_ms=$(_time "$1")
		if [ -z "$_min" ] || [ "$_ms" -lt "$_min" ]; then
			_min=$_ms
		fi
		_i=$((_i + 1))
	done
	printf '%s' "$_min"
}

_secs() { awk -v ms="$1" 'BEGIN { printf "%.2fs", ms / 1000 }'; }

_ratio() {
	if [ "$2" -le 0 ]; then
		printf '-'
		return 0
	fi
	awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1fx", a / b }'
}

_row() { printf '%-32s %11s %11s %9s\n' "$1" "$2" "$3" "$4"; }

scenario() {
	_name=$1
	shift
	_write_ordered "$@"
	_write_chained "$@"
	_ordered=$(_best "$_work/ordered.sh")
	_chained=$(_best "$_work/chained.sh")
	_row "$_name" "$(_secs "$_ordered")" "$(_secs "$_chained")" \
		"$(_ratio "$_ordered" "$_chained")"
	[ "$_chained" -lt "$_ordered" ] || _slower="$_slower
  $_name"
}

# What the library costs when there is nothing to gain: eight chains that do
# nothing at all, so the time is one mktemp, eight forks and a poll or two.
# Any scenario above is that much slower than the build it describes.
_overhead() {
	{
		printf '#!/bin/sh\n. "%s"\n' "$LIB"
		_i=1
		while [ "$_i" -le 8 ]; do
			printf 'chain "chain %s" ":"\n' "$_i"
			_i=$((_i + 1))
		done
		printf 'run\n'
	} >"$_work/overhead.sh"
	_best "$_work/overhead.sh"
}

_pick_clock

printf 'parallel.sh benchmarks\n'
printf 'shell %s, clock %s, poll %s, best of %s, scale %s\n\n' \
	"$SHELL_UNDER_TEST" "$_clock" "${POLL:-0.1}" "$REPS" "$SCALE"

_row 'scenario' 'in order' 'in chains' 'speedup'
_row '--------' '--------' '---------' '-------'

# A PHP app with a front end: composer waits on nothing npm does, and npm
# waits on nothing composer does, but a script runs them one after the other
# anyway. The npm steps are a chain because the build needs its own
# dependencies first.
scenario 'PHP app with a front end' \
	'composer install:4' \
	'npm ci:5|npm run build:2'

# The checks a CI job runs over a monorepo, all four independent of each
# other. This is the shape chains are best at: the build takes as long as
# its longest check instead of as long as all of them.
scenario 'CI checks, four of them' \
	'lint:1' \
	'typecheck:3' \
	'unit tests:5' \
	'build:3'

# The same checks, with the lint failing. In order, the failure is found
# only once everything ahead of it has run, and where that is depends on
# where the failing step sits in the script; in chains it is found as soon
# as it happens, whatever else is still going.
scenario 'A failing lint' \
	'unit tests:5' \
	'lint:1!'

# One step much longer than the rest, which is where the gain runs out: the
# build can never finish before its longest chain does, so the most chains
# can do is hide everything else behind it.
scenario 'One dominant step' \
	'npm run build:6' \
	'composer install:3' \
	'php artisan migrate:1'

_row '--------' '--------' '---------' '-------'
printf '\neight empty chains: %s\n' "$(_secs "$(_overhead)")"

case $_slower in
'') ;;
*)
	printf '\nnot faster in chains than in order:%s\n' "$_slower" >&2
	exit 1
	;;
esac

# Default target is `check`. Written for both GNU make and BSD make, since
# CI runs it on FreeBSD too.

SHELLSPEC_VERSION = 0.28.1
SHELLSPEC = .tools/bin/shellspec

# Extra flags for the suite, e.g. `make test SHELLSPEC_FLAGS="--shell dash"`.
SHELLSPEC_FLAGS =

# The library, the example and the benchmarks: POSIX sh, formatted, no
# bashisms.
SCRIPTS = parallel.sh examples/build.sh bench/bench.sh

# The spec files are POSIX sh as well and get checked, but not formatted:
# shellspec's Describe, It and End are ordinary commands, so shfmt sees no
# nesting to keep and flattens the whole file to one column.
SPECS = spec/parallel_spec.sh spec/spec_helper.sh

.PHONY: check lint ascii test bench install-dev

check: lint test

lint: ascii
	shellcheck --shell=sh $(SCRIPTS) $(SPECS)
	checkbashisms $(SCRIPTS)
	shfmt -ln posix -d $(SCRIPTS)

# Nothing here is anything but printable ASCII, comments included. A shell
# reads a script through the locale, and yash in the C locale refuses one
# carrying a byte sequence that locale cannot make a character of, which is
# the locale a build container has when nobody set one. The box drawing bar
# is written as its bytes in the one place it is needed.
ascii:
	! LC_ALL=C grep -n '[^[:print:][:blank:]]' $(SCRIPTS) $(SPECS)

test:
	@[ -x $(SHELLSPEC) ] || { echo "$(SHELLSPEC) is missing: make install-dev" >&2; exit 1; }
	$(SHELLSPEC) $(SHELLSPEC_FLAGS)

# Not part of `check`: it is minutes of sleeping, and it reports rather than
# asserts. Takes REPS, SCALE and SHELL_UNDER_TEST from the environment.
bench:
	./bench/bench.sh

# Into .tools, which is gitignored.
install-dev:
	curl -fsSL https://raw.githubusercontent.com/shellspec/shellspec/$(SHELLSPEC_VERSION)/install.sh \
		| sh -s $(SHELLSPEC_VERSION) --yes --prefix "$$PWD/.tools"

# Default target is `check`. Written for both GNU make and BSD make, since
# CI runs it on FreeBSD too.

SHELLSPEC_VERSION = 0.28.1
SHELLSPEC = .tools/bin/shellspec

# Extra flags for the suite, e.g. `make test SHELLSPEC_FLAGS="--shell dash"`.
SHELLSPEC_FLAGS =

# The library and the example: POSIX sh, formatted, no bashisms.
SCRIPTS = parallel.sh examples/build.sh

# The spec files are POSIX sh as well and get checked, but not formatted:
# shellspec's Describe, It and End are ordinary commands, so shfmt sees no
# nesting to keep and flattens the whole file to one column.
SPECS = spec/parallel_spec.sh spec/spec_helper.sh

.PHONY: check lint test install-dev

check: lint test

lint:
	shellcheck --shell=sh $(SCRIPTS) $(SPECS)
	checkbashisms $(SCRIPTS)
	shfmt -ln posix -d $(SCRIPTS)

test:
	@[ -x $(SHELLSPEC) ] || { echo "$(SHELLSPEC) is missing: make install-dev" >&2; exit 1; }
	$(SHELLSPEC) $(SHELLSPEC_FLAGS)

# Into .tools, which is gitignored.
install-dev:
	curl -fsSL https://raw.githubusercontent.com/shellspec/shellspec/$(SHELLSPEC_VERSION)/install.sh \
		| sh -s $(SHELLSPEC_VERSION) --yes --prefix "$$PWD/.tools"

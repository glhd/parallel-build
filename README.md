# Parallel Build

[![CI](https://github.com/glhd/parallel-build/actions/workflows/ci.yml/badge.svg)](https://github.com/glhd/parallel-build/actions/workflows/ci.yml)

`parallel.sh` runs chains of commands at the same time, stops everything at
the first failure, and prints each chain's output in one block instead of
interleaved. It is POSIX sh, one file, and nothing else, so it runs in a
build container as it is.

Before, where `npm` waits on `composer` for no reason:

```sh
#!/bin/sh
set -e
composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
npm ci --audit false
npm run build
```

After:

```sh
#!/bin/sh
set -e
. ./parallel.sh

chain "composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader"
chain "npm ci --audit false" "npm run build"

run
```

When something fails, the failure is at the bottom and the rest is grouped
above it:

```
--- composer install
Installing dependencies
Generating autoload files

[!] npm build
added 214 packages
building for production...
[!] npm build exited 1

... assets
[.] assets cancelled
```

## Install

It is one file. Vendor it:

```sh
curl -fsSLO https://raw.githubusercontent.com/glhd/parallel-build/main/parallel.sh
```

or fetch it in the build itself:

```sh
curl -fsSL https://raw.githubusercontent.com/glhd/parallel-build/main/parallel.sh -o /tmp/parallel.sh
. /tmp/parallel.sh
```

## API

`chain <label> <command> [command...]` declares a chain. Its commands run in
order, each one only if the one before it succeeded, and the chain stops at
the first failure. Each command is a string, evaluated by the shell, so
pipes, redirects and `&&` work inside one.

`run` waits for every chain, prints their output in the order they were
declared, and returns the exit code of the chain that failed, or 0. The
first failure cancels the chains still running. Because `run` returns that
code, it can be the last line of a build script:

```sh
run
```

Nothing else is public. `chain` and `run` are meant to be called once each,
in that order.

## POLL

`run` polls for finished chains, by default every `0.1` seconds. Fractional
sleeps are not in POSIX, and a `sleep` that rejects them is detected on the
first poll, after which polling falls back to whole seconds. Set `POLL` for
a different interval and `POLL_WHOLE` for a different fallback:

```sh
POLL=0.5 . ./parallel.sh
```

## Caveats

`kill` stops a cancelled chain's shell, not its grandchildren. A command
that spawned its own children can leave one behind that outlives the chain
it belonged to. In a build container that exits anyway this does not matter;
in a long-lived shell it will.

Fractional `sleep` is not in POSIX, though both GNU coreutils and BSD accept
it. Whole seconds are the fallback, not the default, so a build on a shell
without fractional sleep finishes up to a second later than it might.

Under zsh, a script with `set -e` whose `run` fails leaves the temp
directory behind: zsh skips `EXIT` traps when errexit is triggered by a
function returning non-zero. Every other shell, and every other exit path
under zsh, removes it.

The library has no `local`, because POSIX sh has none. It keeps its own
state in names starting with `_`, but its loops use `i`, `n`, `cmd`, `code`,
`label` and `mark`, and sourcing it will clobber those in the calling
script.

## Prior art

- `make -j --output-sync=target` — parallelism and grouped output, if the build is already a Makefile.
- GNU `parallel --halt now,fail=1 --group` — the same idea with far more of everything, and a dependency.
- [mise](https://mise.jdx.dev) — task runner with parallel tasks and dependencies, for projects that have adopted it.
- [concurrently](https://github.com/open-cli-tools/concurrently) — the npm equivalent, if Node is a given.

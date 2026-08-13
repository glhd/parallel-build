#!/bin/sh
set -u

# The directory comes out into a variable first so that the dot has a single
# word after it: checkbashisms reads the space inside the substitution as a
# second argument to `.`, which really would be unportable, and shellcheck
# needs the directive to know which file this is.
_here=$(dirname "$0")
# shellcheck source=../parallel.sh
. "$_here/../parallel.sh"

chain "composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader"

chain "npm ci --audit false" "npm run build"

run

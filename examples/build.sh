#!/bin/sh
set -u

_cwd=$(dirname "$0")
# shellcheck source=../parallel.sh
. "$_cwd/../parallel.sh"

chain "composer dependencies" \
	"composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader"

chain "build assets" \
	"npm ci --audit false" \
	"npm run build"

run

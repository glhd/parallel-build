#!/bin/sh
set -u

. "$(dirname "$0")/../parallel.sh"

chain "composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader"

chain "npm ci --audit false" "npm run build"

run
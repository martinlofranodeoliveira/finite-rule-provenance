#!/bin/sh
set -e
if (set -o pipefail 2>/dev/null); then
    set -o pipefail
fi
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

mkdir -p dist
if [ ! -f "dist/finite-rule-provenance" ]; then
    raco exe -o dist/finite-rule-provenance bin/cli.rkt
fi

if [ "$#" -eq 0 ]; then
    ./dist/finite-rule-provenance demo --assert
elif [ "$1" = "--assert" ]; then
    ./dist/finite-rule-provenance demo "$@"
else
    ./dist/finite-rule-provenance "$@"
fi

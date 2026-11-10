#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"
mkdir -p dist
raco exe -o dist/finite-rule-provenance bin/cli.rkt
raco distribute dist/distribution dist/finite-rule-provenance

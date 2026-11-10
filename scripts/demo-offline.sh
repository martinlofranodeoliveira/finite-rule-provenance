#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
# Explicit build/test/package steps create the distribution. No runtime compiler.
exec "$PROJECT_ROOT/dist/distribution/bin/finite-rule-provenance" demo "$@"

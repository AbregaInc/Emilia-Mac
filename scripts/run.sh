#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d dist/Emilia.app || bash scripts/build-app.sh
# Only the configuration path is passed. The secret is never in process arguments.
export EMILIA_ENV_FILE="$PWD/.env"
# Local v8 bundle/runtime are configured under Application Support (or explicit EMILIA_V8_* overrides).
exec dist/Emilia.app/Contents/MacOS/Emilia --show

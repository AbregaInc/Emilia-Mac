#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d dist/Emilia.app || bash scripts/build-app.sh
# Only the configuration path is passed. The secret is never in process arguments.
export EMILIA_ENV_FILE="$PWD/.env"
if [ -f Models/VoiceModel/manifest.json ]; then export EMILIA_VOICE_MODEL_DIR="$PWD/Models/VoiceModel"; fi
exec dist/Emilia.app/Contents/MacOS/Emilia --show

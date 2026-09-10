#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# No Keychain storage: credentials are supplied only for this invocation.
if [ -n "${APPLE_API_KEY_PATH:-}" ]; then
    : "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID}"
    : "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER}"
    xcrun notarytool submit dist/Emilia-macOS-arm64.zip \
        --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait
else
    : "${APPLE_ID:?Set APPLE_ID}"
    : "${APPLE_APP_PASSWORD:?Set an app-specific password}"
    : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
    xcrun notarytool submit dist/Emilia-macOS-arm64.zip \
        --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
fi
xcrun stapler staple dist/Emilia.app
xcrun stapler validate dist/Emilia.app
ditto -c -k --sequesterRsrc --keepParent dist/Emilia.app dist/Emilia-macOS-arm64.zip
shasum -a 256 dist/Emilia-macOS-arm64.zip

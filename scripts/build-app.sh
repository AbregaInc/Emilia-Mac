#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -f Models/ggml-base.en.bin || { echo 'Run bash scripts/setup-whisper.sh first.'; exit 1; }
test -f Models/AASISTBaseline/aasist-l.mlmodel || { echo 'Run bash scripts/setup-baseline.sh first.'; exit 1; }
swift build -c release --product Emilia
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
app=dist/Emilia.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Emilia "$app/Contents/MacOS/Emilia"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Models/ggml-base.en.bin "$app/Contents/Resources/ggml-base.en.bin"
cp THIRD_PARTY_NOTICES "$app/Contents/Resources/THIRD_PARTY_NOTICES"
cp .deps/whisper.cpp/LICENSE "$app/Contents/Resources/whisper.cpp-LICENSE"
cp Resources/Whisper-LICENSE "$app/Contents/Resources/Whisper-LICENSE"
cp Resources/AASIST-LICENSE "$app/Contents/Resources/AASIST-LICENSE"
xcrun coremlcompiler compile Models/AASISTBaseline/aasist-l.mlmodel "$app/Contents/Resources"
cp Models/AASISTBaseline/manifest.json "$app/Contents/Resources/aasist-baseline-manifest.json"
identity="${SIGNING_IDENTITY:--}"
if [ "$identity" = - ]; then
    codesign --force --sign - --entitlements Resources/Emilia.entitlements "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" --entitlements Resources/Emilia.entitlements "$app"
fi
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Emilia-macOS-arm64.zip
echo "Built $app and dist/Emilia-macOS-arm64.zip"

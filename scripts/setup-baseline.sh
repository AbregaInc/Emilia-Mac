#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Models/AASISTBaseline
model=Models/AASISTBaseline/aasist-l.mlmodel
checksum=10d9c39ed442b9b2fb16c596237bca2c629ff4a0b93c7ddabfe2d55dbb600de7
if [ ! -f "$model" ]; then
    curl --fail --location --retry 3 \
        https://github.com/AbregaInc/Emilia-Mac/releases/download/v0.3.0/aasist-l.mlmodel \
        --output "$model.partial"
    echo "$checksum  $model.partial" | shasum -a 256 --check
    mv "$model.partial" "$model"
fi
echo "$checksum  $model" | shasum -a 256 --check
cp docs/baseline-manifest.json Models/AASISTBaseline/manifest.json

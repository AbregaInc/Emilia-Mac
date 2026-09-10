#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=2eeeba56e9edd762b4b38467bab96c2517163158
mkdir -p .deps Models
if [ ! -d .deps/whisper.cpp/.git ]; then
    git clone --quiet https://github.com/ggml-org/whisper.cpp.git .deps/whisper.cpp
fi
git -C .deps/whisper.cpp checkout --quiet "$revision"
cmake -S .deps/whisper.cpp -B .deps/whisper.cpp/build \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON
cmake --build .deps/whisper.cpp/build --config Release -j 6
model=Models/ggml-base.en.bin
checksum=a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002
if [ ! -f "$model" ]; then
    curl --fail --location --retry 3 \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin \
        --output "$model.partial"
    echo "$checksum  $model.partial" | shasum -a 256 --check
    mv "$model.partial" "$model"
fi
echo "$checksum  $model" | shasum -a 256 --check

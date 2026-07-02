#!/usr/bin/env bash
# Clone whisper.cpp, build static libs with embedded Metal, install to ./vendor/dist
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p vendor
if [ ! -d vendor/whisper.cpp ]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
fi
cd vendor/whisper.cpp
# Deployment target: keep below common installed macOS versions so the app runs
# on older Macs (not just the build host's OS). The linker stamps the final
# binary's minos to the MAX across all objects, so the libs must match the app.
DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_ACCELERATE=ON
cmake --build build --config Release -j
cmake --install build --prefix "$ROOT/vendor/dist"
echo "=== installed libs ==="
ls -1 "$ROOT/vendor/dist/lib" 2>/dev/null || true

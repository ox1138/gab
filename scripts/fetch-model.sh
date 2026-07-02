#!/usr/bin/env bash
# Download a ggml Whisper model into ~/Library/Application Support/gab/
# Usage: scripts/fetch-model.sh [base.en|large-v3-turbo]   (default: base.en)
set -euo pipefail

MODEL="${1:-base.en}"
DEST="$HOME/Library/Application Support/gab"
FILE="ggml-${MODEL}.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${FILE}"

mkdir -p "$DEST"
if [ -f "$DEST/$FILE" ]; then
  echo "Already have $DEST/$FILE"
  exit 0
fi

echo "Downloading $FILE -> $DEST"
curl -L --fail --progress-bar -o "$DEST/$FILE" "$URL"
echo "Done: $DEST/$FILE"
echo
echo "It will appear in gab's menu bar Model submenu automatically — pick it there."

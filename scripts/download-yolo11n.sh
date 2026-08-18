#!/usr/bin/env bash
# Download Ultralytics YOLO11s Core ML (COCO + NMS) into OmniAR/Models/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-yolo11s}"
DEST="$ROOT/OmniAR/Models/${NAME}.mlpackage"
URL="https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/${NAME}.mlpackage.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
curl -L --fail -o "$TMP/model.zip" "$URL"
unzip -q -o "$TMP/model.zip" -d "$TMP/unpacked"
rm -rf "$DEST"
mkdir -p "$DEST"
if [[ -f "$TMP/unpacked/Manifest.json" ]]; then
  cp -R "$TMP/unpacked/Manifest.json" "$TMP/unpacked/Data" "$DEST/"
else
  pkg="$(find "$TMP/unpacked" -name 'Manifest.json' -print -quit | xargs dirname)"
  cp -R "$pkg/Manifest.json" "$pkg/Data" "$DEST/"
fi
echo "Installed → $DEST"
du -sh "$DEST"

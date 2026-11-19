#!/usr/bin/env bash
# Install Apple's optional Tiny YOLOv3 (8-bit LUT) object detector.
# Source: https://developer.apple.com/machine-learning/models/
# This is a third-party model resource: download locally, not into Git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/MacGroundStation/Models/GroundStationDetector.mlmodel"
SOURCE="https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel"

if [[ -s "$OUTPUT" ]]; then
  echo "Detector already installed at $OUTPUT"
  echo "To reinstall, manually move aside the existing model."
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"
TEMP="$OUTPUT.partial"
trap 'rm -f "$TEMP"' EXIT

echo "Downloading Apple's YOLOv3 Tiny Int8 Core ML model (~9 MB) ..."
curl --fail --show-error --silent --location --retry 3 \
     --connect-timeout 20 --max-time 240 \
     "$SOURCE" --output "$TEMP"

BYTES=$(wc -c < "$TEMP" | tr -d ' ')
if (( BYTES < 1000000 || BYTES > 25000000 )); then
  echo "Unexpected model file size: $BYTES bytes; aborting." >&2
  exit 1
fi

mv "$TEMP" "$OUTPUT"
echo "Model downloaded: $OUTPUT"
echo "Xcode will compile it into GroundStationDetector.mlmodelc."
echo "Next: run xcodegen generate and build the MacGroundStation scheme."

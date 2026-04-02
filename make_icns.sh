#!/bin/bash

# Script to create .icns from a single 1024x1024 PNG
SOURCE_PNG="AppIcon.png"
OUTPUT_ICNS="AppIcon.icns"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "Error: $SOURCE_PNG not found."
    exit 1
fi

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Proper naming and sizing for iconutil
sips -z 16 16     "$SOURCE_PNG" --out "${ICONSET}/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32     "$SOURCE_PNG" --out "${ICONSET}/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 32 32     "$SOURCE_PNG" --out "${ICONSET}/icon_32x32.png" > /dev/null 2>&1
sips -z 64 64     "$SOURCE_PNG" --out "${ICONSET}/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128   "$SOURCE_PNG" --out "${ICONSET}/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256   "$SOURCE_PNG" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$SOURCE_PNG" --out "${ICONSET}/icon_256x256.png" > /dev/null 2>&1
sips -z 512 512   "$SOURCE_PNG" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$SOURCE_PNG" --out "${ICONSET}/icon_512x512.png" > /dev/null 2>&1
sips -z 1024 1024 "$SOURCE_PNG" --out "${ICONSET}/icon_512x512@2x.png" > /dev/null 2>&1

# Convert iconset to icns
echo "📦 Converting iconset to icns..."
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"

if [ -f "$OUTPUT_ICNS" ]; then
    rm -rf "$ICONSET"
    echo "✅ Successfully created $OUTPUT_ICNS"
else
    echo "❌ Failed to create $OUTPUT_ICNS"
    exit 1
fi

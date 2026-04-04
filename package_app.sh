#!/bin/bash

# SlideRev App Packaging Script
# 🚀 V37.20: Automated macOS Bundle Creation

set -e

APP_NAME="SlideRev"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 [Packager] Starting build for release..."
# 1. Build the executable in release mode
swift build -c release --target ${APP_NAME}

# 2. Find the compiled binary
# Detecting architecture (arm64 or x86_64)
ARCH=$(uname -m)
BINARY_PATH=".build/release/${APP_NAME}"
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=".build/${ARCH}-apple-macosx/release/${APP_NAME}"
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ [Error] Binary not found at $BINARY_PATH"
    exit 1
fi

echo "🏗️ [Packager] Creating Bundle structure..."
# 3. Create App Bundle structure
rm -rf "${BUNDLE_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. Copy Assets
echo "📂 [Packager] Copying resources..."
cp "$BINARY_PATH" "${MACOS_DIR}/"
cp Info.plist "${CONTENTS_DIR}/"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/"
fi

# Deep-Copy CoreML Model
echo "🧠 [Packager] Embedding CoreML Model..."
if [ -d "3rd/coremlama/LaMa.mlmodelc" ]; then
    cp -R "3rd/coremlama/LaMa.mlmodelc" "${RESOURCES_DIR}/"
else
    echo "⚠️ [Warning] Model LaMa.mlmodelc not found in 3rd/coremlama/"
fi

# 5. Finalize
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ [Packager] Successfully created ${BUNDLE_NAME}"
echo "🚀 [Packager] You can now launch it using: open ${BUNDLE_NAME}"

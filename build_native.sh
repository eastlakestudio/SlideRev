#!/bin/bash

# SlideRev macOS Universal Build Script (v0.9.8 - Production Prep)
set -e

APP_NAME="SlideRev"
BUNDLE_NAME="AI Slide Editor"
BUNDLE_ID="com.eastlakestudio.sliderev"
VERSION="1.0.1"
BUILD_DIR="build_app"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${BUNDLE_NAME}.app"
INFO_PLIST="Info.plist"
ENTITLEMENTS="SlideRev.local.entitlements"

# Final Placement: pdf2pptx/SlideRev_v1.0.0.app
FINAL_PRODUCT="${BUNDLE_NAME}_v${VERSION}.app"

echo "🚀 Starting Universal Build (arm64 + x86_64) for ${APP_NAME} v${VERSION}..."

# 1. Increment Build Version (CFBundleVersion)
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}")
NEXT_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEXT_BUILD}" "${INFO_PLIST}"
echo "🔢 Build Version incremented: ${CURRENT_BUILD} -> ${NEXT_BUILD}"

# 2. Clean
echo "🧹 Cleaning previous builds..."
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
rm -rf "${FINAL_PRODUCT}"
mkdir -p "${BUILD_DIR}/arm64"
mkdir -p "${BUILD_DIR}/x86_64"
mkdir -p "${DIST_DIR}"

# 3. Compile for arm64
echo "🍎 Compiling for arm64 via SPM..."
swift build -c release --arch arm64

# 4. Compile for x86_64
echo "💎 Compiling for x86_64 (Intel) via SPM..."
swift build -c release --arch x86_64

# 5. Create Universal Binary using lipo
echo "🔗 Combining into Universal Binary..."
lipo -create \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}" \
    -output "${BUILD_DIR}/${APP_NAME}"

# 6. Structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
# 🚀 v38.5: Native ZIPFoundation integrated. No more zip_tool/unzip_tool needed.
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 7. Metadata Sync (Final check)
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${BUNDLE_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"

# 8. Resources
# 🚀 v36.0: Hard Check for Critical Resources
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

if [ -d "PPTXTemplate" ]; then
    cp -R "PPTXTemplate" "${APP_BUNDLE}/Contents/Resources/"
    echo "📁 Expanded Template 'PPTXTemplate' bundled successfully."
else
    echo "❌ ERROR: 'PPTXTemplate' folder not found. Please run 'mkdir PPTXTemplate && unzip empty.pptx -d PPTXTemplate' first."
    exit 1
fi

# 🚀 v45.0: Automatic Model Check
if [ ! -d "3rd/coremlama/LaMa.mlmodelc" ]; then
    echo "🧠 Missing AI Model. Dynamic downloading and preparing..."
    ./prepare_lama_model.sh
fi

if [ -d "3rd/coremlama/LaMa.mlmodelc" ]; then
    cp -R "3rd/coremlama/LaMa.mlmodelc" "${APP_BUNDLE}/Contents/Resources/"
    echo "🧠 AI Model 'LaMa.mlmodelc' bundled successfully."
else
    echo "⚠️ WARNING: 'LaMa.mlmodelc' not found in 3rd/coremlama/. Inpainting might be disabled."
fi

# 9. Code Signing (Ad-hoc with Entitlements)
echo "🔐 Applying Sandboxing Entitlements & Ad-hoc Signing..."
codesign --force --options runtime --entitlements "${ENTITLEMENTS}" --sign - "${APP_BUNDLE}"

echo "✅ App Bundle Created: ${APP_BUNDLE}"

# 10. LOCAL PLACEMENT
echo "📦 Moving to final local destination: ./${FINAL_PRODUCT}..."
mv "${APP_BUNDLE}" "./${FINAL_PRODUCT}"

echo "✨ UNIVERSAL BUILD SUCCESS: ./${FINAL_PRODUCT} (Build v${NEXT_BUILD})"

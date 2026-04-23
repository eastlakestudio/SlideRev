#!/bin/bash

# SlideRev Unified Build Script (v56.0 - Dual Mode Support)
# Usage: ./appstore_package.sh [--dev | --appstore]

set -e

# --- Configuration ---
APP_NAME="SlideRev"
BUNDLE_NAME="AI Slide Editor"
BUNDLE_ID="com.eastlakestudio.sliderev"
VERSION="1.0.1"
BUILD_DIR="build_archive"
DIST_DIR="dist_archive"
APP_BUNDLE="${DIST_DIR}/${BUNDLE_NAME}.app"
PKG_OUT="${DIST_DIR}/${BUNDLE_NAME}.pkg"
INFO_PLIST="Info.plist"

# Signing Identities
APP_CERT="Apple Distribution: Xinyu Liu (J4RT98GF7B)"
INSTALLER_CERT="3rd Party Mac Developer Installer: Xinyu Liu (J4RT98GF7B)"
ENTITLEMENTS="SlideRev.entitlements" # Production entitlements
DEBUG_ENTITLEMENTS="SlideRev.debug.entitlements" # Local debug entitlements

PROVISIONING_PROFILE="docs/SlideRev_Distribute_MacOS.provisionprofile"

# --- Argument Parsing ---
MODE="appstore" # Default to production
if [ "$1" == "--dev" ] || [ "$1" == "-d" ]; then
    MODE="dev"
elif [ "$1" == "--appstore" ] || [ "$1" == "-a" ]; then
    MODE="appstore"
fi

echo "🚀 Starting SlideRev Build for Mode: ${MODE} v${VERSION}..."

# 1. Clean & Prepare
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

if [ "$MODE" == "dev" ]; then
    # --- DEVELOPMENT MODE ---
    echo "🛠 [1/4] Compiling Debug Build (Local Arch)..."
    swift build # Default architecture for fast debug
    
    echo "📁 [2/4] Structuring Debug App Bundle..."
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"
    
    # Copy Debug binary (assuming default .build path)
    cp ".build/debug/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
    cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
    echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"
    
    # Strip Team IDs from Info.plist to prevent sandbox mismatch in debug
    /usr/libexec/PlistBuddy -c "Delete :LSApplicationCategoryType" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.productivity" "${APP_BUNDLE}/Contents/Info.plist"
    
    # Copy Resources
    if [ -f "AppIcon.icns" ]; then cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"; fi
    if [ -d "PPTXTemplate" ]; then cp -R "PPTXTemplate" "${APP_BUNDLE}/Contents/Resources/"; fi
    if [ -d "3rd/coremlama/LaMa.mlmodelc" ]; then cp -R "3rd/coremlama/LaMa.mlmodelc" "${APP_BUNDLE}/Contents/Resources/"; fi

    echo "🔐 [3/4] Ad-hoc Signing for Local Test..."
    # 🚀 Key Fix: Use debug entitlements and sign with '-' to allow local execution
    xattr -cr "${APP_BUNDLE}"
    codesign --force --deep --entitlements "${DEBUG_ENTITLEMENTS}" --sign - "${APP_BUNDLE}"

    echo "🎉 [4/4] Local Build Ready: ${APP_BUNDLE}"
    echo "👉 Run: open ${APP_BUNDLE}"

else
    # --- PRODUCTION MODE ---
    echo "🍎 [1/5] Compiling Universal Release Build..."
    swift build -c release --arch arm64
    swift build -c release --arch x86_64
    
    echo "🔗 [2/5] Creating Universal Binary..."
    lipo -create \
        ".build/arm64-apple-macosx/release/${APP_NAME}" \
        ".build/x86_64-apple-macosx/release/${APP_NAME}" \
        -output "${BUILD_DIR}/${APP_NAME}"
    
    echo "📁 [3/5] Structuring Production App Bundle..."
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"
    cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
    cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
    echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"
    
    if [ -f "$PROVISIONING_PROFILE" ]; then cp "$PROVISIONING_PROFILE" "${APP_BUNDLE}/Contents/embedded.provisionprofile"; fi
    if [ -f "AppIcon.icns" ]; then cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"; fi
    if [ -d "PPTXTemplate" ]; then cp -R "PPTXTemplate" "${APP_BUNDLE}/Contents/Resources/"; fi
    if [ -d "3rd/coremlama/LaMa.mlmodelc" ]; then cp -R "3rd/coremlama/LaMa.mlmodelc" "${APP_BUNDLE}/Contents/Resources/"; fi

    echo "🔐 [4/5] Deep Signing with Distribution Certificate..."
    xattr -cr "${APP_BUNDLE}"
    codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS}" --sign "$APP_CERT" --timestamp=http://timestamp.apple.com/ts01 "${APP_BUNDLE}"
    
    echo "📦 [5/5] Packaging into .pkg..."
    productbuild --component "${APP_BUNDLE}" /Applications --sign "$INSTALLER_CERT" "${PKG_OUT}"
    
    echo "✅ ARCHIVE SUCCESS: ${PKG_OUT}"
fi

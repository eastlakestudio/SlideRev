#!/bin/bash

# SlideRev App Store Archiver (v39.6 - Production Submission)
# Usage: ./appstore_package.sh

set -e

# --- Configuration ---
APP_NAME="SlideRev"
BUNDLE_ID="com.eastlakestudio.sliderev"
VERSION="0.9.8"
BUILD_DIR="build_archive"
DIST_DIR="dist_archive"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
PKG_OUT="${DIST_DIR}/${APP_NAME}.pkg"
INFO_PLIST="Info.plist"
ENTITLEMENTS="SlideRev.entitlements"

# ==============================================================================
APP_CERT="Apple Distribution: Xinyu Liu (J4RT98GF7B)"
INSTALLER_CERT="3rd Party Mac Developer Installer: Xinyu Liu (J4RT98GF7B)"
BUNDLE_ID="com.eastlakestudio.sliderev"

# 🚀 v41.1: 新增描述文件配置（请将路径替换为您下载的 .provisionprofile 文件）
# 下载地址：https://developer.apple.com/account/resources/profiles/list
PROVISIONING_PROFILE="docs/SlideRev_Distribute_MacOS.provisionprofile"

echo "🚀 Starting Production Archive for ${APP_NAME} v${VERSION}..."

# 1. Clean & Prepare
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BUILD_DIR}/arm64"
mkdir -p "${BUILD_DIR}/x86_64"
mkdir -p "${DIST_DIR}"

# 2. Universal Build (Release Mode)
echo "🍎 [1/5] Compiling for arm64..."
swift build -c release --arch arm64
echo "💎 [2/5] Compiling for x86_64..."
swift build -c release --arch x86_64

echo "🔗 [3/5] Creating Universal Binary..."
lipo -create \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}" \
    -output "${BUILD_DIR}/${APP_NAME}"

# 3. Structure App Bundle
echo "📁 [4/5] Structuring App Bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Sync Info.plist
/usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.productivity" "${APP_BUNDLE}/Contents/Info.plist"

# 🚀 v41.1: 嵌入描述文件 (Provisioning Profile)
if [ -n "$PROVISIONING_PROFILE" ] && [ -f "$PROVISIONING_PROFILE" ]; then
    echo "📜 [4.5/5] Embedding Provisioning Profile..."
    cp "$PROVISIONING_PROFILE" "${APP_BUNDLE}/Contents/embedded.provisionprofile"
else
    echo "⚠️ WARNING: No provisioning profile found at '$PROVISIONING_PROFILE'. TestFlight submission may fail."
fi

# Copy Resources
if [ -f "AppIcon.icns" ]; then cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"; fi
if [ -d "PPTXTemplate" ]; then cp -R "PPTXTemplate" "${APP_BUNDLE}/Contents/Resources/"; fi
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

# 4. Deep Signing with Timestamp
echo "🔐 [5/5] Deep Signing with Apple Distribution certificate..."
# 🚀 v42.0: 清理扩展属性，防止签名验证失败
xattr -cr "${APP_BUNDLE}"
# 🚀 v39.6: 使用系统内置默认时间戳通道 (App Store 强制要求)
codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS}" --sign "$APP_CERT" --timestamp=http://timestamp.apple.com/ts01 "${APP_BUNDLE}"

# 5. Packaging
echo "📦 Packaging into .pkg for App Store submission..."
productbuild --component "${APP_BUNDLE}" /Applications --sign "$INSTALLER_CERT" "${PKG_OUT}"

echo "--------------------------------------------------------"
echo "✅ ARCHIVE SUCCESS: ${PKG_OUT}"
echo "--------------------------------------------------------"
echo "👉 Next Steps:"
echo "1. Open 'Transporter' app from Mac App Store."
echo "2. Drag '${PKG_OUT}' into Transporter."
echo "3. Click 'Deliver' to upload to App Store Connect."
echo "--------------------------------------------------------"

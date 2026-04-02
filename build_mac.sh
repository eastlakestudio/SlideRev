#!/bin/bash

# SlideReverse macOS Build Script
echo "🚀 開始準備打包 SlideReverse..."

# 1. 檢查環境
if ! command -v pyinstaller &> /dev/null
then
    echo "❌ 找不到 PyInstaller，請執行: pip install pyinstaller"
    exit
fi

# 2. 清理舊的構建文件
echo "🧹 清理舊的構建目錄..."
rm -rf build dist

# 3. 執行 PyInstaller 打包
# --windowed: 不顯示控制台視窗
# --noconsole: macOS 下同 windowed
# --name: 應用程式名稱
# --icon: 圖標 (如果有的話，目前設為預設)
# --add-data: 包含 PaddleOCR 可能需要的非代碼文件 (需根據實際路徑調整)
# --hidden-import: 添加可能的隱式依賴

echo "📦 正在使用 PyInstaller 打包 (這可能需要幾分鐘)..."

pyinstaller --noconsole \
    --windowed \
    --name "SlideReverse" \
    --clean \
    --add-data "core.py:." \
    --hidden-import "PIL._tkinter_finder" \
    --hidden-import "paddleocr" \
    --hidden-import "paddle" \
    --hidden-import "cv2" \
    --hidden-import "pptx" \
    main.py

echo "✅ 打包完成！"
echo "📂 您可以在 dist/ 目錄下找到 SlideReverse.app"
echo "⚠️ 注意：首次執行時，PaddleOCR 可能仍會嘗試下載模型檔案至 ~/.paddleocr"

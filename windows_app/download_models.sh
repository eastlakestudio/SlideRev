#!/usr/bin/env bash

# Ultimate OCR Model Downloader for macOS/Linux (Proxy Accelerated)
# Set error handling
set -e

MODELS_DIR="assets/models"
mkdir -p "$MODELS_DIR"

echo -e "\033[1;33m--- Ultimate OCR Model Downloader (Proxy Accelerated) ---\033[0m"

# 清理可能存在的残留
rm -f "$MODELS_DIR/ocr_det.onnx"
rm -f "$MODELS_DIR/ocr_rec.onnx"
rm -f "$MODELS_DIR/ppocr_keys_v1.txt"

# 1. 下载检测模型 (v5)
echo -e "\033[1;36mDownloading PP-OCRv5 Detection Model...\033[0m"
curl -k -L -o "$MODELS_DIR/ocr_det.onnx" "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/detection/v5/det.onnx?download=true"

# 2. 下载识别模型 (v5)
echo -e "\033[1;36mDownloading PP-OCRv5 Recognition Model...\033[0m"
curl -k -L -o "$MODELS_DIR/ocr_rec.onnx" "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/chinese/rec.onnx?download=true"

# 3. 下载字典 (v5)
echo -e "\033[1;36mDownloading PP-OCRv5 Dictionary...\033[0m"
curl -k -L -o "$MODELS_DIR/ppocr_keys_v1.txt" "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/chinese/dict.txt?download=true"

# 4. 下载 LaMa 模型
echo -e "\033[1;36mDownloading LaMa ONNX Model (~208MB)...\033[0m"
curl -k -L -o "$MODELS_DIR/lama_fp32.onnx" "https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx?download=true"

echo -e "\n\033[1;33mFinal Verification:\033[0m"
for file in "$MODELS_DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        filesize=$(du -h "$file" | cut -f1)
        if [ ! -s "$file" ]; then
            echo -e "\033[1;31mFAIL: $filename download failed.\033[0m"
        else
            echo -e "\033[1;32mSUCCESS: $filename ($filesize)\033[0m"
        fi
    fi
done

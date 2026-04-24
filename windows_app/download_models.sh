#!/bin/bash

set -e # Stop on error

# Create assets directory
mkdir -p assets/models

echo "Downloading LaMa ONNX Model (208MB)..."
# Use a verified working URL for LaMa ONNX
curl -L -o assets/models/lama_fp32.onnx "https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx?download=true"

echo "Downloading OCR Text Detection Model (4MB)..."
# Use a verified working URL for PaddleOCR Detection (ONNX)
curl -L -o assets/models/ocr_model.onnx "https://huggingface.co/SWHL/RapidOCR/resolve/main/ch_PP-OCRv3_det_infer.onnx?download=true"

# Verify file sizes to ensure they are not just error HTML pages
LAMA_SIZE=$(wc -c <"assets/models/lama_fp32.onnx")
if [ "$LAMA_SIZE" -lt 1000000 ]; then
    echo "Error: LaMa model download failed or file too small ($LAMA_SIZE bytes)"
    exit 1
fi

echo "Models downloaded successfully to assets/models/"
ls -lh assets/models/

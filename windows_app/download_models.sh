#!/bin/bash

set -e # Stop on error

# Create assets directory
mkdir -p assets/models

download_model() {
    local url=$1
    local output=$2
    local name=$3
    echo "Downloading $name..."
    # -f: Fail silently on server errors
    # -L: Follow redirects
    # --retry: Retry on transient errors
    curl -fL --retry 3 --retry-delay 5 -o "$output" "$url"
}

# LaMa ONNX (~208MB)
download_model "https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx?download=true" "assets/models/lama_fp32.onnx" "LaMa Model"

# OCR Detection (~4MB)
download_model "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv3/ch_PP-OCRv3_det_infer.onnx?download=true" "assets/models/ocr_model.onnx" "OCR Model"

# Verify file sizes
LAMA_SIZE=$(wc -c <"assets/models/lama_fp32.onnx")
OCR_SIZE=$(wc -c <"assets/models/ocr_model.onnx")

echo "Verification: LaMa size = $LAMA_SIZE, OCR size = $OCR_SIZE"

if [ "$LAMA_SIZE" -lt 100000000 ]; then # Expecting > 100MB
    echo "Error: LaMa model is too small. Download likely corrupted."
    exit 1
fi

if [ "$OCR_SIZE" -lt 1000000 ]; then # Expecting > 1MB
    echo "Error: OCR model is too small."
    exit 1
fi

echo "Models downloaded and verified successfully."
ls -lh assets/models/

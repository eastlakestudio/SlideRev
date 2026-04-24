#!/bin/bash

# Create assets directory
mkdir -p assets/models

echo "Downloading LaMa ONNX Model..."
# Downloading LaMa FP32 model from a public HuggingFace repo (lama-cleaner)
wget -q --show-progress -O assets/models/lama_fp32.onnx https://huggingface.co/Sanster/lama-cleaner/resolve/main/lama_fp32.onnx

echo "Downloading OCR ONNX Model (Sample/Dummy structure for now)..."
# In a real scenario, this would be a URL to a PaddleOCR ONNX model or similar
# Here we touch a dummy file so that the path exists for the build.
touch assets/models/ocr_model.onnx

echo "Models downloaded successfully to assets/models/"

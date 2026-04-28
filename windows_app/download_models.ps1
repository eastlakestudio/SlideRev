$modelsDir = "assets/models"
if (!(Test-Path $modelsDir)) {
    New-Item -ItemType Directory -Path $modelsDir
}

Write-Host "--- Ultimate OCR Model Downloader (Proxy Accelerated) ---" -ForegroundColor Yellow

# 强制清理之前的残留
Remove-Item -Path "$modelsDir/ocr_det.onnx" -ErrorAction SilentlyContinue
Remove-Item -Path "$modelsDir/ocr_rec.onnx" -ErrorAction SilentlyContinue
Remove-Item -Path "$modelsDir/ppocr_keys_v1.txt" -ErrorAction SilentlyContinue

# 使用 GHProxy 代理 GitHub 源，这是目前最稳定的免费加速方案
$proxyPrefix = "https://ghfast.top/" # 或者 https://mirror.ghproxy.com/

# 1. 下载检测模型 (Det)
Write-Host "Downloading OCR Detection Model (v3)..." -ForegroundColor Cyan
curl.exe -k -L -o "$modelsDir/ocr_det.onnx" "$($proxyPrefix)https://raw.githubusercontent.com/Kazuhito00/PaddleOCRv3-ONNX-Sample/main/ppocr_onnx/model/det_model/ch_PP-OCRv3_det_infer.onnx"

# 2. 下载识别模型 (Rec)
Write-Host "Downloading OCR Recognition Model (v3)..." -ForegroundColor Cyan
curl.exe -k -L -o "$modelsDir/ocr_rec.onnx" "$($proxyPrefix)https://raw.githubusercontent.com/Kazuhito00/PaddleOCRv3-ONNX-Sample/main/ppocr_onnx/model/rec_model/ch_PP-OCRv3_rec_infer.onnx"

# 3. 下载字典 (Dict)
Write-Host "Downloading OCR Dictionary..." -ForegroundColor Cyan
curl.exe -k -L -o "$modelsDir/ppocr_keys_v1.txt" "$($proxyPrefix)https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/release/2.6/ppocr/utils/ppocr_keys_v1.txt"

Write-Host "`nFinal Verification:" -ForegroundColor Yellow
$files = Get-ChildItem $modelsDir
foreach ($file in $files) {
    if ($file.Length -lt 1KB) {
        Write-Host "FAIL: $($file.Name) download failed. Please check if you can access github.com." -ForegroundColor Red
    } else {
        Write-Host "SUCCESS: $($file.Name) ($([Math]::Round($file.Length/1MB, 2)) MB)" -ForegroundColor Green
    }
}

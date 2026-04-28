$modelsDir = "assets/models"
if (!(Test-Path $modelsDir)) { New-Item -ItemType Directory -Path $modelsDir }

Write-Host "--- Fixing remaining OCR files ---" -ForegroundColor Yellow

# 删除之前失败的 145 字节残留
Remove-Item -Path "$modelsDir/ocr_det.onnx" -ErrorAction SilentlyContinue
Remove-Item -Path "$modelsDir/ppocr_keys_v1.txt" -ErrorAction SilentlyContinue

# 换一个更强的代理源 (ghproxy.net)
$proxy = "https://gh-proxy.com/"

Write-Host "Downloading Detection Model..."
curl.exe -k -L -o "$modelsDir/ocr_det.onnx" "$($proxy)https://raw.githubusercontent.com/Kazuhito00/PaddleOCRv3-ONNX-Sample/main/ppocr_onnx/model/det_model/ch_PP-OCRv3_det_infer.onnx"

Write-Host "Downloading Dictionary..."
curl.exe -k -L -o "$modelsDir/ppocr_keys_v1.txt" "$($proxy)https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/release/2.6/ppocr/utils/ppocr_keys_v1.txt"

Write-Host "`nVerifying..." -ForegroundColor Yellow
$det = Get-Item "$modelsDir/ocr_det.onnx" -ErrorAction SilentlyContinue
$dict = Get-Item "$modelsDir/ppocr_keys_v1.txt" -ErrorAction SilentlyContinue

if ($det -and $det.Length -gt 1MB) { Write-Host "SUCCESS: ocr_det.onnx" -ForegroundColor Green } else { Write-Host "FAIL: ocr_det.onnx" -ForegroundColor Red }
if ($dict -and $dict.Length -gt 10KB) { Write-Host "SUCCESS: ppocr_keys_v1.txt" -ForegroundColor Green } else { Write-Host "FAIL: ppocr_keys_v1.txt" -ForegroundColor Red }

import os
from huggingface_hub import snapshot_download

# 目標：下載 LaMa CoreML 模型
repo_id = "vladmandic/lama-coreml" # 这是一个社区维护的常用版本
local_dir = "models/LaMa.mlpackage"

print(f"🚀 開始下載模型 {repo_id} 到 {local_dir}...")

try:
    snapshot_download(
        repo_id=repo_id,
        local_dir=local_dir,
        local_dir_use_symlinks=False,
        # 只下載 mlpackage 相關文件，避免下載過多無關數據
        allow_patterns=["*.mlpackage/*", "Manifest.json", "Data/*"]
    )
    print("✅ 下載完成！")
except Exception as e:
    print(f"❌ 下載失敗: {e}")
    print("💡 嘗試備選方案...")
    # 可以添加備選 repo 或提示用戶

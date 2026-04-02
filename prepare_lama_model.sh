#!/bin/bash
echo "🚀 开始准备 LaMa 神经网络引擎..."

cd temp_coremlama || exit 1

# 检查 Python3
if ! command -v python3 &> /dev/null; then
    echo "❌ 错误：需要 python3 才能运行。"
    exit 1
fi

echo "1. 创建并激活 Python 虚拟环境..."
python3 -m venv venv
source venv/bin/activate

echo "2. 升级 pip..."
pip install --upgrade pip

echo "3. 安装依赖包 (若下载慢，请确保网络工具如 Clash 全局代理处于工作状态，或取消下方的代理注释)"
echo "3. 卸载环境变量代理，完全依赖网卡级 TUN 代理..."
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

# 安装必需的包 (强制使用官方源以避免清华源的 SSL 反爬拦截)
./venv/bin/pip3 install -i https://pypi.org/simple -r requirements.txt torchvision torchaudio coremltools "huggingface_hub<0.23.0"

echo "4. 正在下载并转换 LaMa 模型至 CoreML 格式 (.mlpackage)..."
./venv/bin/python3 convert_lama.py || {
    echo "❌ 模型转换失败。如果是网络超时，请检查代理并重新运行此脚本。"
    exit 1
}

echo "✅ 成功！LaMa.mlpackage 已生成于 temp_coremlama 目录下。"
echo "回到 Xcode 重新编译运行即可自动启用 AI 高保真无损背景修复。"

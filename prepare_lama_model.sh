#!/bin/bash
echo "🚀 开始准备 LaMa 神经网络引擎..."

# 确保 3rd 目录及其内容（动态下载）
if [ ! -d "3rd/coremlama" ]; then
    echo "📦 正在从 GitHub 下载 CoreMLaMa 工具..."
    mkdir -p 3rd
    git clone https://github.com/mallman/CoreMLaMa 3rd/coremlama || {
        echo "❌ 无法克隆 CoreMLaMa 仓库。请检查网络且确保 git 已安装。"
        exit 1
    }
fi

cd 3rd/coremlama || exit 1


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

# 安装必需的包 (使用仓库自带的 requirements.txt，并针对 Python 3.9 锁定关键兼容版本)
./venv/bin/pip3 install -i https://pypi.org/simple -r requirements.txt "huggingface_hub==0.23.1" "networkx<3.3"

echo "4. 正在下载并转换 LaMa 模型至 CoreML 格式 (.mlpackage)..."
./venv/bin/python3 convert_lama.py || {
    echo "❌ 模型转换失败。如果是网络超时，请检查代理并重新运行此脚本。"
    exit 1
}

echo "5. 正在将 .mlpackage 编译为 .mlmodelc (以供生产环境使用)..."
xcrun coremlcompiler compile LaMa.mlpackage . || {
    echo "⚠️ 编译失败。但 .mlpackage 已生成，Xcode 可能会在构建时处理它。"
}

echo "✅ 成功！LaMa.mlmodelc 已生成于 3rd/coremlama 目录下。"
echo "回到 Xcode 重新编译运行即可自动启用 AI 高保真无损背景修复。"

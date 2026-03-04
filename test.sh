#!/usr/bin/env bash
# 测试构建的 code-server 是否正常工作

set -euo pipefail

echo "🧪 测试 code-server..."
echo ""

if [ ! -L "result" ]; then
    echo "❌ 未找到构建结果，请先运行: nix build .#code-server"
    exit 1
fi

echo "📦 检查二进制文件..."
if [ ! -f "result/bin/code-server" ]; then
    echo "❌ 未找到 code-server 二进制文件"
    exit 1
fi
echo "✅ 二进制文件存在"

echo ""
echo "🔍 检查版本..."
VERSION=$(./result/bin/code-server --version 2>&1 | head -1 || true)
echo "版本: $VERSION"

echo ""
echo "🔍 检查帮助信息..."
./result/bin/code-server --help > /dev/null 2>&1
echo "✅ 帮助信息正常"

echo ""
echo "🎉 所有测试通过!"
echo ""
echo "💡 运行 code-server:"
echo "   ./result/bin/code-server"

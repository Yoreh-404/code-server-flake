#!/usr/bin/env bash
# 自动获取并更新 yarn cache 哈希值

set -euo pipefail

echo "🔨 尝试构建以获取正确的 yarn cache 哈希..."
echo ""

# 尝试构建，捕获输出
BUILD_OUTPUT=$(nix build .#code-server 2>&1 || true)

# 提取正确的哈希值
CORRECT_HASH=$(echo "$BUILD_OUTPUT" | grep -oP "got:\s+\K(sha256-[A-Za-z0-9+/=]+)" | head -1)

if [ -z "$CORRECT_HASH" ]; then
    echo "❌ 无法从构建输出中提取哈希值"
    echo ""
    echo "构建输出:"
    echo "$BUILD_OUTPUT"
    exit 1
fi

echo "✅ 找到正确的哈希: $CORRECT_HASH"
echo ""
echo "📝 更新 flake.nix..."

# 替换 fakeSha256 为正确的哈希
sed -i "s|pkgs\.lib\.fakeSha256|\"$CORRECT_HASH\"|g" flake.nix

echo "✅ flake.nix 已更新"
echo ""
echo "🔨 重新构建..."
nix build .#code-server

echo ""
echo "🎉 构建成功！"
echo ""
echo "运行 './result/bin/code-server --version' 查看版本"

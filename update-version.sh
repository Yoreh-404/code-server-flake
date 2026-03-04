#!/usr/bin/env bash
# 自动更新 code-server 到最新版本的脚本

set -euo pipefail

echo "🔍 获取 code-server 最新版本..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/^v//')
echo "✅ 最新版本: $LATEST_VERSION"

echo ""
echo "🔍 获取 git commit hash..."
COMMIT=$(git ls-remote https://github.com/coder/code-server.git "v$LATEST_VERSION" | cut -f1)
echo "✅ Commit: $COMMIT"

echo ""
echo "🔍 计算源码哈希..."
SRC_HASH=$(nix-prefetch-url --unpack "https://github.com/coder/code-server/archive/v$LATEST_VERSION.tar.gz" 2>&1 | tail -1)
echo "✅ 源码哈希: $SRC_HASH"

echo ""
echo "📝 更新 flake.nix..."

# 创建临时文件
cat > flake.nix.tmp << EOF
{
  description = "code-server package for NixOS - Latest version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.\${system};

        # 基于官方包进行 override，保持官方的构建逻辑
        code-server = pkgs.code-server.overrideAttrs (oldAttrs: rec {
          version = "$LATEST_VERSION";

          src = pkgs.fetchFromGitHub {
            owner = "coder";
            repo = "code-server";
            rev = "v\${version}";
            hash = "$SRC_HASH";
            fetchSubmodules = true;
          };

          # 更新 yarn cache - 第一次构建会失败并告诉你正确的哈希
          yarnCache = oldAttrs.yarnCache.overrideAttrs (old: {
            inherit src;
            # 运行 nix build .#code-server 2>&1 | grep "got:" 获取正确的哈希
            outputHash = pkgs.lib.fakeSha256;
          });

          # 注入 git commit（用于缓存和多语言支持）
          postPatch = (oldAttrs.postPatch or "") + ''
            substituteInPlace ./ci/build/build-vscode.sh \\
              --replace-fail '\$(git rev-parse HEAD)' "$COMMIT"
            substituteInPlace ./ci/build/build-release.sh \\
              --replace-fail '\$(git rev-parse HEAD)' "$COMMIT"
          '';
        });
      in
      {
        packages.default = code-server;
        packages.code-server = code-server;

        # 提供一个 app 方便直接运行
        apps.default = {
          type = "app";
          program = "\${code-server}/bin/code-server";
        };
      }
    );
}
EOF

mv flake.nix.tmp flake.nix

echo "✅ flake.nix 已更新"
echo ""
echo "📋 下一步操作："
echo "1. 运行 'nix flake update' 更新依赖"
echo "2. 运行 'nix build .#code-server' 进行首次构建"
echo "3. 构建会失败并显示正确的 yarnCache 哈希值"
echo "4. 复制显示的哈希值，替换 flake.nix 中的 pkgs.lib.fakeSha256"
echo "5. 再次运行 'nix build .#code-server' 完成构建"
echo ""
echo "💡 提示: 你也可以运行 './update-yarn-hash.sh' 自动完成步骤 3-4"

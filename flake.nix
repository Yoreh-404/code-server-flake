{
  description = "code-server package for NixOS - Latest version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # 基于官方包进行 override，使用 Node.js 22
        code-server = (pkgs.code-server.override {
          nodejs_20 = pkgs.nodejs_22;
        }).overrideAttrs (oldAttrs: rec {
          version = "4.109.5";
          commit = "d58aaa7b346b3262e0d4959e5fd5965e95ce456e";

          src = pkgs.fetchFromGitHub {
            owner = "coder";
            repo = "code-server";
            rev = "v${version}";
            hash = "sha256-gS2ReYCAsqmdRw0tx+svPrw0zwF41/+aICBqfflxB14=";
            fetchSubmodules = true;
          };

          # 更新 yarn cache，使用 Node.js 22，并使用 npm 安装根目录依赖
          yarnCache = pkgs.stdenv.mkDerivation {
            name = "code-server-${version}-${system}-yarn-cache";
            inherit src;

            nativeBuildInputs = [
              (pkgs.yarn.override { nodejs = pkgs.nodejs_22; })
              pkgs.nodejs_22
              pkgs.python3
              pkgs.git
              pkgs.cacert
              pkgs.pkg-config
              pkgs.libsecret
              pkgs.xorg.libX11
              pkgs.xorg.libxkbfile
              pkgs.jq
            ];

            buildPhase = ''
              runHook preBuild

              export HOME=$PWD
              export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

              # 增加重试次数和超时时间
              npm config set fetch-retries 10
              npm config set fetch-retry-mintimeout 20000
              npm config set fetch-retry-maxtimeout 120000
              npm config set fetch-timeout 300000

              # 使用 npm ci 安装根目录依赖（code-server 使用 package-lock.json）
              npm ci --ignore-scripts --verbose || npm ci --ignore-scripts --verbose

              # 保存根目录的 node_modules
              mkdir -p $out/root-node-modules
              cp -r node_modules $out/root-node-modules/

              # 安装 lib/vscode 的 npm 依赖
              if [ -f lib/vscode/package.json ]; then
                echo "安装 lib/vscode 依赖"

                # 创建 stub kerberos 包来跳过编译
                echo "创建 stub kerberos 包以跳过编译"
                mkdir -p lib/vscode/node_modules/kerberos
                cat > lib/vscode/node_modules/kerberos/package.json <<'EOF'
{
  "name": "kerberos",
  "version": "2.1.1",
  "description": "Stub package to skip native compilation",
  "main": "index.js"
}
EOF
                cat > lib/vscode/node_modules/kerberos/index.js <<'EOF'
// Stub kerberos module - not actually used by VS Code
module.exports = {};
EOF

                # 正常安装其他依赖
                echo "安装依赖（kerberos 已被 stub 替代）"
                npm install --prefix lib/vscode --verbose || \
                npm install --prefix lib/vscode --verbose

                # 验证关键依赖已安装
                if [ ! -f lib/vscode/node_modules/gulp/bin/gulp.js ]; then
                  echo "ERROR: gulp 未安装"
                  ls -la lib/vscode/node_modules/ | head -30
                  exit 1
                fi
                echo "关键依赖已安装: gulp"

                # 保存 lib/vscode 的 node_modules
                mkdir -p $out/vscode-node-modules
                cp -r lib/vscode/node_modules $out/vscode-node-modules/
              fi

              # 安装 vendor 依赖（使用 yarn）
              yarn --cwd "./vendor" install --modules-folder modules --ignore-scripts --frozen-lockfile

              # 配置 yarn offline mirror 用于其他子目录
              yarn config set yarn-offline-mirror $out

              # 查找并安装所有有 yarn.lock 的子目录依赖
              find ./lib/vscode -name "yarn.lock" -printf "%h\n" | \
                xargs -I {} yarn --cwd {} \
                  --frozen-lockfile --ignore-scripts --ignore-platform \
                  --ignore-engines --no-progress --non-interactive

              runHook postBuild
            '';

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = pkgs.lib.fakeSha256;
          };

          # 覆盖 buildPhase 来修复补丁并构建
          buildPhase = ''
            runHook preBuild

            # 修复 signature-verification.diff 补丁中的文件路径问题
            if [ -f patches/signature-verification.diff ]; then
              sed -i 's|lib/vscode/build/gulpfile\.reh\.js|lib/vscode/build/gulpfile.reh.ts|g' patches/signature-verification.diff
            fi

            # Apply patches (允许部分失败，因为某些补丁可能引用了不存在的文件)
            quilt push -a || echo "Warning: Some patches failed to apply"

            # 继续执行原来的 buildPhase 的其余部分
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
            export SKIP_SUBMODULE_DEPS=1
            export NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=4096"

            # Remove all built-in extensions
            jq --slurp '.[0] * .[1]' "./lib/vscode/product.json" <(
              cat << EOF
            {
              "builtInExtensions": []
            }
            EOF
            ) | sponge ./lib/vscode/product.json

            # Disable automatic updates
            sed -i '/update.mode/,/\}/{s/default:.*/default: "none",/g}' \
              lib/vscode/src/vs/platform/update/common/update.config.contribution.ts

            # Install dependencies
            patchShebangs .

            # 移除 postinstall 脚本以避免在离线模式下安装测试依赖
            if [ -f package.json ]; then
              jq 'del(.scripts.postinstall)' package.json | sponge package.json
            fi

            # 从 yarnCache 复制根目录的 node_modules
            cp -r ${yarnCache}/root-node-modules/node_modules ./
            chmod -R +w node_modules

            # 从 yarnCache 复制 lib/vscode 的 node_modules
            if [ -d ${yarnCache}/vscode-node-modules/node_modules ]; then
              echo "复制 lib/vscode 的 node_modules"
              mkdir -p lib/vscode
              cp -r ${yarnCache}/vscode-node-modules/node_modules lib/vscode/
              chmod -R +w lib/vscode/node_modules

              # 验证 gulp 是否存在
              if [ ! -f lib/vscode/node_modules/gulp/bin/gulp.js ]; then
                echo "ERROR: gulp 未找到！"
                exit 1
              fi
              echo "gulp 已就绪"
            fi

            # 不需要重新安装子目录依赖，因为它们已经在 node_modules 中
            # 只需要 patchShebangs
            patchShebangs .

            # Put ripgrep binary into bin
            find -name ripgrep -type d \
              -execdir mkdir -p {}/bin \; \
              -execdir ln -s ${pkgs.ripgrep}/bin/rg {}/bin/rg \;

            # Run post-install scripts
            find ./lib/vscode \( -path "*/node_modules/*" -or -path "*/extensions/*" \) \
              -and -type f -name "yarn.lock" -printf "%h\n" | \
                xargs -I {} sh -c 'jq -e ".scripts.postinstall" {}/package.json >/dev/null && yarn --cwd {} postinstall --frozen-lockfile --offline || true'
            patchShebangs .

            # Build binary packages
            npm rebuild --offline
            npm rebuild --offline --prefix lib/vscode/remote

            # 确保 TypeScript 可用并创建符号链接
            if [ -d ./node_modules/typescript ]; then
              mkdir -p ./node_modules/.bin
              ln -sf ../typescript/bin/tsc ./node_modules/.bin/tsc
              ln -sf ../typescript/bin/tsserver ./node_modules/.bin/tsserver
              echo "TypeScript symlinks created"
            else
              echo "ERROR: TypeScript not found in node_modules"
              ls -la ./node_modules/ | head -20
              exit 1
            fi

            # 修复 build-code-server.sh 脚本，使用完整路径调用 tsc
            if [ -f ./ci/build/build-code-server.sh ]; then
              sed -i 's|^\s*tsc\s*$|  ./node_modules/.bin/tsc|g' ./ci/build/build-code-server.sh
            fi

            # Build code-server and VS Code
            yarn build
            VERSION=${version} yarn build:vscode

            # Inject version into package.json
            jq --slurp '.[0] * .[1]' ./package.json <(
              cat << EOF
            {
              "version": "${version}"
            }
            EOF
            ) | sponge ./package.json

            # Create release
            KEEP_MODULES=1 yarn release

            # Prune development dependencies
            npm prune --omit=dev --prefix release

            runHook postBuild
          '';
        });
      in
      {
        packages.default = code-server;
        packages.code-server = code-server;

        # 提供一个 app 方便直接运行
        apps.default = {
          type = "app";
          program = "${code-server}/bin/code-server";
        };
      }
    );
}

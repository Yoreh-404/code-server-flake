{
  description = "code-server for NixOS - pnpm refactored version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        version = "4.109.5";
        commit = "d58aaa7b346b3262e0d4959e5fd5965e95ce456e";

        code-server = pkgs.stdenv.mkDerivation {
          pname = "code-server-pnpm";
          inherit version;

          src = pkgs.fetchFromGitHub {
            owner = "coder";
            repo = "code-server";
            rev = "v${version}";
            hash = "sha256-gS2ReYCAsqmdRw0tx+svPrw0zwF41/+aICBqfflxB14=";
            fetchSubmodules = true;
          };

          nativeBuildInputs = with pkgs; [
            nodejs_22
            nodePackages.pnpm
            python3
            pkg-config
            git
            jq
            moreutils
            quilt
            cacert
          ];

          buildInputs = with pkgs; [
            ripgrep
            libsecret
            xorg.libX11
            xorg.libxkbfile
          ];

          # 允许网络访问来转换依赖
          __noChroot = true;

          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          SKIP_SUBMODULE_DEPS = "1";

          postPatch = ''
            export HOME=$PWD
            patchShebangs ./ci

            # 删除所有 package-lock.json 和 yarn.lock
            find . -name "package-lock.json" -delete
            find . -name "yarn.lock" -delete

            # 删除 postinstall 脚本
            jq 'del(.scripts.postinstall)' package.json > package.json.tmp
            mv package.json.tmp package.json

            # 删除 lib/vscode 的 preinstall 脚本
            if [ -f lib/vscode/package.json ]; then
              jq 'del(.scripts.preinstall)' lib/vscode/package.json > lib/vscode/package.json.tmp
              mv lib/vscode/package.json.tmp lib/vscode/package.json
            fi

            # 修复 git 命令
            substituteInPlace ./ci/build/build-vscode.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}" \
              --replace-fail 'git checkout product.json' 'true'
            substituteInPlace ./ci/build/build-release.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}"

            # 修复补丁
            if [ -f patches/signature-verification.diff ]; then
              sed -i 's|lib/vscode/build/gulpfile\.reh\.js|lib/vscode/build/gulpfile.reh.ts|g' patches/signature-verification.diff
            fi

            # 应用补丁
            quilt push -a || echo "Some patches failed"

            # 移除内置扩展
            jq --slurp '.[0] * .[1]' "./lib/vscode/product.json" <(
              cat << EOF
            {
              "builtInExtensions": []
            }
            EOF
            ) | sponge ./lib/vscode/product.json

            # 禁用自动更新
            sed -i '/update.mode/,/\}/{s/default:.*/default: "none",/g}' \
              lib/vscode/src/vs/platform/update/common/update.config.contribution.ts
          '';

          configurePhase = ''
            runHook preConfigure

            export HOME=$PWD
            export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export PNPM_HOME="$PWD/.pnpm"
            export PATH="$PNPM_HOME:$PATH"

            # 初始化 pnpm
            pnpm config set store-dir "$PWD/.pnpm-store"

            # 创建 stub kerberos
            mkdir -p lib/vscode/node_modules/kerberos
            cat > lib/vscode/node_modules/kerberos/package.json <<'EOF'
            {
              "name": "kerberos",
              "version": "2.1.1",
              "main": "index.js"
            }
            EOF
            echo "module.exports = {};" > lib/vscode/node_modules/kerberos/index.js

            # 使用 pnpm 导入依赖
            echo "Installing root dependencies with pnpm..."
            pnpm install --no-frozen-lockfile

            # 安装 lib/vscode 依赖
            if [ -f lib/vscode/package.json ]; then
              echo "Installing lib/vscode dependencies with pnpm..."
              cd lib/vscode
              pnpm install --no-frozen-lockfile
              cd ../..
            fi

            # 安装 vendor 依赖
            if [ -d vendor ]; then
              echo "Installing vendor dependencies with pnpm..."
              cd vendor
              pnpm install --no-frozen-lockfile
              cd ..
            fi

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$PWD
            export NODE_OPTIONS="--max-old-space-size=8192"
            export PATH="$PWD/node_modules/.bin:$PATH"

            # 放置 ripgrep
            find -name ripgrep -type d \
              -execdir mkdir -p {}/bin \; \
              -execdir ln -s ${pkgs.ripgrep}/bin/rg {}/bin/rg \;

            # 构建 code-server
            pnpm run build

            # 构建 vscode
            VERSION=${version} pnpm run build:vscode

            # 注入版本
            jq --slurp '.[0] * .[1]' ./package.json <(
              cat << EOF
            {
              "version": "${version}"
            }
            EOF
            ) | sponge ./package.json

            # 创建 release
            KEEP_MODULES=1 pnpm run release

            # 清理开发依赖
            cd release
            pnpm prune --prod
            cd ..

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/libexec/code-server $out/bin
            cp -R -T release "$out/libexec/code-server"

            # 创建启动脚本
            cat > $out/bin/code-server <<'WRAPPER'
            #!/bin/sh
            exec ${pkgs.nodejs_22}/bin/node $out/libexec/code-server/out/node/entry.js "$@"
            WRAPPER
            chmod +x $out/bin/code-server

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Run VS Code on a remote server (pnpm refactored for NixOS)";
            homepage = "https://github.com/coder/code-server";
            license = licenses.mit;
            maintainers = [ ];
            platforms = [ "x86_64-linux" ];
          };
        };
      in
      {
        packages.default = code-server;
        packages.code-server = code-server;

        apps.default = {
          type = "app";
          program = "${code-server}/bin/code-server";
        };
      }
    );
}

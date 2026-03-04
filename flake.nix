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

          # 更新 yarn cache，使用 Node.js 22
          yarnCache = oldAttrs.yarnCache.overrideAttrs (old: {
            inherit src;

            nativeBuildInputs = [
              (pkgs.yarn.override { nodejs = pkgs.nodejs_22; })
              pkgs.nodejs_22
              pkgs.git
              pkgs.cacert
            ];

            # 使用官方源并增加重试
            buildPhase = ''
              runHook preBuild

              export HOME=$PWD
              export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

              # 增加重试次数和超时时间
              npm config set fetch-retries 10
              npm config set fetch-retry-mintimeout 20000
              npm config set fetch-retry-maxtimeout 120000
              npm config set fetch-timeout 300000

              yarn --cwd "./vendor" install --modules-folder modules --ignore-scripts --frozen-lockfile

              yarn config set yarn-offline-mirror $out
              find "$PWD" -name "yarn.lock" -printf "%h\n" | \
                xargs -I {} yarn --cwd {} \
                  --frozen-lockfile --ignore-scripts --ignore-platform \
                  --ignore-engines --no-progress --non-interactive

              find ./lib/vscode -name "yarn.lock" -printf "%h\n" | \
                xargs -I {} yarn --cwd {} \
                  --ignore-scripts --ignore-engines

              runHook postBuild
            '';

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-3xDinhLSZJoz7N7Z/+ttDLh82fwyunOTeSE3ULOZcHA=";
          });

          # 覆盖 buildPhase 来修复补丁并构建
          buildPhase = ''
            runHook preBuild

            # 修复 signature-verification.diff 补丁中的文件路径问题
            if [ -f patches/signature-verification.diff ]; then
              sed -i 's|lib/vscode/build/gulpfile\.reh\.js|lib/vscode/build/gulpfile.reh.ts|g' patches/signature-verification.diff
            fi

            # 继续执行原来的 buildPhase
            ${oldAttrs.buildPhase or ""}

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

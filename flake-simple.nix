{
  description = "code-server package for NixOS - Latest version";

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
          pname = "code-server";
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
            yarn
            python3
            pkg-config
            git
            cacert
            jq
            moreutils
            quilt
            ripgrep
            libsecret
            xorg.libX11
            xorg.libxkbfile
          ];

          # 允许网络访问来安装依赖
          __noChroot = true;

          postPatch = ''
            export HOME=$PWD
            patchShebangs ./ci

            # inject git commit
            substituteInPlace ./ci/build/build-vscode.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}"
            substituteInPlace ./ci/build/build-release.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}"
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$PWD
            export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
            export SKIP_SUBMODULE_DEPS=1
            export NODE_OPTIONS="--max-old-space-size=8192"

            # 修复补丁
            if [ -f patches/signature-verification.diff ]; then
              sed -i 's|lib/vscode/build/gulpfile\.reh\.js|lib/vscode/build/gulpfile.reh.ts|g' patches/signature-verification.diff
            fi

            # Apply patches
            quilt push -a || echo "Some patches failed"

            # Remove built-in extensions
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

            # 安装根目录依赖
            echo "Installing root dependencies..."
            npm ci --verbose

            # 安装 lib/vscode 依赖
            echo "Installing lib/vscode dependencies..."
            if [ -f lib/vscode/package.json ]; then
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

              # 删除 preinstall 脚本
              jq 'del(.scripts.preinstall)' lib/vscode/package.json > lib/vscode/package.json.tmp
              mv lib/vscode/package.json.tmp lib/vscode/package.json

              npm install --prefix lib/vscode --verbose
            fi

            # 安装 vendor 依赖
            yarn --cwd "./vendor" install --modules-folder modules --ignore-scripts --frozen-lockfile

            # 安装其他 yarn 子目录
            find ./lib/vscode -name "yarn.lock" -printf "%h\n" | \
              xargs -I {} yarn --cwd {} \
                --frozen-lockfile --ignore-scripts --ignore-platform \
                --ignore-engines --no-progress --non-interactive

            patchShebangs .

            # Put ripgrep binary
            find -name ripgrep -type d \
              -execdir mkdir -p {}/bin \; \
              -execdir ln -s ${pkgs.ripgrep}/bin/rg {}/bin/rg \;

            # Run postinstall scripts
            find ./lib/vscode \( -path "*/node_modules/*" -or -path "*/extensions/*" \) \
              -and -type f -name "yarn.lock" -printf "%h\n" | \
                xargs -I {} sh -c 'jq -e ".scripts.postinstall" {}/package.json >/dev/null && yarn --cwd {} postinstall --frozen-lockfile --offline || true'

            patchShebangs .

            # Build binary packages
            npm rebuild --offline
            npm rebuild --offline --prefix lib/vscode/remote

            # Build code-server
            yarn build
            VERSION=${version} yarn build:vscode

            # Inject version
            jq --slurp '.[0] * .[1]' ./package.json <(
              cat << EOF
            {
              "version": "${version}"
            }
            EOF
            ) | sponge ./package.json

            # Create release
            KEEP_MODULES=1 yarn release
            npm prune --omit=dev --prefix release

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/libexec/code-server $out/bin
            cp -R -T release "$out/libexec/code-server"

            ln -s $out/libexec/code-server/out/node/entry.js $out/bin/code-server

            runHook postInstall
          '';

          passthru.tests = { };

          meta = with pkgs.lib; {
            description = "Run VS Code on a remote server";
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

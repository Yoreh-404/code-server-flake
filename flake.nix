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

        code-server = pkgs.buildNpmPackage {
          pname = "code-server";
          inherit version;

          src = pkgs.fetchFromGitHub {
            owner = "coder";
            repo = "code-server";
            rev = "v${version}";
            hash = "sha256-gS2ReYCAsqmdRw0tx+svPrw0zwF41/+aICBqfflxB14=";
            fetchSubmodules = true;
          };

          npmDepsHash = "sha256-Ec0ZlwdihsSbz+4OLPZ9OyBSx88HDOPp16ENEuvzQu4=";

          nativeBuildInputs = with pkgs; [
            python3
            pkg-config
            git
            jq
            moreutils
            quilt
            libsecret
            xorg.libX11
            xorg.libxkbfile
          ];

          buildInputs = with pkgs; [
            ripgrep
          ];

          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          SKIP_SUBMODULE_DEPS = "1";

          # 简化 postPatch，只做必要的替换
          postPatch = ''
            export HOME=$PWD
            patchShebangs ./ci

            # 删除 postinstall 脚本，避免安装 test 依赖
            ${pkgs.jq}/bin/jq 'del(.scripts.postinstall)' package.json > package.json.tmp
            mv package.json.tmp package.json

            # inject git commit and remove git commands
            substituteInPlace ./ci/build/build-vscode.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}" \
              --replace-fail 'git checkout product.json' 'true'
            substituteInPlace ./ci/build/build-release.sh \
              --replace-fail '$(git rev-parse HEAD)' "${commit}"
          '';

          preConfigure = ''
            # 在 npm install 之前修复补丁和配置
            if [ -f patches/signature-verification.diff ]; then
              sed -i 's|lib/vscode/build/gulpfile\.reh\.js|lib/vscode/build/gulpfile.reh.ts|g' patches/signature-verification.diff
            fi

            # Apply patches
            ${pkgs.quilt}/bin/quilt push -a || echo "Some patches failed"

            # Remove built-in extensions
            ${pkgs.jq}/bin/jq --slurp '.[0] * .[1]' "./lib/vscode/product.json" <(
              cat << EOF
            {
              "builtInExtensions": []
            }
            EOF
            ) | ${pkgs.moreutils}/bin/sponge ./lib/vscode/product.json

            # Disable automatic updates
            sed -i '/update.mode/,/\}/{s/default:.*/default: "none",/g}' \
              lib/vscode/src/vs/platform/update/common/update.config.contribution.ts
          '';

          preBuild = ''
            # 创建 stub kerberos
            if [ -f lib/vscode/package.json ]; then
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
              ${pkgs.jq}/bin/jq 'del(.scripts.preinstall)' lib/vscode/package.json > lib/vscode/package.json.tmp
              mv lib/vscode/package.json.tmp lib/vscode/package.json
            fi
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$PWD
            export NODE_OPTIONS="--max-old-space-size=8192"

            # Put ripgrep binary
            find -name ripgrep -type d \
              -execdir mkdir -p {}/bin \; \
              -execdir ln -s ${pkgs.ripgrep}/bin/rg {}/bin/rg \;

            # Build code-server
            npm run build
            VERSION=${version} npm run build:vscode

            # Inject version
            ${pkgs.jq}/bin/jq --slurp '.[0] * .[1]' ./package.json <(
              cat << EOF
            {
              "version": "${version}"
            }
            EOF
            ) | ${pkgs.moreutils}/bin/sponge ./package.json

            # Create release
            KEEP_MODULES=1 npm run release
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

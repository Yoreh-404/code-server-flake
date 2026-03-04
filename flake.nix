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

        # 基于官方包进行 override，保持官方的构建逻辑
        code-server = pkgs.code-server.overrideAttrs (oldAttrs: rec {
          version = "4.109.5";

          src = pkgs.fetchFromGitHub {
            owner = "coder";
            repo = "code-server";
            rev = "v${version}";
            hash = "sha256-gS2ReYCAsqmdRw0tx+svPrw0zwF41/+aICBqfflxB14=";
            fetchSubmodules = true;
          };

          # 更新 yarn cache 哈希
          yarnCache = oldAttrs.yarnCache.overrideAttrs (old: {
            inherit src;
            outputHash = "sha256-0000000000000000000000000000000000000000000=";  # 需要更新
          });

          # 更新 git commit（用于缓存和多语言支持）
          # 运行: git ls-remote https://github.com/coder/code-server.git v4.109.5
          patches = oldAttrs.patches or [];

          postPatch = (oldAttrs.postPatch or "") + ''
            # 注入正确的 commit hash
            COMMIT=$(cat <<'EOF'
            # 需要运行: git ls-remote https://github.com/coder/code-server.git v4.109.5
            # 然后替换这里的值
            EOF
            )
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

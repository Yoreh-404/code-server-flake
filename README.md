# code-server NixOS 构建项目

这个项目使用 GitHub Actions 自动为 NixOS 构建**最新版本**的 code-server 包，并将构建产物推送到 Cachix。

## 为什么需要这个项目？

NixOS 官方的 code-server 包版本严重滞后：
- 官方版本: **4.91.1** (2024年)
- 最新版本: **4.109.5** (2026年)

这个项目基于官方包的构建逻辑，但允许你快速跟踪最新版本。

## 支持的平台

- x86_64-linux
- aarch64-linux

## 功能特性

- ✅ 基于官方 nixpkgs 的构建逻辑（保证质量）
- ✅ 自动跟踪最新稳定版 code-server
- ✅ 支持多平台架构（x86_64 和 ARM64）
- ✅ 使用 Cachix 作为二进制缓存
- ✅ 每周自动检查新版本
- ✅ 支持手动触发构建
- ✅ 提供自动更新脚本

## 快速开始

### 自动更新到最新版本

```bash
# 1. 自动获取最新版本并更新 flake.nix
./update-version.sh

# 2. 更新 flake 依赖
nix flake update

# 3. 自动获取并更新 yarn cache 哈希
./update-yarn-hash.sh
```

就这么简单！脚本会自动完成所有哈希计算和文件更新。

### 手动更新（如果自动脚本失败）

1. 获取最新版本号和 commit：
```bash
# 获取最新版本
curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep tag_name

# 获取对应的 commit
git ls-remote https://github.com/coder/code-server.git v4.109.5
```

2. 更新 `flake.nix` 中的 `version` 和 commit

3. 计算源码哈希：
```bash
nix-prefetch-url --unpack https://github.com/coder/code-server/archive/v4.109.5.tar.gz
```

4. 首次构建获取 yarn cache 哈希：
```bash
nix build .#code-server 2>&1 | grep "got:"
```

5. 将显示的哈希值更新到 `flake.nix` 的 `yarnCache.outputHash`

6. 重新构建：
```bash
nix build .#code-server
```

## GitHub Actions 配置

### 1. 创建 Cachix 缓存

访问 [Cachix](https://cachix.org/) 并创建一个新的缓存。

### 2. 配置 GitHub Secrets

在你的 GitHub 仓库中添加以下 secrets：

- `CACHIX_CACHE_NAME`: 你的 Cachix 缓存名称
- `CACHIX_AUTH_TOKEN`: 你的 Cachix 认证令牌

路径：Settings → Secrets and variables → Actions → New repository secret

### 3. 启用 GitHub Actions

确保你的仓库已启用 GitHub Actions。

## 本地构建

### 构建 x86_64-linux 版本

```bash
nix build .#code-server
```

### 构建 aarch64-linux 版本

```bash
nix build .#code-server --system aarch64-linux
```

### 运行 code-server

```bash
./result/bin/code-server
```

## 使用构建的包

### 方法 1: 从 Cachix 安装

首先添加你的 Cachix 缓存：

```bash
cachix use <your-cache-name>
```

然后在你的 NixOS 配置中使用：

```nix
{
  inputs.code-server-flake.url = "github:<your-username>/<your-repo>";

  outputs = { self, nixpkgs, code-server-flake }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      modules = [
        {
          environment.systemPackages = [
            code-server-flake.packages.x86_64-linux.code-server
          ];
        }
      ];
    };
  };
}
```

### 方法 2: 直接从 flake 安装

```bash
nix profile install github:<your-username>/<your-repo>#code-server
```

## 更新 code-server 版本

使用自动更新脚本（推荐）：

```bash
./update-version.sh && nix flake update && ./update-yarn-hash.sh
```

或者参考上面的"手动更新"步骤。

## 工作流触发条件

- 推送到 main/master 分支
- Pull Request
- 手动触发（workflow_dispatch）
- 每周日自动运行（检查更新）

## 故障排除

### 构建失败

检查 GitHub Actions 日志，常见问题：

1. Cachix secrets 未正确配置
2. 版本号或哈希值不匹配
3. 依赖项缺失

### 跨平台构建问题

aarch64-linux 构建使用 QEMU 进行交叉编译，可能需要较长时间。

## 许可证

MIT

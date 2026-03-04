# 项目改进说明

## 主要改进

### 1. 基于官方包的 Override 方案

**之前的问题：**
- 从零开始编写构建逻辑
- 缺少关键的构建步骤（git commit 注入、yarn cache 管理等）
- 不符合 Nix 的纯函数式构建原则

**现在的方案：**
```nix
code-server = pkgs.code-server.overrideAttrs (oldAttrs: rec {
  version = "4.109.5";
  # 继承官方的所有构建逻辑
  # 只覆盖版本相关的部分
});
```

这样做的好处：
- ✅ 保留官方所有的构建优化和修复
- ✅ 自动继承依赖管理、补丁、平台特定处理
- ✅ 只需要更新版本号和哈希值

### 2. 自动化更新脚本

提供了三个脚本简化更新流程：

**update-version.sh**
- 自动获取最新版本号
- 自动获取 git commit hash
- 自动计算源码哈希
- 自动更新 flake.nix

**update-yarn-hash.sh**
- 自动构建并捕获正确的 yarn cache 哈希
- 自动更新 flake.nix
- 自动重新构建验证

**test.sh**
- 验证构建结果
- 检查版本信息
- 确保二进制文件可执行

### 3. GitHub Actions 自动检测

**auto-update.yml**
- 每天自动检查新版本
- 发现新版本时自动创建 PR
- 提供清晰的更新步骤说明

### 4. 版本对比

| 项目 | 官方 nixpkgs | 本项目 |
|------|-------------|--------|
| 版本 | 4.91.1 | 4.109.5 (最新) |
| 更新频率 | 不定期 | 自动检测 |
| 构建质量 | 官方维护 | 基于官方 |
| 自定义性 | 低 | 高 |

## 使用流程

### 首次设置

```bash
# 1. 克隆仓库
git clone <your-repo>
cd code-server

# 2. 更新到最新版本
./update-version.sh
nix flake update
./update-yarn-hash.sh

# 3. 测试构建
./test.sh

# 4. 配置 GitHub Actions
# 在 GitHub 仓库设置中添加 Cachix secrets
```

### 日常更新

```bash
# 一行命令完成所有更新
./update-version.sh && nix flake update && ./update-yarn-hash.sh && ./test.sh
```

### CI/CD 集成

推送到 GitHub 后：
- ✅ 自动构建 x86_64-linux 和 aarch64-linux
- ✅ 自动推送到 Cachix
- ✅ 每天自动检查新版本
- ✅ 发现新版本自动创建 PR

## 技术细节

### 为什么需要 yarn cache 哈希？

Nix 要求所有构建输入都有固定的哈希值，以确保：
- 构建的可重现性
- 离线构建能力
- 二进制缓存的有效性

code-server 使用 yarn 管理依赖，官方包创建了一个独立的 `yarnCache` derivation 来预先下载所有依赖。

### 为什么需要 git commit？

根据 code-server 维护者的说明：
1. **多语言支持** - VS Code 依赖 commit 来加载翻译文件
2. **缓存破坏** - 确保浏览器不会加载旧版本的资源
3. **问题报告** - 帮助在 bug 报告中准确识别版本

### 构建时间

- **首次构建**: 30-60 分钟（需要编译 VS Code）
- **增量构建**: 5-10 分钟（如果只更新小版本）
- **从 Cachix**: 1-2 分钟（直接下载二进制）

## 故障排除

### 哈希不匹配

```bash
# 清理并重新计算
rm -rf result
nix flake update
./update-yarn-hash.sh
```

### 构建失败

```bash
# 查看详细日志
nix build .#code-server --print-build-logs

# 如果是依赖问题，尝试更新 nixpkgs
nix flake lock --update-input nixpkgs
```

### 跨平台构建慢

aarch64-linux 使用 QEMU 模拟，会比较慢。建议：
- 使用 GitHub Actions 构建
- 或者使用原生 ARM 机器
- 或者只构建 x86_64-linux

## 下一步

1. 配置 Cachix 并推送到 GitHub
2. 等待首次构建完成
3. 在你的 NixOS 配置中使用这个 flake
4. 享受最新版本的 code-server！

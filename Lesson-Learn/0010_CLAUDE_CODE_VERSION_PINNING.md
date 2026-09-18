# 在 NixOS 上升级 claude-code：发布分支冻结与 manifest 覆写

> 日期：2026-09-18　|　相关配置：`modules/development.nix`、`modules/claude-code-manifest.json`
>
> 触发场景：想用 Claude Code 的会话管理功能（`/rename`、会话选择器的 `Ctrl+R`、
> agent view、`claude attach`），发现本机 2.1.223 全都没有。

## 问题症状

本机 `claude --version` 是 **2.1.223**，而官方最新是 **2.1.276**。
好几个想用的功能都有版本门槛：

| 功能 | 最低版本 |
|------|----------|
| 从 claude.ai 改名同步到 CLI | 2.1.221 |
| `chat:queueSubmit`（`Ctrl+X Enter` 排队提交） | 2.1.247 |
| agent view 的 `Agents` 键位上下文 | 2.1.257 |
| diff panel（`/diff` 面板） | 2.1.260 |

第一反应是 `nix flake update`。**没用。**

## 根本原因分析

### 一、`nixos-26.05` 是发布分支，不跟上游滚

查了三个渠道的版本：

| 渠道 | 版本 |
|------|------|
| 本机 / `nixos-26.05` | 2.1.223 |
| `nixos-unstable` | 2.1.272 |
| 官方 `latest` | 2.1.276 |

`nixos-26.05` 上就是 2.1.223，和本机一模一样。
发布分支只收安全修复和重要 backport，不会把一个日更的 CLI 一路跟到最新。
所以 **`nix flake update` 对这个包是彻底的空操作** ——
更新完版本号一点不变，很容易误以为「已经是最新了」。

**教训：`nix flake update` 没让某个包动，先去看它在发布分支上的版本，
而不是怀疑 flake 没更新成功。**

### 二、这个包其实只是个下载器

看 `pkgs/by-name/cl/claude-code/package.nix`：

```nix
manifest ? lib.importJSON ./manifest.json,
...
inherit (manifest) version;
src = fetchurl {
  url = "${baseUrl}/${finalAttrs.version}/${platformKey}/claude";
  sha256 = platformManifestEntry.checksum;
};
```

它不编译任何东西，只是按 `manifest.json` 里的 `version` 和 `checksum`
去 `downloads.claude.ai` 拉官方预编译二进制，再 `autoPatchelfHook` 一遍。

也就是说 —— **换掉 manifest 就等于换版本，包定义本身一个字都不用改。**
而 `manifest` 是个带默认值的函数参数，天生就能 `.override`。

## 已实施的修复

`modules/development.nix` 加一个 overlay：

```nix
nixpkgs.overlays = [
  (_final: prev: {
    claude-code = prev.claude-code.override {
      manifest = lib.importJSON ./claude-code-manifest.json;
    };
  })
];
```

manifest 从上游取（它有 `latest` 端点）：

```bash
V=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$V/manifest.json" \
  -o modules/claude-code-manifest.json
```

## 为什么这样解决

### 为什么不加 `nixpkgs-unstable` input

那是另一条可行路线，能拿到 2.1.272，而且走 `cache.nixos.org` 的二进制缓存。
但代价是仓库里多一整个 nixpkgs —— 多一份 tarball、多一份求值开销、
每次 `nix flake update` 多一个要动的东西。**为一个包不值得。**

覆写 manifest 这条路还顺带拿到了更新的 2.1.276。

### 为什么用 overlay 而不是在两处各写一次

`claude-code` 同时出现在两个地方，而且**两处都是必需的**：

- `modules/development.nix` 的 `systemPackages` —— 终端里直接用
- `home/toru.nix` 的 `programs.neovim.extraPackages` —— claudecode.nvim
  是从 Neovim 内部 spawn `claude` 的，走 nvim wrapper 的 PATH（见 `000D`）

如果改成在两处各写一次 `.override`，漏掉一边就会装出两个版本，
正是 `000A` 记过的坑。覆写 `pkgs.claude-code` 让两处同时生效。

因为 `home-manager.useGlobalPkgs = true`，home 层用的就是系统的 `pkgs`，
overlay 自动覆盖过去。**验证过**：

```
系统 PATH 的 claude     → /nix/store/0g2jlr4...-claude-code-2.1.276
nvim wrapper 里的 claude → /nix/store/0g2jlr4...-claude-code-2.1.276
```

同一个 store path，确认只有一个版本。

## 后续注意事项

- **不要去取同目录下的 `manifest.zst.json`。**
  `nixos-unstable` 上的新包定义换成了那个格式（二进制经 zstd 压缩，
  构建时要 `zstd` 解压，`buildInputs` 里也多了 `zstd`）。
  `nixos-26.05` 的包定义只认不带 `.zst` 的那份。两个文件在上游同时存在，
  取错了会在构建时才报错。
- **升级后要手动刷新 manifest**，不会跟着 `nix flake update` 走。
  刷新命令见上。这是这条路线的代价，接受它换来的是不用背一个 nixpkgs。
- **不要用 `claude install` / `claude update` 自更新。**
  那会把二进制装到 `~/.local` 下，脱离 Nix 管理，和整个仓库的声明式前提冲突，
  而且下次 rebuild 时 PATH 上会同时存在两个 claude，行为取决于顺序。
- **下载量约 232 MB**，且**不走 `cache.nixos.org`** ——
  覆写后的派生和缓存里的不是同一个，只能从 `downloads.claude.ai` 直取。
  实测该站点约 6.4 MB/s，半分钟左右，不成问题。
  注意 README 里记的「本机 ~80 KiB/s」是 **GitHub clone** 的特性（见 `000E`），
  不是全局网速，别拿它吓自己。
- 升级后新增的会话管理子命令：`claude attach <id>`、`claude logs <id>`、
  `claude respawn`、`claude stop|kill <id>`、`claude rm <id>`。
  配合 `/background` 和 `claude agents` 用。

## 相关文档

- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— 同一个程序被装出两份的历史教训
- [000C_NIX_LD_PREBUILT_BINARIES.md](000C_NIX_LD_PREBUILT_BINARIES.md) —— nixpkgs 版 claude-code 经 auto-patchelf，不依赖 nix-ld
- [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md) —— 为什么 extraPackages 那一份是必需的
- [000E_LAZY_NVIM_SLOW_NETWORK_CLONE.md](000E_LAZY_NVIM_SLOW_NETWORK_CLONE.md) —— 「本机网络慢」那条结论的出处与适用范围

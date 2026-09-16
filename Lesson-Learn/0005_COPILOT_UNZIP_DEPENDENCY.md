# Copilot.lua 语言服务器 unzip 依赖问题修复

## 问题描述

在 Neovide 中使用 Copilot 时（按 Alt+Enter），出现以下错误：

```
[Copilot.lua] could not prepare copilot-language-server: extract failed at 
/home/toru/.local/share/nvim/copilot.lua/lsp/1.545.0/linux-x64/.staging-v0psCZ 
(extract): unzip unavailable; powershell unavailable
```

## 根本原因

Copilot 的 Neovim 插件（copilot.lua）需要下载并解压 copilot-language-server 的二进制文件。
错误信息表明系统中没有可用的解压工具：
- `unzip` 不可用
- `powershell` 不可用

在 Linux 系统上，`unzip` 是标准的解压工具，可以处理 .zip 文件。

## 解决方案

在 Neovim 的依赖包中添加 `unzip`：

**文件：** `/home/toru/nixos-config/home/toru.nix`

**修改位置：** `programs.neovim.extraPackages`

**修改内容：**

添加前：
```nix
extraPackages = with pkgs; [
  nixfmt
  nil
  nodejs_24
  github-cli
  lua-language-server
];
```

添加后：
```nix
extraPackages = with pkgs; [
  nixfmt
  nil
  nodejs_24
  github-cli
  unzip  # ← 新增：Copilot 语言服务器解压需要
  lua-language-server
];
```

## 为什么添加到 extraPackages？

`extraPackages` 是 HomeManager 中为 Neovim 准备的额外工具包列表。这些包会：
1. 被安装到系统中
2. 在 Neovim 的执行环境中可用
3. 被包含在 PATH 中

对于 Copilot 这样需要系统工具的插件来说，这是最合适的位置。

## 部署步骤

1. **验证配置修改**（已完成）
   ```bash
   cat /home/toru/nixos-config/home/toru.nix | grep -A 15 "extraPackages"
   # 应该能看到 unzip 在列表中
   ```

2. **验证配置有效性**（已完成）
   ```bash
   nix flake check
   # 输出：all checks passed! ✅
   ```

3. **部署系统配置**（待执行）
   ```bash
   sudo nixos-rebuild switch --flake .#thinkpad
   # 这会安装 unzip 到系统中
   ```

4. **清理 Copilot 缓存**（推荐）
   ```bash
   rm -rf ~/.local/share/nvim/copilot.lua/
   ```

5. **测试 Copilot**
   ```bash
   neovide /home/toru/nixos-config
   # 进入 Insert 模式
   # 输入一些代码让 Copilot 建议
   # 按 Alt+Enter 打开 Copilot 面板（应该不再出现 unzip 错误）
   ```

## Copilot.lua 的依赖要求

copilot.lua 需要以下工具才能正常工作：

| 工具 | 用途 | 平台 | 状态 |
|------|------|------|------|
| `unzip` | 解压 LSP 服务器 | Linux/macOS | ✅ 已添加 |
| `nodejs` | Copilot 服务通信 | 所有 | ✅ 已有（nodejs_24） |
| `git` | 克隆和管理插件 | 所有 | ✅ 已有（系统默认） |
| `curl` 或 `wget` | 下载 LSP 服务器 | 所有 | ✅ 已有（系统默认） |
| `powershell` | Windows 解压工具 | Windows | ❌ 不需要（Linux 系统） |

## 相关文件

已修改的文件：
- `/home/toru/nixos-config/home/toru.nix`（第 57-73 行的 extraPackages 部分）

## 关键学习

✅ **Copilot.lua 需要解压工具** - 因为 LSP 服务器以压缩形式分发
✅ **unzip 应该在 Neovim extraPackages 中** - 作为开发工具的依赖
✅ **Linux 系统使用 unzip，Windows 系统使用 powershell** - 错误消息很清楚地表明了需要哪一个
✅ **清理缓存很重要** - 之前失败的下载会被重试

## 后续验证

部署后，如果 Copilot 仍然无法工作：

1. **验证 unzip 已安装**
   ```bash
   which unzip
   # 应该输出：/run/current-system/sw/bin/unzip
   ```

2. **查看 Neovim 日志**
   ```bash
   nvim
   :messages
   # 查看是否还有相关错误
   ```

3. **检查 Copilot 认证**
   ```bash
   nvim
   :Copilot auth
   # 完成认证流程
   ```

4. **测试完整流程**
   ```bash
   nvim test.py  # 或任何支持的文件
   i
   def hello_world
   # 等待 Copilot 建议
   ```

## 提交记录

文件修改说明：
- 添加 `unzip` 到 Neovim extraPackages
- 添加注释说明其作用
- 保持与其他工具相同的格式和组织

下次提交时的提交消息应该包含：
```
feat: Add unzip to Neovim dependencies for Copilot LSP support

- Copilot.lua 需要 unzip 来解压 copilot-language-server
- 添加到 home.programs.neovim.extraPackages
- 修复错误：unzip unavailable
```

# Copilot "Offline" 状态问题诊断和修复

> ⛔ **已过时（2026-09-17）**
> 本文记录的修复方案（vim.g.copilot_node_command / COPILOT_DEBUG / copilot.command.auth_setup() / server_opts_overrides.trace / :CopilotStatus / :CopilotStart / :CopilotReauth / copilot-cmp）已于 2026-09-17 全部撤销。
> 其中多个 API 在新版 copilot.lua 中已不存在，调用只会静默失败；copilot-cmp 则是 Copilot 真正故障的根源。
>
> 请以 [0009_COPILOT_GHOST_TEXT_MIGRATION.md](0009_COPILOT_GHOST_TEXT_MIGRATION.md) 和
> [0000_NEOVIM_GUIDE.md](0000_NEOVIM_GUIDE.md) 为准。本文仅作排查过程的历史记录保留。

## 问题症状

启动 Neovide 时显示：
```
[Copilot.lua] Status: Offline
Press ENTER or type command to continue
```

这说明 Copilot 的 LSP 服务器无法启动或无法连接。

## 根本原因分析

Copilot "Offline" 状态通常由以下几个原因引起：

### 1. **Node.js 路径未配置**
Copilot.lua 需要找到 Node.js 可执行文件来启动 LSP 服务器。
如果 Neovim 不知道 Node.js 在哪里，就会显示 "Offline"。

### 2. **Copilot 认证信息缺失**
Copilot LSP 服务器需要有效的认证令牌才能启动。
如果之前没有完成过认证，或者认证信息已过期，就会离线。

### 3. **LSP 服务器初始化不完整**
Copilot 需要在 lazy.nvim 加载完所有插件后才能正确初始化。
如果初始化时序不对，LSP 服务器可能启动失败。

### 4. **缺少必要的依赖**
- `unzip` - 用于解压 LSP 服务器（已添加）
- `node` - Node.js 运行时（已配置）
- 网络连接 - 首次下载 LSP 服务器

## 已实施的修复

### 修改 1: 在 init.lua 中设置 Node.js 路径

**文件：** `/home/toru/nixos-config/home/toru.nix` (init.lua 部分)

```lua
-- Copilot 和 Node.js 配置
-- 显式设置 Node.js 路径，确保 Copilot 能找到它
vim.g.copilot_node_command = "node"

-- 启用 Copilot 日志来诊断问题
vim.env.COPILOT_DEBUG = "true"
```

这确保 Neovim 知道 Node.js 的位置。

### 修改 2: 添加 Copilot 初始化脚本

```lua
-- Copilot 初始化检查
-- 在 Neovim 完全启动后运行，确保所有插件加载完成
vim.schedule(function()
  -- 给插件一点时间加载
  vim.defer_fn(function()
    -- 尝试获取 Copilot 状态
    pcall(function()
      require("copilot.command").auth_setup()
    end)
  end, 100)
end)
```

这确保 Copilot 在所有插件加载完成后自动尝试初始化。

### 修改 3: 增强 Copilot 插件配置

**文件：** `/home/toru/nixos-config/home/toru.nix` (copilot.lua 部分)

新增内容：

```lua
-- LSP 服务器选项覆盖
server_opts_overrides = {
  -- 确保日志记录启用以便诊断
  trace = "verbose",
},

-- 诊断和初始化辅助函数
vim.api.nvim_create_user_command("CopilotStatus", function()
  require("copilot.api").get_status(function(status)
    if status then
      print("Copilot Status: " .. vim.inspect(status))
    else
      print("Failed to get Copilot status")
    end
  end)
end, {})

-- 强制启动 Copilot LSP 服务器（如果尚未启动）
vim.api.nvim_create_user_command("CopilotStart", function()
  vim.cmd("Copilot enable")
  print("Copilot LSP server start requested")
end, {})

-- 重新认证命令
vim.api.nvim_create_user_command("CopilotReauth", function()
  require("copilot.command").auth_setup()
end, {})
```

### 修改 4: 添加依赖关系

```lua
{
  "zbirenbaum/copilot-cmp",
  lazy = false,
  dependencies = { "zbirenbaum/copilot.lua" },  -- 明确指定依赖
  config = function()
    require("copilot_cmp").setup()
  end,
}
```

## 部署步骤

### 1. 验证配置（已完成）
```bash
cd /home/toru/nixos-config
nix flake check
# 输出：all checks passed! ✅
```

### 2. 部署系统配置（必须执行）
```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

### 3. 清理所有缓存（推荐）
```bash
# 清理 Copilot 缓存
rm -rf ~/.local/share/nvim/copilot.lua/

# 清理 lazy.nvim 缓存
rm -rf ~/.local/share/nvim/lazy/

# 清理 LSP 日志
rm -rf ~/.local/share/nvim/lsp.log
```

### 4. 启动 Neovide 并验证
```bash
neovide /home/toru/nixos-config
```

## 验证步骤

### 1. 检查 Copilot 状态
在 Neovide 的 Normal 模式中执行：
```vim
:CopilotStatus
```

**预期输出：** 应该显示 Copilot 的当前状态（认证、离线等）

### 2. 启动 Copilot LSP 服务器
```vim
:CopilotStart
```

**预期输出：** 应该显示 "Copilot LSP server start requested"

### 3. 重新认证（如果仍显示 Offline）
```vim
:CopilotReauth
```

这会打开认证流程。

### 4. 查看日志诊断
```vim
:messages
```

查看消息历史，查找任何 Copilot 相关的错误信息。

### 5. 测试 Copilot 建议
1. 打开或创建一个 .nix 文件
2. 进入 Insert 模式（`i`）
3. 输入一些代码：
   ```nix
   environment.systemPackages = with pkgs; [
   ```
4. 等待灰色的 Copilot 建议出现
5. 按 Alt+L 接受建议

如果看到建议，说明 Copilot 正常工作！

## 故障排查

### 问题 1: 仍然显示 "Offline"

**诊断步骤：**

```bash
# 检查 Node.js 是否可用
which node

# 检查 Copilot LSP 服务器目录
ls -la ~/.local/share/nvim/copilot.lua/lsp/

# 查看详细的 Neovim 日志
tail -100 ~/.local/share/nvim/lsp.log
```

**可能的原因和解决方案：**

1. **Node.js 不在 PATH 中**
   ```bash
   # 验证 Node.js 已安装
   node --version
   
   # 应该输出：v24.19.0
   ```

2. **Copilot 认证令牌丢失**
   ```vim
   :Copilot auth login
   # 完成认证流程
   ```

3. **LSP 服务器下载失败**
   ```bash
   # 清理并重新下载
   rm -rf ~/.local/share/nvim/copilot.lua/
   # 重启 Neovim，让它重新下载
   ```

### 问题 2: 认证命令无响应

```vim
:CopilotReauth
```

如果没有反应：

1. **检查 Copilot 是否加载**
   ```vim
   :CopilotStatus
   ```

2. **查看错误消息**
   ```vim
   :messages
   ```

3. **强制重启 Copilot**
   ```bash
   rm -rf ~/.local/share/nvim/copilot.lua/
   # 重启 Neovide
   ```

### 问题 3: Copilot 启动后立即显示 "Offline"

这通常表示 LSP 服务器启动成功，但没有有效的认证令牌。

**解决方案：**
```vim
:Copilot auth login
```

按照提示完成认证。

## GitHub CLI 认证方式

如果 `:Copilot auth login` 在 Neovim 中无法工作，可以使用 GitHub CLI：

```bash
# 使用系统的 GitHub CLI 认证
gh auth login

# 选择：
# - Authentication protocol: HTTPS
# - Credentials: Paste an authentication token
# 或自动询问
```

这会生成认证令牌，Copilot 可以使用。

## 快速诊断命令集

将这些命令保存起来，以便快速诊断问题：

```bash
# 检查所有必需的工具
echo "=== 检查依赖 ==="
which node
which unzip
which git

# 检查 Copilot 缓存
echo "=== Copilot 缓存 ==="
ls -lh ~/.local/share/nvim/copilot.lua/

# 检查 LSP 日志
echo "=== LSP 日志 ==="
tail -50 ~/.local/share/nvim/lsp.log

# 在 Neovim 中执行
echo "=== Neovim 中执行 ==="
echo "nvim 中执行: :CopilotStatus"
echo "nvim 中执行: :CopilotStart"
echo "nvim 中执行: :messages"
```

## 预防措施

### 定期检查 Copilot 状态
```bash
# 每周运行一次
neovide
:CopilotStatus
```

### 定期清理缓存
```bash
# 每月清理一次（可选）
rm -rf ~/.local/share/nvim/copilot.lua/
```

### 保持认证最新
如果长时间不使用，认证令牌可能过期：
```vim
:Copilot auth login
```

## 关键要点

✅ **Node.js 路径** - 必须在 Neovim 中配置，让 Copilot 能找到
✅ **认证令牌** - 必须有效，可以通过 `:Copilot auth login` 获取
✅ **初始化时序** - 确保 Copilot 在所有插件加载完成后初始化
✅ **日志记录** - 启用详细日志以便诊断（已配置）
✅ **清理缓存** - 许多问题可以通过清理 ~/.local/share/nvim/ 解决

## 后续步骤

1. **部署配置：**
   ```bash
   sudo nixos-rebuild switch --flake .#thinkpad
   ```

2. **清理缓存：**
   ```bash
   rm -rf ~/.local/share/nvim/copilot.lua/
   rm -rf ~/.local/share/nvim/lazy/
   ```

3. **启动测试：**
   ```bash
   neovide /home/toru/nixos-config
   ```

4. **验证状态：**
   ```vim
   :CopilotStatus
   ```

5. **如果仍需认证：**
   ```vim
   :Copilot auth login
   ```

## 相关文档参考

- [0005_COPILOT_UNZIP_DEPENDENCY.md](0005_COPILOT_UNZIP_DEPENDENCY.md) - Copilot 的 unzip 依赖
- [0006_COPILOT_STARTUP_ISSUES.md](0006_COPILOT_STARTUP_ISSUES.md) - Copilot 启动问题
- [0000_NEOVIM_GUIDE.md](0000_NEOVIM_GUIDE.md) - Neovim 使用指南
- [0007_LAZY_NVIM_DASHBOARD.md](0007_LAZY_NVIM_DASHBOARD.md) - Lazy.nvim 仪表板使用

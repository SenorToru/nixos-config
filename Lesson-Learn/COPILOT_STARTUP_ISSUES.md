# Copilot 启动问题诊断和修复指南

> ⛔ **已过时（2026-09-17）**
> 本文第 3 节「依赖插件加载时序问题」关于 copilot-cmp 的结论已于 2026-09-17 作废。
> copilot-cmp 已被整体移除，它不是加载时序问题，而是与 copilot.lua 的 suggestion/panel 模块根本冲突，并且在 Neovim 0.11+ 上使用已废弃的 client.is_stopped()。
>
> 请以根目录的 [COMMIT_NOTES.md](../COMMIT_NOTES.md) 和
> [NEOVIM_GUIDE.md](NEOVIM_GUIDE.md) 为准。本文仅作排查过程的历史记录保留。

## 问题症状

1. **错误消息：** "copilot.lua copilot is not running"
2. **启动提示：** 每次打开 Neovide 都显示 "# Plugin Updates - lazy.nvim"，需要按 Enter 继续
3. **认证失败：** 执行 `:Copilot auth login` 没有任何反应

## 根本原因分析

### 1. lazy.nvim 启动检查导致交互提示

**问题位置：** `home/toru.nix` 中 lazy.lua 的配置
```lua
checker = { enabled = true },
```

**问题说明：**
- `checker = { enabled = true }` 会在每次启动时检查插件更新
- 如果发现更新，会显示交互式提示，要求用户按 Enter 继续
- 这会阻塞 Copilot 的正常启动

**修复：** 禁用启动检查（已实施）
```lua
checker = { enabled = false },
```

### 2. Copilot 延迟加载导致初始化不完整

**问题位置：** `copilot.lua` 中的加载事件配置
```lua
event = "InsertEnter",  -- 仅在进入 Insert 模式时加载
```

**问题说明：**
- 设置 `event = "InsertEnter"` 表示 Copilot 只在首次进入 Insert 模式时才加载
- 这导致 Copilot LSP 服务器启动延迟
- 如果在 LSP 服务器启动前就尝试使用 Copilot，会显示"not running"错误
- 认证命令 `:Copilot auth login` 在 Copilot 未加载时会失效

**修复：** 改为立即加载（已实施）
```lua
lazy = false,  -- 立即加载，不延迟
-- 删除 event = "InsertEnter"
```

### 3. 依赖插件加载时序问题

**问题位置：** `copilot-cmp` 插件的加载
```lua
config = function()
  require("copilot_cmp").setup()
end,
```

**问题说明：**
- `copilot-cmp` 是 Copilot 补全的依赖
- 如果它加载延迟或加载顺序不对，Copilot 补全会失效
- 原配置中没有明确指定其加载顺序

**修复：** 也改为立即加载（已实施）
```lua
lazy = false,  -- 也立即加载
```

## 已实施的修改

### 修改 1: 禁用 lazy.nvim 启动检查

**文件：** `/home/toru/nixos-config/home/toru.nix` (lazy.lua 部分)

```nix
"nvim/lua/config/lazy.lua" = {
  text = ''
    ...
    require("lazy").setup({
      spec = {
        { import = "plugins" },
      },
      checker = { enabled = false },  -- 改为 false
    })
  '';
};
```

### 修改 2: Copilot 立即加载

**文件：** `/home/toru/nixos-config/home/toru.nix` (copilot.lua 部分)

```nix
{
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  lazy = false,  -- 新增：立即加载
  -- 删除：event = "InsertEnter",
  config = function()
    -- 配置内容保持不变
  end,
},
{
  "zbirenbaum/copilot-cmp",
  lazy = false,  -- 新增：立即加载
  config = function()
    require("copilot_cmp").setup()
  end,
},
```

## 部署步骤

### 1. 验证配置（已完成）
```bash
cd /home/toru/nixos-config
nix flake check
# 输出：all checks passed! ✅
```

### 2. 部署系统配置（待执行）
```bash
sudo nixos-rebuild switch --flake .#thinkpad
# 这会应用新的 Neovim 配置
```

### 3. 清理缓存并重启（推荐）
```bash
# 清理 Copilot 缓存
rm -rf ~/.local/share/nvim/copilot.lua/

# 清理 lazy.nvim 缓存
rm -rf ~/.local/share/nvim/lazy/

# 重新启动 Neovide
neovide /home/toru/nixos-config
```

## 验证修复

### 1. 检查启动时是否仍有提示
启动 Neovide 后，应该**不再出现** "# Plugin Updates" 的交互式提示。
- ✅ 正常：直接进入 Neovide，无提示
- ❌ 问题：仍显示 "Plugin Updates" 提示

### 2. 验证 Copilot 是否已加载
在 Neovide 中执行：
```vim
:messages
```

查看日志中是否有关于 Copilot 初始化的信息：
- ✅ 应该看到：类似 "copilot initialized" 或 LSP 启动信息
- ❌ 如果仍有错误：记下完整的错误信息

### 3. 验证认证状态
```vim
:Copilot status
```

预期输出：
- ✅ "Authenticated" 或 "Not authenticated"（明确的状态）
- ❌ 没有反应或超时

如果显示 "Not authenticated"：
```vim
:Copilot auth login
```

### 4. 测试 Copilot 建议
1. 创建或打开一个 .nix 文件：
   ```bash
   echo "# test" > test.nix
   neovide test.nix
   ```

2. 进入 Insert 模式：
   ```
   i
   ```

3. 输入一些代码：
   ```
   environment.systemPackages = with pkgs; [
   ```

4. 等待 Copilot 显示灰色建议
   - ✅ 如果看到建议：Copilot 工作正常
   - ❌ 如果没有建议：检查错误日志

## 常见问题排查

### 问题 1: 仍然显示 "copilot is not running"

**诊断步骤：**
```bash
# 1. 检查 Copilot 日志
tail -50 ~/.local/share/nvim/lsp.log

# 2. 检查 Copilot 的 LSP 服务器是否启动
ps aux | grep copilot

# 3. 查看详细的 Neovim 消息
nvim
:messages
:verbose messages
```

**可能原因：**
1. LSP 服务器启动失败（查看 ~/.local/share/nvim/lsp.log）
2. 认证失败（运行 `:Copilot auth login`）
3. 需要重启 Neovim（`:qa!` 然后重新打开）

### 问题 2: 认证命令无响应

```vim
:Copilot auth login
```

如果没有反应：

1. **检查 Copilot 是否加载**
   ```vim
   :Copilot status
   ```

2. **查看错误日志**
   ```vim
   :messages
   ```

3. **强制重载 Copilot**
   ```vim
   :Copilot auth
   # 应该显示可用的 auth 子命令
   ```

4. **使用完整的认证命令**
   ```bash
   # 在命令行使用 GitHub CLI
   gh auth login
   ```

### 问题 3: Copilot 补全不工作

**检查列表：**
1. ✓ Copilot 已加载（`:Copilot status`）
2. ✓ 已认证（显示 "Authenticated"）
3. ✓ 当前文件类型支持 Copilot（编辑 .nix 文件）
4. ✓ 补全菜单启用（`:verbose set completeopt`）

**调试补全：**
```vim
" 手动触发补全菜单
Ctrl+Space

" 或在 Insert 模式
Ctrl+X Ctrl+O  " 触发 omni-completion
```

## Copilot.lua 的认证方式

copilot.lua 支持多种认证方式：

### 方式 1: GitHub CLI 认证（推荐）
```bash
# 系统已配置有 github-cli
# 确保已通过 GitHub CLI 认证
gh auth status

# 如果未认证
gh auth login
```

### 方式 2: VSCode 认证
如果安装了 VSCode 并已认证：
```vim
:Copilot auth
# copilot.lua 会自动使用 VSCode 的认证令牌
```

### 方式 3: 直接设备认证
```vim
:Copilot auth login
# 会显示设备代码，需要在浏览器访问 https://github.com/login/device
```

## 关键要点

✅ **lazy = false** 确保插件立即加载，不延迟
✅ **checker = { enabled = false }** 避免启动时的交互提示
✅ **完整的认证链** 确保 Copilot 可以访问 GitHub

⚠️ **部署后需要 `:qa!` 完全重启 Neovim** 
⚠️ **第一次使用需要完成认证** (`:Copilot auth login`)
⚠️ **清理缓存可以解决大多数"not running"问题**

## 后续部署

1. 部署配置：
   ```bash
   sudo nixos-rebuild switch --flake .#thinkpad
   ```

2. 清理缓存：
   ```bash
   rm -rf ~/.local/share/nvim/copilot.lua/
   rm -rf ~/.local/share/nvim/lazy/
   ```

3. 测试：
   ```bash
   neovide /home/toru/nixos-config
   # 进入 Insert 模式，输入代码，看是否有 Copilot 建议
   ```

4. 如果仍有问题：
   ```bash
   # 检查日志
   cat ~/.local/share/nvim/lsp.log
   
   # 在 Neovim 中查看消息
   nvim
   :messages
   ```

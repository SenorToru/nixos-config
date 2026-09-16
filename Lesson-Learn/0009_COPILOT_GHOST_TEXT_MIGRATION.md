# Copilot：移除 copilot-cmp，迁移到行内建议（ghost text）

> 日期：2026-09-17　|　相关提交：`8fef4d0`
> 前置文档：[0005_COPILOT_UNZIP_DEPENDENCY.md](0005_COPILOT_UNZIP_DEPENDENCY.md)、
> [0006_COPILOT_STARTUP_ISSUES.md](0006_COPILOT_STARTUP_ISSUES.md)、
> [0008_COPILOT_OFFLINE_FIX.md](0008_COPILOT_OFFLINE_FIX.md)
>
> **本文取代 06 和 08 中关于 copilot-cmp 的全部结论。**
> 那两份文档记录的修复方案（`vim.g.copilot_node_command`、`COPILOT_DEBUG`、
> `copilot.command.auth_setup()`、`server_opts_overrides.trace`、
> `:CopilotStatus` / `:CopilotStart` / `:CopilotReauth`、copilot-cmp）
> 已在本次全部撤销。

## 问题症状

### 症状 1：一输入就报错，什么都打不进去

在 Neovide 里编辑 `flake.nix`，屏幕下半部分突然出现一个标题为
`copilot:///home/toru/nixos-config/...` 的窗口，内容是：

```
Synthesized ?/0 solutions (Duplicates hidden) [done]
```

此后无论按什么键都得到：

```
E21: Cannot make changes, 'modifiable' is off
```

而 lualine 上仍然显示 `NORMAL`——按 `i` 进不了 Insert 模式。

### 症状 2：每次启动 Neovide 都报废弃警告

```
client.is_stopped is deprecated. Run ":checkhealth vim.deprecated" for more information
```

## 根本原因分析

两个症状看起来无关，其实是**同一个配置错误**的两个表现：
`copilot.lua` 的 `suggestion` / `panel` 模块与 `copilot-cmp` 被同时启用，
而这三者是互斥的。

### 原因 1：panel 的全局 `<M-CR>` 映射 + 只读 buffer（症状 1）

`copilot.lua` 的 panel 模块在 setup 时会注册一个**全局 Insert 模式**映射：

```lua
-- copilot.lua/lua/copilot/panel/init.lua:553
vim.keymap.set("i", panel.keymap.open, M.open, {
  desc = "[copilot] (panel) open",
  silent = true,
})
```

本机实测确认了它的存在：

```vim
:lua print(vim.inspect(vim.fn.maparg("<M-CR>", "i", false, true)))
" => desc = "[copilot] (panel) open", buffer = 0   （buffer = 0 表示全局）
```

而这个映射打开的面板 buffer 是**只读且会抢走焦点**的：

```lua
-- copilot.lua/lua/copilot/panel/init.lua:266-278
self.bufnr = vim.api.nvim_create_buf(false, true)
for name, value in pairs({
  buftype    = "nofile",
  modifiable = false,   -- ← 这里
  readonly   = true,
  ...
```

于是链条是：

```
在 Insert 模式误触 Alt+Enter
  → 面板打开，光标被移进面板窗口
  → 面板 buffer modifiable = false
  → 之后每一次按 i / a / o 都是 E21，且停在 NORMAL 模式
```

截图里窗口标题是 `copilot:///...`（面板 buffer 的名字）而不是 `flake.nix`，
正好印证了「当前 buffer 已经是面板」。

**为什么只在 Neovide 出现：** 在终端里按 `Alt+Enter`，终端通常把它编码成
`<Esc><CR>` 两个键，Neovim 收到的是「退出 Insert 模式 + 回车」，碰不到这个映射。
而 Neovide 是 GUI，按键带完整修饰符直接送进 Neovim，`<M-CR>` 是真的 `<M-CR>`，
映射就会触发。

至于 `?/0 solutions` 里的 `0`——那是面板本次请求拿到 0 条建议，是个独立的小问题
（面板补全和行内补全走的是不同的 LSP 方法），不是 E21 的原因。

### 原因 2：copilot-cmp 使用了 Neovim 0.11+ 已废弃的 API（症状 2）

通过 hook `vim.deprecate` 抓到了完整调用栈，确认了警告来源：

```
client.is_stopped
stack traceback:
  .../nvim-0.12.4/share/nvim/runtime/lua/vim/lsp/client.lua:264: in function 'is_stopped'
  .../lazy/copilot-cmp/lua/copilot_cmp/source.lua:23:  in function 'is_available'
  .../lazy/copilot-cmp/lua/copilot_cmp/init.lua:41:    in function '_on_insert_enter'
  .../lazy/copilot-cmp/lua/copilot_cmp/init.lua:56:    in function <...:55>
  [C]: in function 'nvim_exec_autocmds'
  .../lua/vim/lsp/client.lua:1173: in function 'on_attach'
```

问题代码：

```lua
-- copilot-cmp/lua/copilot_cmp/source.lua:23
if self.client.is_stopped() or not self.client.name == "copilot" then
```

Neovim 0.11 起 `client.is_stopped()`（点调用）已废弃，应写成 `client:is_stopped()`。

> 顺带一提，这一行还有个 copilot-cmp 自身的逻辑 bug：
> `not self.client.name == "copilot"` 会被解析成 `(not self.client.name) == "copilot"`，
> 也就是 `false == "copilot"`，永远为 `false`。作者的意图显然是
> `self.client.name ~= "copilot"`。这也侧面说明这个插件已经没人维护了。

**为什么这是「不可修复」的：**

| 插件 | 最后提交 | 状态 |
|------|----------|------|
| `zbirenbaum/copilot.lua` | `b2b899f` **2026-09-12** | 活跃维护 |
| `zbirenbaum/copilot-cmp` | `15fc12a` **2024-12-11** | 近两年无更新 |

copilot-cmp 落后 copilot.lua 将近两年。同时 copilot-cmp 自己的 README 明确要求
**关闭** `suggestion` 和 `panel` 模块，而本机配置里两个都开着——这是个从一开始
就不该存在的组合。

### 原因 3：配置里还有一批依赖已失效 API 的死代码

新版 copilot.lua 的模块结构变了，旧配置调用的这些东西都已不存在：

| 旧配置里的调用 | 现状 |
|----------------|------|
| `require("copilot.command").auth_setup()` | `command.lua` 里只有 `version` / `attach` / `detach` / `toggle` / `enable` / `disable`，**没有 `auth_setup`** |
| `require("copilot.api").get_status(...)` | `copilot/api.lua` 已变成 `copilot/api/` 目录，且其 `init.lua` 里**没有 `get_status`** |
| `vim.g.copilot_node_command` | 这是 **copilot.vim（vimscript 版）** 的变量，copilot.lua 完全不读它 |
| `:CopilotStatus` / `:CopilotStart` / `:CopilotReauth` | 基于上面两个失效 API 定义，调用只会静默失败 |

其中 `auth_setup()` 那一处被 `pcall` 包着，所以**报错被静默吞掉了**——配置看起来
"没问题"，实际上从来没执行成功过。这是这类死代码最麻烦的地方。

## 已实施的修复

### 修复 1：移除 copilot-cmp，统一走行内建议

`home/toru.nix` 中 `nvim/lua/plugins/copilot.lua`：

```lua
return {
  {
    "zbirenbaum/copilot.lua",
    lazy = false,
    config = function()
      require("copilot").setup({
        copilot_node_command = "node",

        suggestion = {
          enabled = true,
          auto_trigger = true,
          hide_during_completion = true,   -- cmp 菜单弹出时自动隐藏 ghost text
          debounce = 75,
          keymap = {
            accept = "<M-l>",
            next   = "<M-]>",
            prev   = "<M-[>",
            dismiss = "<C-]>",
            accept_word = false,
            accept_line = false,
          },
        },

        panel = {
          enabled = true,
          auto_refresh = false,
          keymap = {
            jump_prev = "[[",
            jump_next = "]]",
            accept    = "<CR>",
            refresh   = "gr",
            open      = false,   -- ★ 关键：关掉全局 <M-CR> 映射
          },
        },

        filetypes = { ... },
      })
    end,
  },
}
```

同时从 `nvim/lua/plugins/completion.lua` 中删除：

```lua
{ name = "copilot", priority = 10 },   -- 删除
"zbirenbaum/copilot-cmp",              -- 从 dependencies 删除
```

### 修复 2：删除全部死代码

- `init.lua`：删掉 `vim.g.copilot_node_command`、`vim.env.COPILOT_DEBUG`、
  整个 `vim.schedule(... auth_setup() ...)` 块
- `copilot.lua`：删掉 `server_opts_overrides = { trace = "verbose" }` 和
  `:CopilotStatus` / `:CopilotStart` / `:CopilotReauth` 三个自定义命令
- 同时去掉了 `cmd = "Copilot"` 与 `lazy = false` 并存的矛盾写法
  （`lazy = false` 已经是立即加载，`cmd` 触发器没有意义）

改用官方子命令：`:Copilot status` / `:Copilot auth info` / `:Copilot auth signin`。

## 为什么这样解决

### 为什么是移除 copilot-cmp，而不是「关掉 suggestion/panel 去迁就它」

按 copilot-cmp 的 README，正确用法确实是关掉 `suggestion` 和 `panel`。
那样也能消掉 E21。但**不能消掉启动警告**——警告来自 copilot-cmp 自己的代码。
而启动警告是本次明确要解决的问题之一，所以这条路走不通。

更重要的是方向问题：

| | 保留 copilot-cmp | 移除 copilot-cmp（选此） |
|---|---|---|
| E21 面板问题 | 能解决 | 能解决 |
| 启动废弃警告 | **无法解决** | 解决 |
| 长期可维护性 | 依赖一个两年未更新、且带已知逻辑 bug 的插件 | 只依赖活跃维护的 copilot.lua |
| Neovim 0.13 兼容性 | `client.is_stopped` 一旦真正移除就直接崩 | 不受影响 |

代价是 Copilot 建议从「补全菜单里的一项」变成「行内灰色文字」，
接受键从 `Enter` 变成 `Alt+l`。这是习惯上的改变，但配置里开了
`hide_during_completion = true`，ghost text 和 cmp 菜单不会互相干扰，
体感上是两套独立、互不打扰的补全。

如果将来确实想让 Copilot 回到补全菜单里，**维护中的**方案是换
`blink.cmp` + `blink-copilot`（copilot.lua 的 README 也是这么推荐的），
但那是一次更大的迁移，本次没做。

### 为什么 panel 用 `open = false` 而不是 `enabled = false`

`enabled = false` 会让面板功能彻底消失，连 `:Copilot panel open` 都没了。
而面板本身是有用的（一次比较多条候选）。真正的问题只在于那个**全局按键映射**
太容易误触。所以只关映射、保留功能：

```lua
panel = { enabled = true, keymap = { open = false, ... } }
```

代码上确认这样是安全的——`panel/init.lua` 的 setup 里是
`if panel.keymap.open then vim.keymap.set(...) end`，传 `false` 就直接跳过注册，
其余功能不受影响。

## 后续注意事项

### ⚠️ 不要做的事

   想让 Copilot 回到补全菜单，走 `blink.cmp` + `blink-copilot`。

3. **不要把 `panel.keymap.open` 改回 `<M-CR>`。**
   在 GUI（Neovide）里极易误触，代价是整个编辑器「假死」。

4. **不要在 `modules/common.nix` 里再加 `fonts.*`。**
   字体统一在 `modules/localization.nix`。


### ✅ 需要记住的排查经验

3. **`pcall` 会把死代码伪装成正常配置。**
   `pcall(function() require("copilot.command").auth_setup() end)` 这种写法，
   即使函数根本不存在也不会有任何提示。给插件升级后，
   要主动确认自己调用的 API 还在：

   ```bash
   grep -n "^function M\." ~/.local/share/nvim/lazy/<插件>/lua/<模块>.lua
   ```

4. **定位废弃警告的来源，可以 hook `vim.deprecate` 打调用栈：**

   ```bash
   nvim --cmd 'lua local od=vim.deprecate; vim.deprecate=function(...)
     print(debug.traceback(tostring(({...})[1]), 2)); return od(...) end'
   ```

   比在插件目录里瞎 grep 快得多（本次 `is_stopped` 在 4 个插件里都出现过，
   但只有 copilot-cmp 是真正的触发者）。

5. **Neovim 里遇到「按什么键都没反应 / 报 E21」，先确认光标在哪个 buffer。**
   `Ctrl+w w` 切窗口、`:ls` 看 buffer 列表。只读 buffer（面板、quickfix、
   帮助、Lazy 窗口）都会有这个表现。

6. **`nix build` 比 `nixos-rebuild switch` 更适合验证。**
   不需要 sudo，不改系统状态，并且可以直接检查产物：

## 当前配置速查

| 操作 | 按键 / 命令 |
|------|-------------|
| 接受行内建议 | `Alt+l` |
| 下一个 / 上一个建议 | `Alt+]` / `Alt+[` |
| 拒绝建议 | `Ctrl+]` |
| 打开面板 | `:Copilot panel open`（`Alt+Enter` 已禁用） |
| 查看状态 | `:Copilot status` |
| 重新登录 | `:Copilot auth signin` |
| 自检 | `:checkhealth copilot` |

Copilot 建议**不在** `Ctrl+Space` 的补全菜单里，只以行内灰色文字出现。

## 相关文档

- [0000_NEOVIM_GUIDE.md](0000_NEOVIM_GUIDE.md) —— 第六、七步已按本文更新，含完整用法
- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— 同批次发现的 `nvim` / `vim` 双派生问题
- [0006_COPILOT_STARTUP_ISSUES.md](0006_COPILOT_STARTUP_ISSUES.md) —— ⛔ 第 3 节已被本文取代
- [0008_COPILOT_OFFLINE_FIX.md](0008_COPILOT_OFFLINE_FIX.md) —— ⛔ 已被本文整体取代

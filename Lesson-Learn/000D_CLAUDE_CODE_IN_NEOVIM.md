# 在 Neovide / Neovim 里使用 Claude Code

> 日期：2026-09-17　|　相关配置：`modules/development.nix`、`home/toru.nix`
>
> 目标：在 Neovide 里获得和 VSCode 扩展基本对等的 Claude Code 体验 ——
> 选区上下文、`@` 引用文件、修改以 diff 形式送回编辑器审阅。

## 方案选择

Claude Code 在编辑器里有三种用法，差别很大：

| 方案 | 能力 | 评价 |
|------|------|------|
| `:terminal claude` | 只是个终端，Claude 不知道你在编辑什么 | 零配置，但等于没集成 |
| 简单的终端包装插件 | 多了开关面板的快捷键 | 仍然拿不到编辑器上下文 |
| **`coder/claudecode.nvim`**（选此） | 实现了 Claude Code 的 IDE 协议 | 和 VSCode 扩展走同一套 WebSocket 协议，能力对等 |

**为什么是 claudecode.nvim：** 它不是把 CLI 塞进一个终端窗口就完事，
而是在 Neovim 里起一个 WebSocket 服务端，实现 Claude Code 官方的 IDE 集成协议 ——
也就是 VSCode 扩展用的那一套。所以它能做到：

- Claude 知道你当前打开/选中的是什么
- `@` 引用文件时补全的是你工程里真实的文件
- Claude 的修改**不是直接写盘**，而是在 Neovim 里开一个 diff 让你审阅后再决定

纯 Lua 实现，没有额外的运行时依赖。

## 配置

### 1. 装 CLI

`claude` 必须同时出现在两个地方：

```nix
# modules/development.nix —— 让终端里也能直接 `claude`
environment.systemPackages = with pkgs; [
  claude-code
];
```

```nix
# home/toru.nix —— 关键：claudecode.nvim 是从 Neovim 内部 spawn `claude` 的
programs.neovim.extraPackages = with pkgs; [
  claude-code
];
```

> ⚠️ **只装进 `systemPackages` 是不够的。**
> Neovim 是个 wrapper 脚本，它把 `extraPackages` 里的东西拼成自己的 `PATH`。
> 插件 spawn 子进程时用的是 Neovim 的 PATH，不是你登录 shell 的 PATH。
> 这和 Copilot 当初找不到 `node` / `unzip` 是同一个机制，
> 参见 [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) 的「问题 1」。

`claude-code` 是 unfree 包，本仓库已在 `modules/common.nix` 里开了
`nixpkgs.config.allowUnfree = true`，不用额外处理。

nixpkgs 的这个包经过 auto-patchelf，**不依赖 nix-ld**
（见 [000C_NIX_LD_PREBUILT_BINARIES.md](000C_NIX_LD_PREBUILT_BINARIES.md)）。

### 2. 插件

`home/toru.nix` 里新增 `nvim/lua/plugins/claudecode.lua`：

```lua
return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    cmd = { "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSend", ... },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.35,
        provider = "snacks",
        auto_close = true,
        auto_insert = true,
      },
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
      },
    },
    keys = { ... },
  },
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = { input = { enabled = true }, picker = { enabled = true } },
  },
}
```

几个决定：

- **不设 `terminal_cmd`。** 默认值就是 `"claude"`，从 PATH 找。
  因为走的是 nixpkgs 而不是 `npm i -g` 或 `claude migrate-installer`，
  不需要写死路径 —— 写死了反而会在包升级换 hash 后失效。
- **`provider = "snacks"` 而不是 `"auto"`。** `snacks.nvim` 是必装依赖，
  既然一定在，就明确指定，避免 `auto` 在某些加载顺序下悄悄退回 native 终端。
- **`snacks.nvim` 设 `lazy = false` + 高 `priority`。**
  它同时给 claudecode 提供终端和 diff 浮窗，延迟加载容易出时序问题。

## 快捷键

leader 是空格。

| 按键 | 命令 | 作用 |
|------|------|------|
| `<Space>ac` | `:ClaudeCode` | 开关 Claude 面板 |
| `<Space>af` | `:ClaudeCodeFocus` | 聚焦面板 |
| `<Space>ar` | `:ClaudeCode --resume` | 列出本目录的历史会话，交互选择 |
| `<Space>aR` | `:ClaudeCode --resume --fork-session` | 从某个历史会话岔出一条新会话 |
| `<Space>aC` | `:ClaudeCode --continue` | 直接进最近一次会话，不问 |
| `<Space>am` | `:ClaudeCodeSelectModel` | 选模型 |
| `<Space>ab` | `:ClaudeCodeAdd %` | 把当前文件加入上下文 |
| `<Space>as`（**可视模式**） | `:ClaudeCodeSend` | 把选中的代码发给 Claude |
| `<Space>aa` | `:ClaudeCodeDiffAccept` | 接受 Claude 的修改 |
| `<Space>ad` | `:ClaudeCodeDiffDeny` | 拒绝 Claude 的修改 |
| `<Space>aS` | `:ClaudeCodeStatus` | 查看连接状态 |

和已有映射不冲突：LSP 占的是 `<Space>rn` / `<Space>ca` / `<Space>f`，
Copilot 用的是 `Alt` 系列。

## 选择历史会话

Claude Code 的会话是**按目录**存的，路径按 cwd 编码：

```
~/.claude/projects/-home-toru-nixos-config/
├── 2806d414-0e05-47e0-82c6-a834bed546c2.jsonl
├── 43f5aaee-89d5-4026-951c-20bc6f138f12.jsonl
└── 8adcc5b4-3528-4f42-b968-038d1e9ec9c1.jsonl
```

四个入口：

| 方式 | 行为 |
|------|------|
| `<Space>ar` | 列出**本目录**的历史会话，交互选择 |
| `<Space>aR` | 同上，但选中后岔出一条新会话，不续写原记录 |
| `<Space>aC` | 直接进最近一次，不弹选择器 |
| 会话内输入 `/resume` | CLI 自带的斜杠命令，同样弹选择器 |

CLI 侧的对应选项：

```
-r, --resume [value]   Resume a conversation by session ID, or
                       open interactive picker with optional search term
-c, --continue         Continue the most recent conversation in the current directory
--fork-session         When resuming, create a new session ID instead of
                       reusing the original (use with --resume or --continue)
```

`--fork-session` 的用处：想从某个历史会话岔出一条新线去试别的方向，
又不希望把新的往来写进原会话的记录里。原会话保持原样，可以再回去接着聊。

## 典型工作流

```
1. 打开工程：  neovide ~/nixos-config
2. <Space>ac   打开 Claude 面板（右侧 35% 宽）
3. 在代码里选中一段（v 或 V），按 <Space>as 发给 Claude
4. 在面板里描述你要什么
5. Claude 提出修改 -> Neovim 自动开一个竖向 diff
6. 看完：<Space>aa 接受 / <Space>ad 拒绝
```

## 部署与验证

```bash
sudo nixos-rebuild switch --flake .#thinkpad

# 首次启动 Neovide，lazy.nvim 会自动拉取 claudecode.nvim 和 snacks.nvim
neovide ~/nixos-config
```

在 Neovim 里：

```vim
:checkhealth claudecode   " 检查 CLI 和 WebSocket 服务端
:ClaudeCodeStatus         " 看连接状态
```

命令行确认 CLI 可用：

```bash
claude --version          # 应输出 2.1.223 (Claude Code)
```

## 后续注意事项

1. **认证是和 CLI 共享的。** 凭据在 `~/.claude/.credentials.json`，
   在终端 `claude` 登录过一次，Neovim 里就直接可用，不用重复登录。

2. **`claude` 版本跟着 nixpkgs 走。** 本机是 2.1.223，
   而 VSCode 扩展自带的是 2.1.273 —— 两者独立，版本可以不一致，互不影响。
   想升级 CLI 就更新 flake input。

3. **别改成 `terminal_cmd = "/nix/store/..."`。**
   写死 store 路径会在包升级后失效。保持默认从 PATH 找。

4. **如果 `:ClaudeCodeStatus` 说找不到 `claude`**，先确认它在 **Neovim 的** PATH 里：

   ```vim
   :lua print(vim.fn.exepath("claude"))
   ```

   为空说明 `extraPackages` 没生效 —— 检查是不是只加进了 `systemPackages`，
   或者 home-manager 那一层没激活成功
   （见 [000B_HOME_MANAGER_ACTIVATION_CONFLICT.md](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md)）。

5. **Copilot 和 Claude Code 可以共存。** Copilot 负责行内的即时补全（`Alt+l`），
   Claude Code 负责需要对话和大范围改动的任务（`<Space>a` 系列），
   两者不抢按键也不抢补全菜单。

6. **面板里已有活会话时，`<Space>ar` 的 `--resume` 会被静默丢弃。**
   这个很容易误判成「按键没绑上」。实际是插件的 toggle 逻辑：

   ```lua
   -- claudecode.nvim/lua/claudecode/terminal/snacks.lua:447
   if terminal and terminal:buf_valid() then
     -- 只是 hide / show 已有终端，cmd_string 根本没用上
   else
     -- 只有这条分支才真正带参数启动 claude
   ```

   也就是说 `--resume` / `--continue` / `--fork-session` **只在新起进程时生效**。
   已经有会话在跑的时候按 `<Space>ar`，表现是面板闪一下（显示/隐藏），
   没有任何选择器。

   两个办法：
   - 在已有会话里直接打 `/resume`（推荐，不用重启进程）
   - 或者先 `:ClaudeCodeClose` 真正关掉，再按 `<Space>ar`

7. **会话按目录隔离，从错的目录启动就看不到想要的会话。**
   `--continue` 的官方说明里明确写着 *in the current directory*。
   存储路径是按 cwd 编码的（见「选择历史会话」一节）。

   所以要 `neovide ~/nixos-config`，而不是从家目录开了 neovide 再去编辑文件 ——
   后者的 cwd 是 `~`，选择器里会是空的，或者列出一堆不相干的会话。
   已经开错了的话，在 Neovim 里 `:cd ~/nixos-config` 再开面板。

## 相关文档

- [000C_NIX_LD_PREBUILT_BINARIES.md](000C_NIX_LD_PREBUILT_BINARIES.md) —— VSCode 扩展版 CLI 为什么需要 nix-ld
- [0000_NEOVIM_GUIDE.md](0000_NEOVIM_GUIDE.md) —— Neovim 基础操作与 Copilot 用法
- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— `extraPackages` 与 wrapper PATH 的机制

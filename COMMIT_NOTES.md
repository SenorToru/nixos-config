# 提交注释：修复 Neovide 下的 Copilot 故障 + 配置去重

> 日期：2026-09-17
> 分支：`master`
> 上一个提交：`eca7d14 feat: add unzip for Copilot in NeoVim.`

---

## 一、建议的提交信息

```
fix: 修复 Neovide 下 Copilot 不可用，并清理配置中的重复与矛盾

Copilot 在 Neovide 中一输入就卡死在只读 buffer（E21），启动时还会报
client.is_stopped 废弃警告。根因是配置里同时启用了 copilot.lua 的
suggestion/panel 模块和已停止维护的 copilot-cmp，两者互斥。

- 移除 copilot-cmp，统一走 copilot.lua 自带的行内建议（ghost text）
- 关闭 panel 的全局 <M-CR> 映射（open = false）
- 删除依赖已失效 API 的死代码（auth_setup / copilot.api.get_status 等）
- 合并重复的 programs.neovim 声明：vim/vi 此前指向不带 extraPackages
  的系统级 neovim，Copilot 在其下必然离线
- 修正 fontconfig.defaultFonts 中 5 个无法解析的字体族名
- 字体声明统一收进 localization.nix，消除与 common.nix 的重复
- 将默认浏览器设为 Firefox（此前由 GNOME 自行选了 Epiphany）
- 清理 8 处未使用的模块参数
- 设置 home-manager.backupFileExtension，避免文件冲突导致整个激活失败
- 更新 NEOVIM_GUIDE.md 的 Copilot 章节，并为两份过时文档加废弃横幅
```

---

## 二、未提交变更清单

### 已修改（10 个文件）

| 文件 | 变更内容 |
|------|----------|
| `home/toru.nix` | Copilot 配置重写；移除 copilot-cmp；`panel.keymap.open = false`；删除失效死代码；neovim 加 `viAlias`/`vimAlias`/`defaultEditor = true`；新增 `xdg.mimeApps` 把默认浏览器设为 Firefox；新增 `home.sessionVariables.BROWSER`；移除未用参数 `config`、`inputs` |
| `modules/development.nix` | **删除**系统级 `programs.neovim` 整块（附详细注释说明为何不能加回）；移除未用参数 `config` |
| `modules/common.nix` | **删除** `fonts` 整块（移交 localization.nix）；移除未用参数 `config` |
| `modules/localization.nix` | 接管全部字体声明；修正 5 个无效字体族名；补上 `fontconfig.enable` |
| `modules/apps.nix` | 移除未用参数 `config` |
| `modules/desktop.nix` | 移除未用参数 `config`、`pkgs` |
| `modules/flatpak.nix` | 移除未用参数 `config`、`pkgs` |
| `modules/browsers.nix` | 移除未用参数 `config` |
| `hosts/thinkpad/default.nix` | 移除未用参数 `config`；新增 `home-manager.backupFileExtension = "hm-bak"` |
| `Lesson-Learn/NEOVIM_GUIDE.md` | 重写第六、七步 Copilot 章节；更新快速参考卡；新增 E21 与 Copilot 排查两条 FAQ；`:Copilot auth login` → `auth signin`；补 `:checkhealth` 命令 |

### 新增到版本控制（3 个此前未跟踪的文件）

| 文件 | 说明 |
|------|------|
| `Lesson-Learn/COPILOT_OFFLINE_FIX.md` | **已加⛔废弃横幅** —— 本文记录的修复方案已被本次提交整体撤销 |
| `Lesson-Learn/COPILOT_STARTUP_ISSUES.md` | **已加⛔废弃横幅** —— 第 3 节关于 copilot-cmp 的结论已作废 |
| `Lesson-Learn/LAZY_NVIM_DASHBOARD.md` | Lazy.nvim 仪表板说明，内容仍然有效 |
| `COMMIT_NOTES.md` | 本文件 |

### ⚠️ 不在本仓库内、不会被提交的改动

VSCode 的用户设置 **不由本 nix 仓库管理**，以下两项是直接改在
`~/.config/Code/User/settings.json` 里的，`git` 看不到它们：

```jsonc
"claudeCode.useCtrlEnterToSend": true,   // Claude Code 改用 Ctrl+Enter 发送
"chat.fontSize": 16                      // 聊天正文字号（默认 13）
```

换机器或重装时这两项会丢。如果希望纳入版本控制，需要改用 home-manager 的
`programs.vscode.profiles.default.userSettings`——但那会让 HM 接管整个
settings.json，VSCode 内部自己写入的键（如 `claudeCode.preferredLocation`）
会被覆盖，属于另一个决定，本次没有动。

---

## 三、问题

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

---

## 四、根本原因分析

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

### 原因 4：`nvim` 和 `vim` 是两个不同的 neovim（潜在雷）

这个问题本次是顺带发现的，此前一直埋着。两处同时声明了 neovim：

```nix
# modules/development.nix（系统级 NixOS 模块）
programs.neovim = {
  enable = true;
  defaultEditor = true;    # ← 和下面矛盾
  viAlias = true;
  vimAlias = true;
  # 没有 extraPackages
};

# home/toru.nix（home-manager 模块）
programs.neovim = {
  enable = true;
  defaultEditor = false;   # ← 和上面矛盾
  extraPackages = [ nixfmt nil nodejs_24 github-cli unzip ... ];
};
```

这两个是**不同的 option 命名空间**，所以 Nix 不会报冲突，但结果是装了两个 neovim：

```
$ readlink -f $(which nvim)
/nix/store/q3d42c9fd80xr8a0797ciyyfdw29vp6k-neovim-0.12.4/bin/nvim   ← home-manager 版

$ readlink -f $(which vim)
/nix/store/9lza75apxfn5v6s5bh72l26qpxahh62s-neovim-0.12.4/bin/nvim   ← 系统版（不同 hash！）
```

只有 home-manager 那个的 wrapper 里有 Copilot 需要的依赖：

```
$ grep -oE '(nodejs|unzip)-[0-9.]+/bin' $(readlink -f $(which nvim))
nodejs-24.19.0/bin
unzip-6.0/bin

$ grep -oE '(nodejs|unzip)-[0-9.]+/bin' $(readlink -f $(which vim))
（无输出）
```

**后果：** 用 `nvim` 打开文件 Copilot 一切正常；用 `vim` 或 `vi` 打开，
Copilot 的 language server 找不到 `node` 和 `unzip`，表现为
`Status: Offline` / `copilot is not running`。这正是
`COPILOT_OFFLINE_FIX.md` 当初想解决的症状——但当时找错了方向，
去 init.lua 里加 `vim.g.copilot_node_command`（一个 copilot.lua 根本不读的变量），
而真正的原因在 nix 层。

### 原因 5：fontconfig 里 5 个字体族名全部无效

`modules/common.nix` 的 `fontconfig.defaultFonts` 整块是**空转**的：

```
$ fc-match "Sarasa Mono"          → NotoSans.ttf: "Noto Sans"   ❌ 回退
$ fc-match "Sarasa Gothic"        → NotoSans.ttf: "Noto Sans"   ❌ 回退
$ fc-match "Noto Sans CJK"        → NotoSans.ttf: "Noto Sans"   ❌ 回退
$ fc-match "Noto Sans Mono CJK"   → NotoSans.ttf: "Noto Sans"   ❌ 回退
$ fc-match "Noto Serif CJK"       → NotoSans.ttf: "Noto Sans"   ❌ 回退
```

`sarasa-gothic` 只提供带地区后缀的族名（`Sarasa Mono J` / `SC` / `TC` / `K` /
`CL` / `HC`），`noto-fonts-cjk` 同理（`Noto Sans CJK JP` / `SC` / ...）。
**fontconfig 对不存在的族名不会报任何错**，只会静默回退到默认字体——
所以这个 bug 藏了很久。

这和之前的提交 `4062d2b fix: SarasaMono font does not exist, use Sarasa Mono J as
replacement.` 是**完全同一类错误**：当时只修了 Neovim 的 `guifont`，
漏掉了 common.nix 里的 fontconfig。

### 原因 6：从来没人声明过默认浏览器

```
$ xdg-settings get default-web-browser
org.gnome.Epiphany.desktop
```

仓库里装了 Firefox（`home/toru.nix`）、Zen、Brave（`modules/browsers.nix`），
但没有任何模块声明默认浏览器，于是 GNOME 自己挑了 Epiphany（GNOME Web）。
从终端或其它应用点链接都会跳到 Epiphany。

---

## 五、解决方法

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

### 修复 3：统一 neovim 声明

`modules/development.nix` 删除整个 `programs.neovim` 块，并留下注释说明为何不能加回。
`home/toru.nix` 接手三个选项：

```nix
programs.neovim = {
  enable = true;
  defaultEditor = true;   # 从 false 改为 true
  viAlias = true;         # 从 development.nix 迁入
  vimAlias = true;        # 从 development.nix 迁入
  extraPackages = with pkgs; [ nixfmt nil nodejs_24 github-cli unzip lua-language-server ];
};
```

验证（构建产物，未 switch）：

```
$ ls -l .../home-path/bin/ | grep -E " (vi|vim|nvim) ->"
nvim -> /nix/store/50rjvg0arngbvds1f9dpwy8idfg94k10-neovim-0.12.4/bin/nvim
vi   -> /nix/store/50rjvg0arngbvds1f9dpwy8idfg94k10-neovim-0.12.4/bin/vi
vim  -> /nix/store/50rjvg0arngbvds1f9dpwy8idfg94k10-neovim-0.12.4/bin/vim
                    ^^^^^^^ 三者同一个 hash

$ grep -oE '(nodejs|unzip|nixfmt)-[0-9.]+/bin' /nix/store/50rjvg0.../bin/nvim
nixfmt-1.4.0/bin
nodejs-24.19.0/bin
unzip-6.0/bin
```

另外确认了系统 profile 里已经没有 neovim：

```
$ ls result/sw/bin/ | grep -E "^(vi|vim|nvim)$"
（无输出）
```

### 修复 4：字体声明收拢 + 修正族名

`modules/common.nix` 删除整个 `fonts` 块，`modules/localization.nix` 成为唯一声明处：

```nix
fontconfig.defaultFonts = {
  monospace = [ "Sarasa Mono J"   "Noto Sans Mono CJK JP" ];
  sansSerif = [ "Sarasa Gothic J" "Noto Sans CJK JP" ];
  serif     = [ "Noto Serif CJK JP" ];
};
```

逐个验证通过：

```
$ fc-match "Sarasa Mono J"          → Sarasa-Regular.ttc: "Sarasa Mono J"          ✅
$ fc-match "Noto Sans Mono CJK JP"  → NotoSansMonoCJK-VF.otf.ttc: "..."            ✅
$ fc-match "Sarasa Gothic J"        → Sarasa-Regular.ttc: "Sarasa Gothic J"        ✅
$ fc-match "Noto Sans CJK JP"       → NotoSansCJK-VF.otf.ttc: "Noto Sans CJK JP"   ✅
$ fc-match "Noto Serif CJK JP"      → NotoSerifCJK-VF.otf.ttc: "..."               ✅
```

并确认新族名已进入构建产物的 `/etc/fonts/conf.d/`。

### 修复 5：默认浏览器设为 Firefox

`home/toru.nix`：

```nix
xdg.mimeApps = {
  enable = true;
  defaultApplications = {
    "text/html"                 = [ "firefox.desktop" ];
    "application/xhtml+xml"     = [ "firefox.desktop" ];
    "x-scheme-handler/http"     = [ "firefox.desktop" ];
    "x-scheme-handler/https"    = [ "firefox.desktop" ];
    "x-scheme-handler/about"    = [ "firefox.desktop" ];
    "x-scheme-handler/unknown"  = [ "firefox.desktop" ];
  };
};

home.sessionVariables.BROWSER = "firefox";
```

生成的 `~/.config/mimeapps.list` 已验证内容正确。
`firefox.desktop` 这个 ID 也已确认存在于
`/etc/profiles/per-user/toru/share/applications/`。

### 修复 6：清理未使用的模块参数

8 处：`config` 从 apps / browsers / desktop / flatpak / development / common /
localization / hosts-thinkpad 中移除，`inputs` 和 `config` 从 home/toru.nix 移除，
`pkgs` 从 desktop / flatpak 移除（这两个文件确实没用到 pkgs）。

### 修复 7（仓库外）：VSCode 设置

```jsonc
// ~/.config/Code/User/settings.json —— User 全局作用域
"claudeCode.useCtrlEnterToSend": true,
"chat.fontSize": 16
```

两点说明：

- `claudeCode.useCtrlEnterToSend` 是 Claude Code 扩展 `v2.1.273` 自带的选项，
  默认 `false`。官方描述："use Ctrl/Cmd+Enter to send prompts instead of just
  Enter. This allows Enter to create new lines."
- `chat.fontSize` 是 **VSCode 核心**设置（默认 `13`，范围 6–100），不属于任何扩展。
  已确认 Claude Code 扩展会监听它
  （`extension.js` 里有 `affectsConfiguration("chat.fontSize")`），
  内置的 Copilot Chat 也用同一个键，所以**一个设置同时覆盖两个聊天面板**。

> 另外：本机 `~/.vscode/extensions/` 里**没有**独立安装的 GitHub Copilot 扩展。
> Copilot 是 VSCode 1.119 自带的内置扩展
> （`.../resources/app/extensions/copilot`），所以无需额外装东西，
> `chat.fontSize` 一样生效。

---

## 六、为什么这样解决

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

### 为什么把 neovim 统一到 home-manager 而不是系统级

因为 Copilot 需要的依赖（`node`、`unzip`）必须进 neovim 的 **wrapper PATH**，
而这靠 `extraPackages` 实现。把 `extraPackages` 放系统级也能做到，
但 neovim 的**配置文件**（`init.lua` 和整个 `lua/` 目录）已经由
home-manager 的 `xdg.configFile` 管理了。配置和运行时依赖放在同一层，
以后只需要改一个文件，不会再出现「改了一边忘了另一边」。

顺便说明为什么不是简单地「把 `defaultEditor` 改成一致」：
那只统一了 `$EDITOR`，`vim` / `vi` 仍然会指向那个不带依赖的系统 neovim，
真正的坑还在。必须删掉整块声明。

### 为什么字体收进 localization.nix 而不是 common.nix

原先 `common.nix` 的 `defaultFonts` 里引用了 `Noto Sans CJK`，
而提供它的 `noto-fonts-cjk-sans` 只装在 `localization.nix` 里——
**声明和依赖跨模块分离**，这是最容易腐烂的结构。
字体族名和提供它的包必须在同一个文件里，改的时候才能一眼看到对应关系。

选 `localization.nix` 而不是 `common.nix`，是因为字体和输入法本来就是
本地化（i18n）的一部分，`localization.nix` 里已经有 fcitx5 了，语义上更贴。

### 为什么用 `xdg.mimeApps` 而不是 `xdg-settings set`

`xdg-settings set default-web-browser firefox.desktop` 是**命令式**的，
改的是用户家目录里的状态，换机器、重装、或者哪天手滑被覆盖了都要重新执行，
而且这个状态不在版本控制里。`xdg.mimeApps` 是**声明式**的，
由 home-manager 生成 `~/.config/mimeapps.list`，
和这个仓库其它所有配置一样可复现。

额外加 `home.sessionVariables.BROWSER = "firefox"` 是为了兜底：
一部分 CLI / TUI 程序不读 `mimeapps.list`，只认 `$BROWSER`。

---

## 七、部署与验证

```bash
cd /home/toru/nixos-config

# 1. 已验证：完整构建通过（未 switch）
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --no-link

# 2. 应用
sudo nixos-rebuild switch --flake .#thinkpad

# 3. 清掉已移除的插件（lazy.nvim 不会自动删）
nvim
:Lazy clean       # 会列出 copilot-cmp，确认删除
:qa!
```

> ### ⚠️ 首次 switch 时遇到的激活失败（已修复）
>
> 第一次 `nixos-rebuild switch` 时 home-manager 激活失败：
>
> ```
> Existing file '/home/toru/.local/share/applications/mimeapps.list' would be clobbered
> Failed to restart home-manager-toru.service
> ```
>
> **原因：** `xdg.mimeApps` 会同时管理两个路径 —— `~/.config/mimeapps.list`
> 和**已废弃的** `~/.local/share/applications/mimeapps.list`。后者本机已存在一个
> 0 字节的空文件（2026-09-06 生成），HM 默认不敢覆盖任何非自己管理的文件，于是整个激活中断。
>
> **这个失败很有欺骗性：** 系统层（`/etc`、字体、systemPackages）已经切过去了，
> 但 home 层（配置文件链接、mimeapps.list）完全没生效 —— 属于半成功状态。
> 判断方法：
>
> ```bash
> ls -la ~/.config/mimeapps.list          # 不存在 = home 层没生效
> ls -la ~/.config/nvim/init.lua          # 看 symlink 指向哪个 home-manager-files hash
> ```
>
> **已做的两件事：**
> 1. 移走那个 0 字节空文件（备份在 `/tmp/claude-1000/`，内容为空，无信息损失）
> 2. 在 `hosts/thinkpad/default.nix` 加上 `home-manager.backupFileExtension = "hm-bak"`，
>    以后 HM 遇到挡路的文件会自动改名成 `<原名>.hm-bak` 再继续，不再中断整个激活

验证清单：

| 检查项 | 命令 | 期望结果 |
|--------|------|----------|
| Copilot 认证 | `:Copilot status` | `Authenticated as GitHub user: SenorToru (status: OK)` |
| 无废弃警告 | 重启 Neovide 看首屏 | 不再出现 `client.is_stopped is deprecated` |
| 面板映射已关 | `:imap <M-CR>` | `No mapping found` |
| 行内建议可用 | Insert 模式输入代码，停 1 秒 | 出现灰色建议，`Alt+l` 接受 |
| `vim` 与 `nvim` 一致 | `readlink -f $(which vim) $(which nvim)` | 两行输出相同 |
| 默认浏览器 | `xdg-settings get default-web-browser` | `firefox.desktop` |
| 字体生效 | `fc-match monospace` | `Sarasa Mono J` |
| Ctrl+Enter 发送 | 重启 VSCode，在 Claude Code 面板按 Enter | 换行而非发送；`Ctrl+Enter` 才发送 |
| 聊天字号 | 肉眼 | Claude Code 与 Copilot Chat 正文都变大 |

---

## 八、后续注意事项

### ⚠️ 不要做的事

1. **不要把 `programs.neovim` 加回 `modules/development.nix`。**
   会重新产生两个 neovim，`vim` / `vi` 又会指向不带 `extraPackages` 的那个，
   Copilot 在它下面必然离线，而用 `nvim` 打开又完全正常——这种「看人下菜」的
   故障极难排查。文件里已留了警示注释。

2. **不要把 `copilot-cmp` 加回来。**
   它与 `suggestion` / `panel` 模块互斥，且在 Neovim 0.11+ 上使用已废弃 API。
   想让 Copilot 回到补全菜单，走 `blink.cmp` + `blink-copilot`。

3. **不要把 `panel.keymap.open` 改回 `<M-CR>`。**
   在 GUI（Neovide）里极易误触，代价是整个编辑器「假死」。

4. **不要在 `modules/common.nix` 里再加 `fonts.*`。**
   字体统一在 `modules/localization.nix`。

### ✅ 需要记住的排查经验

1. **home-manager 激活失败会留下「半成功」状态，必须单独确认。**
   `nixos-rebuild switch` 里系统层和 home 层是两个阶段：系统层先生效，
   然后才重启 `home-manager-toru.service`。后者失败时前者**已经切过去了**，
   所以「命令报错了」不等于「什么都没变」。看到
   `warning: the following units failed: home-manager-toru.service` 时，
   用这两条确认 home 层到底有没有生效：

   ```bash
   ls -la ~/.config/nvim/init.lua     # symlink 指向哪个 home-manager-files hash
   systemctl status home-manager-toru.service
   ```

   已用 `home-manager.backupFileExtension` 从根上避免了最常见的那种失败
   （文件冲突），但其它原因（比如选项求值出错）仍可能失败。

2. **`fontconfig` 对错误的字体族名完全静默。**
   任何时候写了新的字体名，先跑一次验证：

   ```bash
   fc-match "你写的族名"
   ```

   如果返回的不是你指定的字体，那这行配置就是空转的。
   这个坑已经踩过两次了（`4062d2b` 和这次）。

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

   ```bash
   nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res
   ls /tmp/res/sw/bin/        # 看系统装了什么
   nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage --out-link /tmp/hm
   cat /tmp/hm/home-files/.config/mimeapps.list    # 看 HM 生成了什么
   ```

### 📌 遗留 / 可选项

1. **VSCode 设置不在版本控制内**（见第二节）。若要纳入，需改用
   `programs.vscode.profiles.default.userSettings`，但会让 HM 接管整个
   `settings.json`，VSCode 自己写入的键会被覆盖。

2. **字体目前是日语优先（J / JP 变体）**。如果中文字形看起来别扭，
   把 `modules/localization.nix` 里的 `J` → `SC`、`JP` → `SC` 即可。

3. **`modules/browsers.nix` 的浏览器装在系统级，Firefox 装在 home-manager 级。**
   不影响功能，但位置不一致。哪天想统一，可以把 Zen / Brave 也挪到
   `home/toru.nix`，或把 Firefox 挪到 `browsers.nix`（后者要放弃
   `programs.firefox.policies` 这种 HM 写法）。

4. **`home/toru.nix` 里的 `baseExtensionPolicies` 只被引用了一次。**
   名字叫 "base" 暗示它本来打算被多处复用/扩展，目前并没有。
   如果将来不打算给 Zen 之类复用，可以直接内联掉。

---

## 九、相关文档

- [Lesson-Learn/NEOVIM_GUIDE.md](Lesson-Learn/NEOVIM_GUIDE.md) —— Copilot 用法已按本次改动更新
- [Lesson-Learn/COPILOT_OFFLINE_FIX.md](Lesson-Learn/COPILOT_OFFLINE_FIX.md) —— ⛔ 已过时，方案被本次撤销
- [Lesson-Learn/COPILOT_STARTUP_ISSUES.md](Lesson-Learn/COPILOT_STARTUP_ISSUES.md) —— ⛔ 第 3 节已作废
- [Lesson-Learn/COPILOT_UNZIP_DEPENDENCY.md](Lesson-Learn/COPILOT_UNZIP_DEPENDENCY.md) —— `unzip` 依赖，仍然有效
- [Lesson-Learn/SARASA_MONO_FONT_ISSUE.md](Lesson-Learn/SARASA_MONO_FONT_ISSUE.md) —— 与本次字体族名问题同源，建议对照阅读
- [Lesson-Learn/LAZY_NVIM_DASHBOARD.md](Lesson-Learn/LAZY_NVIM_DASHBOARD.md) —— Lazy.nvim 仪表板

# NixOS 配置审计：重复声明、无效字体名与默认浏览器

> 日期：2026-09-17　|　相关提交：`8fef4d0`
>
> 这批问题是排查 Copilot 故障（见
> [0009_COPILOT_GHOST_TEXT_MIGRATION.md](0009_COPILOT_GHOST_TEXT_MIGRATION.md)）时
> 对全部 nix 文件做静态分析顺带发现的。它们都**不会导致构建失败**，
> 所以能长期潜伏 —— 这正是它们值得单独记录的原因。

## 发现的问题

### 问题 1：`nvim` 和 `vim` 是两个不同的 neovim（潜在雷）

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
`0008_COPILOT_OFFLINE_FIX.md` 当初想解决的症状——但当时找错了方向，
去 init.lua 里加 `vim.g.copilot_node_command`（一个 copilot.lua 根本不读的变量），
而真正的原因在 nix 层。

### 问题 2：fontconfig 里 5 个字体族名全部无效

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

### 问题 3：从来没人声明过默认浏览器

```
$ xdg-settings get default-web-browser
org.gnome.Epiphany.desktop
```

仓库里装了 Firefox（`home/toru.nix`）、Zen、Brave（`modules/browsers.nix`），
但没有任何模块声明默认浏览器，于是 GNOME 自己挑了 Epiphany（GNOME Web）。
从终端或其它应用点链接都会跳到 Epiphany。


## 已实施的修复

### 修复 1：统一 neovim 声明

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

### 修复 2：字体声明收拢 + 修正族名

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

### 修复 3：默认浏览器设为 Firefox

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

### 修复 4：清理未使用的模块参数

8 处：`config` 从 apps / browsers / desktop / flatpak / development / common /
localization / hosts-thinkpad 中移除，`inputs` 和 `config` 从 home/toru.nix 移除，
`pkgs` 从 desktop / flatpak 移除（这两个文件确实没用到 pkgs）。

### 修复 5（仓库外）：VSCode 设置

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


## 为什么这样解决

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


## 后续注意事项

### ⚠️ 不要做的事

1. **不要把 `programs.neovim` 加回 `modules/development.nix`。**
   会重新产生两个 neovim，`vim` / `vi` 又会指向不带 `extraPackages` 的那个，
   Copilot 在它下面必然离线，而用 `nvim` 打开又完全正常——这种「看人下菜」的
   故障极难排查。文件里已留了警示注释。

2. **不要在 `modules/common.nix` 里再加 `fonts.*`。**
   字体统一在 `modules/localization.nix`。

### ✅ 需要记住的排查经验

2. **`fontconfig` 对错误的字体族名完全静默。**
   任何时候写了新的字体名，先跑一次验证：

   ```bash
   fc-match "你写的族名"
   ```

   如果返回的不是你指定的字体，那这行配置就是空转的。
   这个坑已经踩过两次了（`4062d2b` 和这次）。

2. **`nix build` 比 `nixos-rebuild switch` 更适合验证。**
   不需要 sudo，不改系统状态，并且可以直接检查产物：

   ```bash
   nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res
   ls /tmp/res/sw/bin/        # 看系统装了什么
   nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage --out-link /tmp/hm
   cat /tmp/hm/home-files/.config/mimeapps.list    # 看 HM 生成了什么
   ```


### 📌 遗留 / 可选项

1. **VSCode 设置不在版本控制内**（见「修复 5」）。若要纳入，需改用
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

## 相关文档

- [0009_COPILOT_GHOST_TEXT_MIGRATION.md](0009_COPILOT_GHOST_TEXT_MIGRATION.md) —— 本次审计的起因
- [000B_HOME_MANAGER_ACTIVATION_CONFLICT.md](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md) —— 默认浏览器改动导致的激活失败
- [0004_SARASA_MONO_FONT_ISSUE.md](0004_SARASA_MONO_FONT_ISSUE.md) —— 同类字体名错误的第一次发生
- [0002_NEOVIM_PLUGIN_AND_FONT_FIX.md](0002_NEOVIM_PLUGIN_AND_FONT_FIX.md) —— 字体配置的最早版本

# 笔电调优与「AI 也能用」的 shell 环境

> 日期：2026-09-17　|　相关配置：`hosts/thinkpad/tuning.nix`、`modules/shell.nix`、`modules/common.nix`、`home/toru.nix`
>
> 触发场景：拿当前配置和 Omarchy 4 "Quattro" 做了一次横向对比，
> 挑出两块投入产出比最高的补齐项先做 —— 笔电硬件调优和 CLI 环境。

## 问题症状

不是「坏了」，是「一直缺着」：

1. 7.6 GiB 内存的 Skylake 机器没有 zram，内存一紧张就直接换到 NVMe。
2. `hardware.graphics.enable` 是 `true`，但 `extraPackages` 是**空的** ——
   等于一个 VAAPI 驱动都没装，浏览器和 mpv 放视频全走 CPU 软解。
   这种「开了但没配全」的状态不会报任何错。
3. 仓库里**没有任何 shell 声明**，登录 shell 是裸 bash，
   没有提示符、没有补全插件、没有 fzf / zoxide / direnv。

## 根本原因分析

### 一、三个「以为要加、其实早就开着」的选项

动手前逐个 `nix eval` 查了默认值，结果推翻了原计划：

| 选项 | 当前值 | 结论 |
|------|--------|------|
| `systemd.oomd.enable` | `true` | NixOS 默认就开，不用加 |
| `services.power-profiles-daemon.enable` | `true` | GNOME 模块已拉起 |
| `services.fstrim.enable` | `true` | NixOS 默认就开，NVMe TRIM 在跑 |

**教训：在 NixOS 上加任何服务之前先 `nix eval` 查当前值。**
很多东西 `services.xserver.desktopManager.gnome` 这类高层模块已经替你开了，
重复声明不会报错，只会在配置里留下一堆看不出真假的噪音。

而且 `services.tlp.enable` **不能**加 —— TLP 和 power-profiles-daemon
抢同一批 sysfs 旋钮，NixOS 会直接抛断言失败。

### 二、指纹传感器：不是「一行配置」，是不支持

`lsusb` 查出来是 **Validity Sensors VFS7500，USB ID `138a:0090`**。

上游 libfprint **不支持这颗**。它是 match-on-host 传感器，要用得上
社区的 out-of-tree TOD 驱动（`3v1n0/libfprint-tod-vfs0090`），
而且驱动跑起来之前必须先用 `validity-sensors-tools`
（或者一个 Windows 环境）把传感器固件初始化过一次。

所以 `services.fprintd.enable = true` 加了也白加：fprintd 会起来，
但 `fprintd-enroll` 找不到任何设备。这次**没有**启用它。

**教训：ThinkPad 有指纹槽 ≠ 这颗指纹在 Linux 上能用。**
先 `lsusb` 拿到 USB ID，再去查 libfprint 的支持列表。

### 三、AI 跑的是非交互 shell，`.zshrc` 根本不会被 source

这次配 shell 的最大约束不是「好不好看」，而是
**这台机器上的 shell 经常被 AI 编码助手拿去跑命令**。

关键事实：

- `bash -c 'cmd'` 是**非交互非登录** shell，`~/.bashrc` 不读，`/etc/bashrc` 也不读。
- `zsh -c 'cmd'` 是非交互 shell，`~/.zshrc` 不读，但 **`~/.zshenv` 和 `/etc/zshenv` 会读**。
- 所以 **alias 对 AI 完全不存在**。`ll` 在你终端里好好的，AI 那边就是 command not found。

更隐蔽的一个坑：home-manager 的 `programs.eza` 默认会写
`alias ls='eza'`。于是你在终端里看到的是 eza 的彩色分栏，
AI 看到的是 coreutils `ls` 的原始输出 —— **同一条命令两份结果**。
排查问题时这会让人和 AI 互相误导，而且一旦 alias 漏进脚本，
输出格式变了，解析全错。

## 已实施的修复

### `hosts/thinkpad/tuning.nix`（新增）

```nix
zramSwap.enable = true;                    # 默认 50% / zstd / priority 5
boot.kernel.sysctl = {
  "vm.swappiness" = 100;                   # 不是社区常见的 180，理由见下
  "vm.page-cluster" = 0;
};
services.thermald.enable = true;           # Intel DPTF 主动控温
# services.fwupd.enable 不在这里 —— 已上移到 modules/common.nix（见下）
hardware.graphics.extraPackages = [ intel-media-driver intel-vaapi-driver ];
environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
```

### 分层：`modules/` 与 `hosts/` 的分界

这套配置以后要上更强的笔记本和台式机，所以上面这些**一条都不能放 `modules/`**：

| 条目 | 为什么绑本机 |
|------|--------------|
| `intel-media-driver` | AMD / NVIDIA 机器装它纯属浪费，还可能选错驱动 |
| `vm.swappiness = 100` | 是按「7.6 GiB 内存 + 有磁盘 swap 兜底」算出来的 |
| `services.thermald` | Intel 专用，读的是 DPTF/ACPI |

判据一句话：**换一台机器还成立的放 `modules/`，只对这台成立的放 `hosts/<主机>/`。**

按这个判据还顺手挪了两处：

- `services.fwupd.enable` **上移**到 `modules/common.nix` ——
  任何带 UEFI 的机器都该开，放本机文件里等于逼下一台机器再抄一遍。
- `users.users.toru.shell = pkgs.zsh` 从 `modules/shell.nix` **下移**到
  `hosts/thinkpad/default.nix`。共用模块里出现具体用户名，
  等于把模块钉死在这个用户上。拆成两半才对：
  `programs.zsh.enable`（zsh 本体，通用）留模块，
  「哪个用户用它」的指派回到声明该用户的地方。

`hosts/thinkpad/default.nix` 的 `imports` 也改成「本机专属在前、
共用模块在后」两组，加新机器时照抄骨架即可。

### `modules/shell.nix`（新增，只放必须在系统层的部分）

```nix
programs.zsh.enable = true;                # 登记 /etc/shells + 生成 /etc/zshrc + compinit
# 注意：这里**不写** users.users.<名字>.shell，见下面「分层」一节
environment.sessionVariables = {           # 注意是 sessionVariables 不是 variables
  PAGER = "less -FRX";
  LESS = "-FRX";
};
```

### `home/toru.nix`（新增「Shell 环境」一节）

zsh（autosuggestion / syntaxHighlighting / historySubstringSearch / 10 万条历史）、
bash（配成同一套基线）、starship、direnv + nix-direnv、fzf、zoxide、
eza、bat、btop、lazygit、tmux，外加 `dua` / `duf`。

## 为什么这样解决

### swappiness 取 100 而不是 180

社区常见的 `vm.swappiness = 180` 有个前提：**zram 是唯一的 swap**。
本机背后还挂着一个 8.8 GiB 的磁盘 swap 分区（priority `-1`，
zram 是 `5`，所以内核先用 zram、压满了才落到 NVMe）。
在有磁盘兜底的情况下把 swappiness 拉到 180，
zram 一压满就会把压力整个甩给 NVMe，反而更卡。100 是个折中。

`vm.page-cluster = 0` 则没有折中余地：预读页数对磁盘 swap 是摊薄寻道成本，
对 zram 纯属浪费 —— 没有寻道可言，每多读一页就多解压一次。

### 三条 AI 友好的硬规则

1. **工具必须是 PATH 上的真二进制，不能靠 alias。**
   全部走 `programs.*`，落到 `/etc/profiles/per-user/toru/bin`，
   这个路径在 `/etc/pam/environment` 的 `PATH` 里，
   任何 shell、任何模式下都找得到。

2. **绝不用 alias 遮蔽 `ls` / `cat` / `grep` / `find`。**
   显式关掉 `programs.eza` 的 shell integration
   （`enableZshIntegration = false; enableBashIntegration = false;`），
   另起 `ll` / `la` / `lt` 这些不冲突的名字。
   同理 `programs.zoxide` **不加** `options = [ "--cmd cd" ]` ——
   那会把 `cd` 换成模糊跳转，脚本里的 `cd ../foo` 就不再是标准语义了。

3. **bash 和 zsh 配成同一套基线。** starship / direnv / fzf / zoxide
   全部 `enableBashIntegration` 和 `enableZshIntegration` 双开，
   别名两边共用同一份 `commonAliases`。
   AI 用哪个 shell 结果都一样。

### `PAGER` 用 `sessionVariables` 而不是 `variables`

- `environment.variables` → `/etc/set-environment`，要靠 shell 去 source。
- `environment.sessionVariables` → `/etc/pam/environment`，**会话级**，
  任何进程任何 shell 都继承。

`less -FRX` 里 `-F` 是关键：内容不足一屏就直接输出并退出，
**不会卡在分页器里等输入** —— 这是自动化跑 shell 时最常见的一种假死。
`FRX` 也正是 git 在 `LESS` 未设置时自己用的默认值，所以不改变 git 现有行为。

### `dotDir` 显式按回家目录

`home.stateVersion` 是 `"26.05"`，新版 home-manager 的
`programs.zsh.dotDir` 默认值已经变成 `~/.config/zsh`。
这里显式写回 `config.home.homeDirectory`：
`~/.zshrc` 是所有外部工具（包括 AI 助手）默认会去找的位置，
换成 XDG 路径要靠 `ZDOTDIR` 转接，多一层可能出错的环节，不值得。

### `enableCompletion = false`（home 层）

系统层 `programs.zsh.enable` 已经在 `/etc/zshrc` 里跑过一次 `compinit`，
而 `/etc/zshrc` 在 `~/.zshrc` **之前**被 source。
home 层再跑一次的话，每开一个终端都要多花几百毫秒重建补全缓存。

## 后续注意事项

- **首次 `nixos-rebuild switch` 之后要重新登录**，登录 shell 才会变成 zsh。
  当前那个终端还是 bash，`echo $SHELL` 看到的也还是旧值。
- home-manager 要接管 `~/.bashrc`。已存在的那份会被改名成 `~/.bashrc.hm-bak`，
  不会中断激活 —— 靠的是 `backupFileExtension`，见 [000B](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md)。
- **VAAPI 要实机验证**：`nix shell nixpkgs#libva-utils -c vainfo`，
  应当看到 `iHD` 字样和一串 `VAProfile` 列表，而不是 `no driver`。
  和字体一样，这里配错了不会报错，只会静默退回软解。
- **zram 要实机验证**：`swapon --show` 应当出现 `/dev/zram0`，`PRIO` 为 `5`，
  磁盘分区的 `PRIO` 是 `-1`。
- **没开 eza 的 `icons`**：本机装的是 Sarasa Mono J，不是 Nerd Font，
  开了只会得到一片豆腐块。想要图标得先补一个 Nerd Font
  （Neovim 的 `nvim-web-devicons` 和 lualine 其实也在等这个）。
- **没有加 `programs.git`（home 层）**：`git` 已经在 `modules/common.nix` 的
  `systemPackages` 里，而且 root 跑 `nixos-rebuild --flake` 时需要它，
  必须留在系统层。在 home 层再声明一次就是 CLAUDE.md 里的坑 3。
  因此 `delta` 之类依赖 git 配置的工具这次也没加。
- **新建的 `.nix` 文件必须先 `git add`**，否则 flake 看不见它，
  `nix build` 会报 `Path 'hosts/thinkpad/tuning.nix' ... is not tracked by Git`。

## 相关文档

- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— 系统层 / home 层重复声明的历史教训
- [000B_HOME_MANAGER_ACTIVATION_CONFLICT.md](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md) —— `backupFileExtension` 为什么存在
- [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md) —— Neovim 里的 Claude Code 集成

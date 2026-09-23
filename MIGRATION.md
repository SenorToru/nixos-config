# 在一台全新机器上重建这套 NixOS

从插上 U 盘开始，到新机器和现在这台**用起来一样**为止。

> 本文件和另外三份的分工：
>
> | 文件 | 管什么 |
> |------|--------|
> | [README.md](README.md) | 日常操作手册：改完配置怎么重建、怎么清理 generation |
> | [CLAUDE.md](CLAUDE.md) | AI 协作约定：什么放 `modules/`、什么放 `hosts/` |
> | [Lesson-Learn/](Lesson-Learn/README.md) | 踩过的坑和排查过程 |
> | **本文件** | **一次性的事：装新机器、搬 Nix 管不到的状态** |

---

## 本文档的完成度

这份指南分三批落地，当前状态：

| 批次 | 内容 | 状态 |
|------|------|------|
| 一 | 本文档 | 已完成 |
| 二 | rEFInd 主题 derivation、`refind-sync`、`refind-hwinfo`、在 thinkpad 上实装验证 | **已完成** |
| 三 | A 类配置补全、`migration-check`、`state-sync`、README/CLAUDE.md 同步 | **已完成** |

**第 1-5 节已在虚拟机里完整跑通**（2026-09-21，Bluefin 上的 libvirt/KVM）。
装完能进 GNOME，A 类复现逐条验证过：字体命中 `Sarasa Mono J` 不回退、
登录 shell 是 zsh、`claude --version` 和 manifest 钉的版本一致、
25 个 Agent Skill 全在。演练清单和沿途发现见
[REHEARSAL.md](REHEARSAL.md)。

**第 6 节（rEFInd）在 thinkpad 上验过**，连重启看菜单、图标、分辨率都做了，
踩的五个坑记在 [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。
但**在全新安装的语境下还没走过** —— 虚拟机演练的下一步就是它。

**第 7 节（搬用户状态）在 thinkpad 上验过**，`dotfiles-state` 私有仓库
已经建好并推上 GitHub。

三件虚拟机验证不了的，真机上还得重走：GOP 分辨率（OVMF 的模式和真机
固件无关）、NTFS 脏状态（没有真 Windows 去弄脏它）、硬件探测的值。

---

## 0. 先分清：什么能复现，什么不能

**这是整件事的地基。** 仓库能复现的部分和不能复现的部分，处理方式完全不同，
混在一起想只会浪费时间。

### A 类 —— 仓库负责，字节级复现

`nixos-rebuild switch` 一下就和这台一致，全部由 `flake.lock` 锁死：

系统与桌面、GNOME 扩展、20 套 stylix 主题、字体、
fcitx5 的插件组合（白霜拼音含那个 lua 补丁、mozc-ut 的 8 套词典）、
neovim 配置、VS Code 的 `userSettings`、25 个 Agent Skill、zsh/tmux/starship
那一整套交互环境。

**这一类不需要你做任何事**，跑一遍构建就有了。

### B 类 —— 仓库管不到，但可以版本化

`$HOME` 里的用户状态。不在版本库里，所以**一个都不会自动跟过去**。
解决办法是一个**独立的私有仓库** `dotfiles-state`（见第 7 节）：

| 路径 | 内容 |
|------|------|
| `~/.config/fcitx5/profile` | 启用了哪些输入法、顺序 |
| `~/.config/fcitx5/config` | 全局快捷键 |
| `~/.config/fcitx5/conf/` | 各插件的设置 |
| `~/.config/mozc/` | Mozc 学习历史（**整个目录**，含 `.encrypt_key.db`） |
| `~/.local/state/theme/current` | 当前选的是 20 套主题里哪套 |
| `~/.local/state/agent-skills/disabled` | 关掉了哪些 Agent Skill |
| `~/.config/monitors.xml` | 多显示器布局（台式机上有用） |
| `~/.config/user-dirs.dirs` | XDG 目录指向 |
| `~/.claude/settings.json` | Claude Code 的模型 / effort / 主题偏好。**归 B 类是因为工具在运行时写它** |

### C 类 —— 不搬，新机器重新签发

秘密。**刻意不做迁移**，因为密钥本来就该一机一把 —— 泄露时能单独吊销，
而不是一把钥匙开所有门。

| 东西 | 新机器上怎么办 |
|------|----------------|
| `~/.ssh/id_ed25519` | 新生成一把。公钥在 GitHub 登记**两次**（认证 + 签名），再加进 `home/toru.nix` 的 `signingKeys` |
| `~/.gnupg/` | 需要时新生成 |
| `~/.config/gh/` | `gh auth login` |
| `~/.claude.json`、`~/.claude/` 里的凭据 | `claude` 首次启动时登录。**但 `~/.claude/projects/` 下的会话记录要搬**，那不是凭据，见 7.5 |
| `~/.grok/` 里的凭据（Grok Build） | `grok login`。`~/.grok/` 里其余东西（`config.toml`、会话、memory）怎么分类，见文末「还没解决的问题」 |
| `~/.config/.wrangler/`（Cloudflare 的 OAuth 令牌） | 在用到的项目目录里 `pnpm exec wrangler login`。wrangler 是项目的 devDependency，不是全局命令 |
| GNOME keyring（`~/.local/share/keyrings/`） | 重新解锁各服务 |
| WiFi 密码 | 重新输 |
| 浏览器 cookie / 登录态 | 靠浏览器自己的账号同步 |

具体清单见第 7.3 节。

### 不属于任何一类的三样东西

| 路径 | 为什么 |
|------|--------|
| `~/.local/share/fcitx5/rime/*.userdb/` | LevelDB，**没法合并**。用 Rime 内建同步，见 7.2 |
| `~/.local/share/fcitx5/rime/build/` | **绝对不要拷**，里面固化着旧机器的 store 路径 |
| `~/.local/share/fcitx5/rime/installation.yaml` | **绝对不要拷**，里面的 UUID 是 Rime 同步的分机标识 |

---

## 1. 动手前的决策清单

装机过程中有四个地方会分叉。**先把这四个想清楚再开始**，中途改主意
基本等于重来一遍。

### 决策点 A：用哪个 ISO

| | Graphical（GNOME） | Minimal |
|---|---|---|
| 大小 | 约 3 GB | 约 1 GB |
| 联网 | GNOME 点两下 | `nmtui` 或 `wpa_supplicant` 手敲 |
| 看这份文档 | 能在同一台机器上开 Firefox 对照 | 得用手机或另一台机器 |
| 分区时目视确认 | 有 GParted | 只有 `lsblk` |
| 老机器 / 内存小 | 吃内存 | 更稳 |

**两个 ISO 的安装步骤完全一样**（第 4 节起），区别只在第 3 节怎么联网、
怎么开终端。

> **不要用图形安装器（Calamares）。**
> 它划不出我们要的 Btrfs subvolume 布局、处理不了多盘多 ESP、
> 也不会给 rEFInd 留位置，而且会生成一份自己的 `configuration.nix`
> 和这个 flake 仓库对不上。装完还得重分重装。
> **Graphical ISO 的价值在于它提供的 GNOME 环境，不在于它的安装器。**

### 决策点 B：磁盘拓扑

| 场景 | 做法 |
|------|------|
| 单盘，整机给 NixOS | 一个 2 GiB ESP + 一个 Btrfs 分区。rEFInd 也装进这个 ESP |
| 多盘，NixOS 独占一块 | 同上，其余盘按用途格式化 |
| 多盘，NixOS + Windows 各占一块 | **各自独立 ESP**，两个 ESP 各装一份 rEFInd，见 6.4 |
| 多盘，其中一块做 Win/Linux 共享 | 那块格 NTFS，见 4.3 |

### 决策点 C：Btrfs 压缩等级

挂载选项写成 `compress=zstd:1` 还是 `zstd:3`。

> ### 这个值不会被 `nixos-generate-config` 记录
>
> 那个脚本只往生成的文件里写四样：loop 设备的 `loop`、btrfs 的
> `subvol=`、vfat 的 `fmask` / `dmask`、以及 stratis 相关的几项
> （源码见 `nixos/modules/installer/tools/nixos-generate-config.pl`）。
> **`compress`、`noatime`、`discard` 一律不记。**
>
> 所以安装时挂载用什么压缩等级，**只影响安装过程本身**。
> 要让它持久生效，必须写进 `hosts/<机>/tuning.nix`，见第 5.2 节。
>
> 这也正好符合仓库的分层判据 —— 压缩等级是按这台机器的 CPU 定的调优，
> 本来就该在 `tuning.nix`。而 `fileSystems.*.options` 是列表，
> 多个模块的定义会**合并**：`hardware-configuration.nix` 出 `subvol=`，
> `tuning.nix` 出 `compress` 和 `noatime`，两边各管各的，
> 谁都不用去改对方。

| 选 | 什么时候 |
|----|----------|
| `zstd:1` | CPU 较弱（移动端 U、老平台）、盘够大。**ThinkPad X1 Yoga 这类选这个** |
| `zstd:3` | CPU 有富余（新一代桌面 / HX 系列）、盘偏小想多换点空间 |

判据是「压缩的 CPU 开销 vs 省下的 IO」。`zstd:1` 几乎不占 CPU 且已经
能压掉 `/nix/store` 相当可观的一块；`zstd:3` 多压不了太多，但 CPU 开销明显上升。
**拿不准就选 `zstd:1`。**

### 决策点 D：swap 怎么给

仓库里 `zramSwap.enable` 在 `hosts/<机>/tuning.nix`，是**内存里的压缩 swap**，
和磁盘 swap 是互补关系（zram 优先级高，压满了才落盘）。磁盘那一份：

| 做法 | 说明 |
|------|------|
| **独立 swap 分区**（推荐） | 最简单。在 ESP 和 Btrfs 之间切一块，大小取内存的 1-1.5 倍 |
| Btrfs 上的 swapfile | 要单独建一个 subvolume 并设 `nodatacow`，**不能压缩、不能被快照**。约束多 |
| 不给磁盘 swap，只用 zram | 内存充裕（32 GiB 以上）的机器可以。但没有休眠能力 |

本文档第 4 节按**独立 swap 分区**写。

### 决策点 E：主机名

`hosts/<主机名>/` 的目录名、`networking.hostName`、
`flake.nix` 里 `nixosConfigurations` 的条目名，三处要一致。
现有的是 `thinkpad` / `thinkpad-nixos`。

---

## 2. 准备安装介质

在**现在这台机器**上做。

```bash
# 1. 下载。两个 ISO 的地址在 https://nixos.org/download/
#    Graphical: nixos-gnome-<版本>-x86_64-linux.iso
#    Minimal:   nixos-minimal-<版本>-x86_64-linux.iso

# 2. 校验（别跳过，下载损坏在装到一半时才暴露最难受）
sha256sum nixos-*.iso
# 和下载页上的 SHA-256 比对

# 3. 确认 U 盘是哪个设备。写错设备 = 抹掉一块硬盘
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT

# 4. 写盘。确认 /dev/sdX 是 U 盘本身而不是分区（不带数字）
sudo dd if=nixos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

> ISO 版本尽量和 `flake.nix` 里的 `nixpkgs` 对齐（当前是 `nixos-26.05`）。
> 不一致也能装，只是 ISO 里的工具链和目标系统版本不同，
> 遇到问题时多一个变量。

---

## 3. 从 ISO 启动并联网

先在固件设置里确认两件事：**UEFI 模式**（不是 Legacy/CSM）、
**Secure Boot 关闭**（NixOS 默认不签名，rEFInd 也不签名）。

### 3.1 Graphical ISO

1. 进 GNOME 桌面（自动登录为 `nixos` 用户）。
2. 右上角状态菜单连 WiFi。
3. 打开 **Console**（GNOME 自带终端）。
4. 后续所有命令都要 root：`sudo -i`

### 3.2 Minimal ISO

落到一个 root shell（用户 `nixos`，已有 sudo 免密）。

```bash
sudo -i

# 有线：通常插上就有 IP，确认一下
ip -brief addr

# WiFi：用 nmtui 交互连
nmtui

# 或者命令行连
nmcli device wifi list
nmcli device wifi connect "<SSID>" password "<密码>"
```

验证：

```bash
ping -c3 nixos.org
```

> **Minimal ISO 上没有 `git`。** 第 5 节要用，届时
> `nix-shell -p git` 临时取一个即可（ISO 上 nix 是可用的）。

---

## 4. 分区与格式化

> **所有命令都要 root。** 新开的终端或 SSH 会话先 `sudo -i`。
> 第 3 节提过一次，但那是假设你从头一路做下来 ——
> **SSH 断线重连、或者换一个终端窗口，都会回到普通用户。**
>
> **这一节的每条命令都会不可逆地抹掉数据。**
> 每次动手前先跑一遍 `lsblk -o NAME,SIZE,MODEL,SERIAL`，
> 靠**型号和序列号**确认目标盘，不要靠 `/dev/nvme0n1` 这种会变的名字。

下面以 `/dev/nvme0n1` 为例。**把它换成你确认过的那块盘。**

### 4.1 分区表与分区

```bash
parted /dev/nvme0n1 -- mklabel gpt

# 三个分区的起止位置是**连锁**的：后一个的起点 = 前一个的终点。
# 所以用变量推，不要手写死数字 —— 改了 swap 大小却忘了改 root 的起点，
# parted 不会报错，只会在中间留一段白白浪费的空隙。
ESP_END=2      # GiB。比常见的 512 MiB 大得多是有理由的：每换一次内核，
               # systemd-boot 就要在这里多存一份约 50-60 MiB 的
               # kernel + initrd。1 GiB 的 ESP 撑不住几轮。
SWAP_SIZE=16   # GiB。按决策点 D，取内存的 1-1.5 倍。
SWAP_END=$((ESP_END + SWAP_SIZE))

parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB "${ESP_END}GiB"
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart swap linux-swap "${ESP_END}GiB" "${SWAP_END}GiB"
parted /dev/nvme0n1 -- mkpart root btrfs "${SWAP_END}GiB" 100%

# 不要磁盘 swap 的话，跳过 swap 那行，并把 root 的起点改成 "${ESP_END}GiB"
```

### 4.2 格式化

```bash
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkswap -L swap /dev/nvme0n1p2
mkfs.btrfs -L nixos /dev/nvme0n1p3
```

### 4.3 分支：NTFS 共享盘（3 块盘以上时）

给 Windows 和 NixOS 共用的那块：

```bash
# 整盘一个分区
parted /dev/sdX -- mklabel gpt
parted /dev/sdX -- mkpart share ntfs 1MiB 100%
mkfs.ntfs -Q -L share /dev/sdX1
```

> **装好之后必须去 Windows 里关掉两个东西，否则这块盘迟早会出事：**
>
> 1. **快速启动**（控制面板 → 电源选项 → 选择电源按钮的功能 →
>    更改当前不可用的设置 → 取消「启用快速启动」）
> 2. **休眠**（管理员 PowerShell 跑 `powercfg /h off`）
>
> 这两个功能会让 Windows 关机时**不真正卸载文件系统**，NTFS 留在「脏」状态。
> Linux 侧此时要么只读挂载，要么强行写入导致损坏。
> 这是 NTFS 共享盘最常见的翻车方式，和用哪个驱动无关。

NixOS 侧的挂载配置在第 5.2 节写进 `hosts/<主机>/`。

### 4.4 挂载

这里挂载用的选项**只影响安装过程本身**。
`nixos-generate-config` 只记 `subvol=`（btrfs）和 `fmask`/`dmask`（vfat），
**`compress` 和 `noatime` 不记** —— 那两样要写进 `hosts/<机>/tuning.nix`，
见第 5.2 节。

```bash
# 先建 subvolume
mount /dev/nvme0n1p3 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@snapshots
umount /mnt
```

```bash
# 安装期间的挂载选项。压缩等级在这里只影响安装过程 ——
# 装完之后生效的那一份在 hosts/<机>/tuning.nix（第 5.2 节）。
OPTS=compress=zstd:1,noatime

mount -o subvol=@,$OPTS          /dev/nvme0n1p3 /mnt
mkdir -p /mnt/{home,nix,.snapshots,boot}
mount -o subvol=@home,$OPTS      /dev/nvme0n1p3 /mnt/home
mount -o subvol=@nix,$OPTS       /dev/nvme0n1p3 /mnt/nix
mount -o subvol=@snapshots,$OPTS /dev/nvme0n1p3 /mnt/.snapshots

# ESP。umask=0077 会让生成器写出 fmask/dmask=0077，
# 和现有 hosts/thinkpad/hardware-configuration.nix 一致。
mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot

swapon /dev/nvme0n1p2
```

确认一遍：

```bash
findmnt -R /mnt
```

四个 subvolume 都在、`/mnt/boot` 是 vfat、选项里有 `compress=zstd:N`
才继续。

> **`@snapshots` 现在是空的，不影响任何事。**
> 它只是一个占位，将来真要用 snapper / btrbk 时不用重装。
> Btrfs 的 subvolume 随时能加，不像分区那样是死的 ——
> 所以这里多建一个的成本接近零。

---

## 5. 安装 NixOS

### 5.1 生成 hardware-configuration.nix

```bash
nixos-generate-config --root /mnt
```

生成两个文件，**只用其中一个**：

| 文件 | 怎么处理 |
|------|----------|
| `/mnt/etc/nixos/hardware-configuration.nix` | **要**。下一步拷进仓库 |
| `/mnt/etc/nixos/configuration.nix` | **不要**。仓库的 `hosts/<主机>/default.nix` 取代了它 |

先看一眼生成对了没有：

```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```

`fileSystems."/"` 的 `options` 里应该有 `subvol=@`、`compress=zstd:N`、`noatime`。
**没有的话说明第 4.4 步挂载选项写漏了** —— 回去重挂，重新生成。

### 5.2 把仓库接进来

```bash
# 用 https，因为这台机器还没有 SSH key（C 类：秘密不搬）
nix-shell -p git --run '
  git clone https://github.com/SenorToru/nixos-config /mnt/home/toru/nixos-config
'
cd /mnt/home/toru/nixos-config

HOST=<新主机名>          # 例如 desktop、asus、vm
mkdir -p hosts/$HOST
cp /mnt/etc/nixos/hardware-configuration.nix hosts/$HOST/
```

> ISO 里全程是 root，所以这些文件的属主都是 root。
> **第 5.5 节的 `chown` 会一次性修掉**，别提前做 ——
> `nixos-install` 读 dirty 工作树时还可能往 `.git/objects` 里写东西。
> 背景见 [Lesson-Learn/0011](Lesson-Learn/0011_ROOT_OWNED_FILES_IN_REPO.md)。

#### 先定键盘布局

**`console.keyMap`（TTY）和 `services.xserver.xkb.layout`（图形界面）
用的是两套命名**，不能想当然地填成一样：

| 键盘 | `console.keyMap` | `xkb.layout` | 一样吗 |
|------|------------------|--------------|--------|
| 美式 | `us` | `us` | 是 |
| **日语 JIS** | **`jp106`** | **`jp`** | **否** |
| 英式 | `uk` | `gb` | **否** |
| 德语 | `de` | `de` | 是 |
| 法语 | `fr` | `fr` | 是 |

写错了 `console.keyMap` **不会报错**，只是 TTY 下按键映射不对 ——
而平时都在图形界面里，只有真出事掉进 TTY 时才发现。

自己查一遍：

```bash
ls $(nix eval --raw nixpkgs#kbd)/share/keymaps/**/*.map.gz | xargs -n1 basename
```

#### `hosts/<主机>/tuning.nix`

**必须按新硬件重写，不能照抄 `hosts/thinkpad/`** —— 那里每一条都绑死在
那台的硬件上。下面是骨架，按注释增删：

```nix
{ lib, pkgs, ... }:

{
  # ============================================
  # 本机专属调优。判据：换一台机器这条还成立吗？
  # ============================================

  # --- Btrfs 挂载选项（决策点 C）---
  # nixos-generate-config **不记** compress 和 noatime，
  # 安装时挂载用的那份只作用于安装过程，持久生效必须在这里声明。
  # fileSystems.*.options 是列表，会和 hardware-configuration.nix
  # 里的 subvol= 自动合并，两边各管各的。
  fileSystems."/".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/home".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/nix".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/.snapshots".options = [ "compress=zstd:1" "noatime" ];

  # --- zram ---
  # 内存里的压缩 swap，和磁盘 swap 互补（zram 优先级高，压满了才落盘）。
  zramSwap.enable = true;

  boot.kernel.sysctl = {
    # 按**这台机器**的内存大小和 swap 布局定，别照抄。
    # 100 是「7.6 GiB 内存 + 有磁盘 swap 兜底」算出来的。
    "vm.swappiness" = 100;
    "vm.page-cluster" = 0;   # zram 没有寻道，预读纯属浪费
  };

  # --- 显卡：三选一，删掉不适用的 ---
  #
  # Intel 核显：
  #   hardware.graphics.extraPackages = with pkgs; [
  #     intel-media-driver   # Gen9 及以后走 iHD
  #     intel-vaapi-driver   # 旧的 i965，留给个别只认它的程序
  #   ];
  #   environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  #
  # AMD：mesa 自带 radeonsi，通常什么都不用加
  #
  # NVIDIA：
  #   services.xserver.videoDrivers = [ "nvidia" ];
  #   hardware.nvidia.open = true;   # Turing 及以后
  #
  # 验证：nix shell nixpkgs#libva-utils -c vainfo
  # 应看到驱动名和一串 VAProfile，不是 "no driver"。
  # **配错只会静默软解，不报错。**

  # --- 温控：按 CPU 厂商 ---
  # services.thermald.enable = true;   # **Intel 专用**，AMD 上删掉

  # --- 虚拟机才需要的 ---
  # services.qemuGuest.enable = true;
  # services.spice-vdagentd.enable = true;

  # --- NTFS 共享盘（见 4.3）---
  # UUID 用 blkid 查。nofail 不能省 —— 拔掉那块盘时没有它会卡在开机。
  # fileSystems."/mnt/share" = {
  #   device = "/dev/disk/by-uuid/<blkid 查到的>";
  #   fsType = "ntfs3";
  #   options = [ "nofail" "uid=1000" "gid=100" "umask=0022" ];
  # };
}
```

#### `hosts/<主机>/default.nix`

这份是**本机身份 + 模块拼装**，骨架对所有机器都一样，照抄改四处即可：

```nix
{ pkgs, inputs, ... }:

{
  imports = [
    # 本机专属（跟着这台硬件走）
    ./hardware-configuration.nix
    ./tuning.nix

    # 共用模块（任何机器都能直接 import）
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/desktop-gnome.nix
    ../../modules/localization.nix
    ../../modules/development.nix
    ../../modules/flatpak.nix
    ../../modules/apps.nix
    ../../modules/browsers.nix
    ../../modules/shell.nix
    ../../modules/stylix.nix
    ../../modules/refind.nix

    inputs.home-manager.nixosModules.home-manager

    # stylix 的 NixOS 模块必须排在 home-manager 之后
    inputs.stylix.nixosModules.stylix
  ];

  # ① 主机名（网络上显示的那个）
  networking.hostName = "<主机名>";

  # ② 仓库里的名字：hosts/<这个>/ 目录名 + flake 属性名。
  #    **不一定等于上面的 hostName** —— thinkpad 那台就是
  #    hosts/thinkpad/ 配 thinkpad-nixos。
  custom.flakeHost = "<hosts 目录名>";

  # ③ 键盘布局，两套命名见上面的表
  console.keyMap = "us";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # **首次安装保持 true**，让 systemd-boot 建好自己的 NVRAM 项 ——
  # 那一项是后面装 rEFInd 时的安全网。
  # 装 rEFInd 时（第 6.2 节）再改成 false。
  boot.loader.efi.canTouchEfiVariables = true;

  # ④ 用户账户。登录 shell 的指派放这里而不是 modules/ ——
  #    用户名是本机的事，不该把共用模块钉死在一个用户上。
  users.users."toru" = {
    isNormalUser = true;
    description = "Toru Sugihara";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };
  home-manager.users.toru = import ../../home/toru.nix;

  # home-manager 接管已存在的文件时，把原文件改名成 <原名>.hm-bak
  # 再继续，而不是整个激活失败。见 Lesson-Learn/000B。
  home-manager.backupFileExtension = "hm-bak";

  system.stateVersion = "26.05";
}
```

> **`custom.refind` 先不要加。** 它要读 `hwinfo.nix`，而那个文件要等
> 系统装好、能跑 `refind-hwinfo` 之后才生成。第 6 节再回来加。

#### `flake.nix` 加一个条目

```bash
cat > /tmp/entry.txt <<'EOF'

        # <这台机器是什么>
        <主机名> = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            nix-flatpak.nixosModules.nix-flatpak
            ./hosts/<主机名>/default.nix
          ];
        };
EOF
sed -i '/将来华硕笔记本/r /tmp/entry.txt' flake.nix
sed -n '/nixosConfigurations/,/^    };/p' flake.nix    # 看一眼结构对不对
```

#### 让 flake 看见新文件

```bash
nix-shell -p git --run "git add hosts/$HOST/"
```

**这步不能跳。** flake 看不见未跟踪的文件，不 add 会直接报
`Path 'hosts/xxx/default.nix' ... is not tracked by Git`，安装失败。

#### 新机器没有 SSH，而且主机密钥是全新的

**仓库里任何地方都没有开 `services.openssh`。** 装好的机器默认连不上 ——
对笔记本来说这是对的（少一个暴露面），但如果你打算装完之后远程操作，
得自己在 `hosts/<主机>/default.nix` 里加：

```nix
  # 放 hosts/ 而不是 modules/：要不要开 SSH 是**这台机器**的事。
  # 笔记本通常不需要，服务器和虚拟机需要。
  services.openssh.enable = true;
```

另外，**新机器的 SSH 主机密钥是全新生成的**。如果这台机器是**替换**旧机器、
沿用同一个 IP 或主机名，你从别的机器连过来会撞上：

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

这不是攻击，是 SSH 在正确工作 —— 同一个地址后面换了台机器。在**连接方**清掉旧记录：

```bash
ssh-keygen -R <那台机器的 IP 或主机名>
```

> 主机密钥和第 0 节的 C 类是同一个道理：**一机一把，不该搬**。
> 第 0 节的 C 类表里列的是用户的 `~/.ssh/id_ed25519`，
> 主机密钥（`/etc/ssh/ssh_host_*`）同理 —— 让新机器自己生成。

### 5.3 装

```bash
nixos-install --flake /mnt/home/toru/nixos-config#<新主机名>
```

第一次会比较久（要下载或构建整棵依赖树）。结束时会提示设置 **root 密码**。

### 5.4 设置用户密码 —— 这一步不能省

> **仓库里 `users.users.toru` 没有任何密码字段**，
> `isNormalUser = true` 但既没有 `initialPassword` 也没有 `hashedPassword`。
> 这意味着刚装完时 `toru` 是**锁定账户**，GDM 登不进去。

装完、重启**之前**，在 ISO 环境里就把密码设好：

```bash
nixos-enter --root /mnt -c 'passwd toru'
```

忘了也没关系 —— 重启后在 GDM 界面按 `Ctrl+Alt+F2` 切到 TTY，
用 root 登录再 `passwd toru`。

### 5.5 修正文件属主并重启

```bash
# 仓库是以 root 身份 clone 的，改回 toru
# （uid 1000 / gid 100 是 NixOS 上第一个普通用户和 users 组的默认值）
chown -R 1000:100 /mnt/home/toru

umount -R /mnt
swapoff -a
reboot
```

> 属主这一步不能省。仓库里留下 root 拥有的文件会让 git 和 nix 同时卡住，
> 而且症状很有迷惑性（只对某些文件失败）。
> 见 [Lesson-Learn/0011](Lesson-Learn/0011_ROOT_OWNED_FILES_IN_REPO.md)。

---

## 6. 装 rEFInd

> **本节已在 thinkpad 上实测跑通**（2026-09-20）。
> 选型推理和踩过的五个坑见
> [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。

### 6.1 架构：为什么是两层

```
UEFI 固件
   │
   ▼
rEFInd                      顶层入口，负责好看和选系统
   ├──> Windows Boot Manager     \EFI\Microsoft\Boot\bootmgfw.efi
   └──> systemd-boot             \EFI\systemd\systemd-bootx64.efi
           └──> NixOS 的全部 generation（回滚安全网在这一层）
```

**为什么不用 NixOS 官方的 `boot.loader.refind`：**

它设 `system.boot.loader.id = "refind"`，和 `systemd-boot.enable` **互斥** ——
两层结构根本搭不起来。而且它会把**每一个 generation 展开成一条顶层
`menuentry`**，菜单里排着一长串 NixOS 图标，正好毁掉选 rEFInd 的理由。
它还会每次 rebuild 整个重写 `refind.conf`。

所以 rEFInd 在这套方案里**不由 `boot.loader` 管**，而是：
仓库用 Nix 把素材备好（rEFInd 二进制、生成好的主题、`refind.conf`），
再由 `refind-sync` 这一条**你主动跑**的命令写进 ESP。

好处是 `nixos-rebuild` 永远不会意外改动引导分区。

### 6.2 关掉 NVRAM 争夺

`hosts/<主机>/default.nix` 里：

```nix
  boot.loader.efi.canTouchEfiVariables = false;
```

**必须改。** 保持 `true` 的话，systemd-boot 每次 `switch` 都会把自己设回
UEFI 启动顺序第一位，rEFInd 就永远轮不到 —— 正好抵消装它的意义。

> **这同时就是安全网。** 改成 `false` **不会删掉**已经存在的那条
> `Linux Boot Manager` NVRAM 项，只是不再更新它。
> 也就是说 rEFInd 出任何问题，开机敲启动菜单键（ThinkPad 一般是 **F12**）
> 选 `Linux Boot Manager`，照样正常进系统。**不需要 U 盘救援。**

### 6.3 写进 ESP

```bash
sudo refind-sync
```

它做四件事：

1. 把 `refind_x64.efi` 复制到 `<ESP>/EFI/refind/`
2. 把生成好的 finn-term 主题铺到 `<ESP>/EFI/refind/themes/finn-term/`
3. 写 `<ESP>/EFI/refind/refind.conf`
4. 用 `efibootmgr` 建一条 rEFInd 的 NVRAM 项并提到第一位

主题来自 [FaeArtz/refind-finn-term](https://github.com/FaeArtz/refind-finn-term)，
作为 `flake = false` 的 input 被 `flake.lock` 钉死，和 Agent Skills 同一个机制。
它的 `src/gen.py` 会按**分辨率、主机名、硬件清单**生成背景图。

那几行硬件不用手写 —— 先跑一次探测：

```bash
cd ~/nixos-config
sudo refind-hwinfo          # 加 sudo 才读得到内存代数（DDR3/DDR4）
git add hosts/<主机>/hwinfo.nix
sudo nixos-rebuild switch --flake .#<主机>
sudo refind-sync
```

> **第一次在一台机器上配 rEFInd 要 `nrb` 两次** —— `refind-hwinfo`
> 本身就是 `custom.refind.enable` 带进来的，开启之前它不存在。
> 完整顺序见第 9.3 节。

**中间那次 switch 不能省。** `refind-sync` 里的主题路径是**构建时烤死的
store 路径**，不重新构建的话新图根本不存在，sync 拷的还是旧那份。

内核版本那一行不进 `hwinfo.nix` —— 它由模块从
`config.boot.kernelPackages` 直接取，升级内核会自己跟着变。

### 6.4 分辨率：装完必须回头校一次

**rEFInd 的 `resolution` 只能从 UEFI GOP 实际提供的模式里挑**，
不是常见分辨率就一定有。**写了固件不支持的值，rEFInd 启动时会直接报该模式不存在，
然后回退到别的模式，背景图被拉伸或平铺。**

> **别想当然地填 1080p。** thinkpad 这台就是反例：
> 第一次按「1080p 哪个固件都支持吧」填了 1920×1080，实机直接报不存在。
> 它的 GOP 实际给的是 `Mode 0: 2560x1440`（面板原生）、
> `Mode 5: 1600x1200`、`Mode 6: 1920x1440` —— **压根没有 1080p。**

所以流程是：

1. 先随便填一个值装上去，`refind-sync`，重启
2. 固件不支持的话，rEFInd 启动时会**把它支持的全部模式列出来**。
   想主动列出来，把 `resolution` 临时设成一个明显无效的值（比如 `1 1`）
3. 挑面板原生那个（通常就是 `Mode 0`），改回 `hosts/<主机>/` 的分辨率参数
4. `nrb` 重新生成主题，再 `sudo refind-sync` 一次

> **每台新机器都要走一遍这四步。** 没有能提前探测的办法 ——
> GOP 模式列表只有在固件环境里才拿得到，Nix 构建的沙箱里更不可能。

验证是否真的跑在目标分辨率：在 rEFInd 界面按 **`F10`** 截图，
它会往 ESP 根目录写一张未压缩 24 位 BMP。文件大小 = `宽 × 高 × 3 + 54`，
反推即可。2560×1440 对应 11,059,254 字节。

> **F10 截图 rEFInd 自己从不清理**，每张 11 MB，攒几张就吃掉 ESP 一块。
> 看完删掉：`sudo rm -f /boot/screenshot_*.bmp`

### 6.5 双启动：两个 ESP 各装一份

**已在虚拟机里验证过**（造一块盘、格 FAT32、放一个假的 `bootmgfw.efi`）。

#### 为什么要两份

`bcdedit` 的 path 是**相对于 Windows 自己所在的那个 ESP** 的，
指不到另一块盘的 ESP 里去。所以：

- **NixOS 盘的 ESP**：日常走这条，NVRAM 第一顺位指它
- **Windows 盘的 ESP**：`bcdedit` 劫持用，Windows 抢回第一顺位时的兜底

两条路都通到 rEFInd，怎么冲都坏不了。代价是升级 rEFInd 时两份都要更新
（`refind-sync` 一条命令写两个，不用手动）。

#### 第二个 ESP 必须挂载并声明进配置

**这一步最容易漏。** `refind-sync` 要往那个 ESP 里写东西，所以它得挂着；
而手工 `mount` 的重启就掉了。写进 `hosts/<主机>/tuning.nix`：

```bash
blkid /dev/<Windows 盘的 ESP 分区>
```

> **FAT32 的 UUID 是 8 位短格式**（`1D5C-9F1B` 这样），
> 不是 ext4/btrfs 那种 36 位的。抄错了配上 `nofail` 会**静默失败** ——
> 不报错、不阻止开机，你只会在后面发现 rEFInd 没写进第二个 ESP，
> 然后跑去怀疑 refind 模块。

```nix
  # Windows 盘的 ESP。nofail 不能省 —— 拔掉那块盘时没有它会卡在开机。
  fileSystems."/mnt/winesp" = {
    device = "/dev/disk/by-uuid/XXXX-XXXX";
    fsType = "vfat";
    options = [ "nofail" "fmask=0077" "dmask=0077" ];
  };
```

#### 然后告诉 rEFInd 这两件事

```nix
  custom.refind = {
    enable = true;
    resolution = { width = 1920; height = 1080; };

    # 两个 ESP 各装一份。**NVRAM 项只为第一个建。**
    espMountPoints = [ "/boot" "/mnt/winesp" ];

    extraEntries = ''
      menuentry "Windows 10" {
          icon   /EFI/refind/themes/finn-term/icons/os_win.png
          volume WINESP
          loader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };
```

两个细节：

- **`icon` 必须是从 ESP 卷根算起的绝对路径**，不能写相对 rEFInd 目录的。
  写错不报错，只显示一个约 32×32 的内置占位方块。见
  [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md) 坑 1。
- **`volume` 不能省**。那个 `.efi` 在**另一块盘**上，不写 volume 的话
  rEFInd 只在自己所在的 ESP 里找。`WINESP` 是 `mkfs.fat -n` 设的卷标，
  也可以用分区 GUID。

`nrb` 之后 `sudo refind-sync`，然后确认两份都写进去了：

```bash
sudo ls /boot/EFI/refind/
sudo ls /mnt/winesp/EFI/refind/
```

#### Windows 侧的防御

```powershell
# 管理员 PowerShell
bcdedit /set {bootmgr} path \EFI\refind\refind_x64.efi
```

Windows 的功能更新会擅自把 UEFI 启动顺序第一位重置成
`Windows Boot Manager`。这条让 Windows 自己的引导入口也指向 rEFInd，
于是它抢回第一顺位也没用 —— 开机照样先进 rEFInd。

### 6.6 开不了机怎么办

按代价从小到大：

| 症状 | 怎么救 |
|------|--------|
| rEFInd 起来了但找不到 NixOS | 按 `Esc` 让它重新扫描。还是没有的话看 `refind.conf` 里手写的那条 `menuentry` 路径对不对（`\EFI\systemd\systemd-bootx64.efi`）|
| rEFInd 本身起不来 / 黑屏 | 开机敲 **F12**（ThinkPad）选 `Linux Boot Manager`，直接走 systemd-boot。**thinkpad 上实测过** |
| rEFInd 的 NVRAM 项整个失效 | **什么都不用做** —— 固件会往下落到通用设备项（`NVMe0`），走 UEFI 可移动回退路径 `\EFI\BOOT\BOOTX64.EFI`，那也是 systemd-boot |
| 启动菜单里也没有可用项 | 进固件设置（ThinkPad 是 **F1**），把启动项手动指到 `\EFI\systemd\systemd-bootx64.efi` |
| 系统起来了但配置坏了 | `sudo nixos-rebuild switch --rollback` |
| 以上全失败 | 用第 2 节的 U 盘启动，挂载分区后 `nixos-enter --root /mnt` 修 |

> **动手前先确认你这台机器的启动菜单键是哪个。**
> ThinkPad 一般是 F12，但要在开机 logo 那一瞬敲对；
> 有些机型要先在固件里把 "Startup Interrupt Menu" 打开。
> **这件事要在改 `canTouchEfiVariables` 之前就验证过。**

---

## 7. 还原 `$HOME` 里 Nix 管不到的部分

> **本节已实现并实测过**（2026-09-21）。`state-sync` 和 `migration-check`
> 都在 PATH 上，本地状态仓库已建。**远程仓库还没建**，见 7.1。

### 7.1 B 类状态

```bash
git clone git@github.com:SenorToru/dotfiles-state ~/dotfiles-state
state-sync restore
```

`state-sync` 的四个子命令：

| 命令 | 作用 |
|------|------|
| `state-sync status` | 看哪些路径有差异 |
| `state-sync push` | 把本机的 B 类路径收进仓库（**不自动 commit**） |
| `state-sync pull` | 拉远程最新 |
| `state-sync restore` | 把仓库内容铺回 `$HOME` |

**推送是手动的**，而且 `push` 只复制不提交。理由和这个仓库
「Toru 实机验证过再提交」是同一条：不能让一个刚改坏的配置
被自动推上去覆盖掉好的。

收哪些路径由 `home/migration.nix` 的 `stateFiles` 决定，
`state-sync` 和 `migration-check` 共用同一份清单。

`push` 会剔掉日志、锁文件和 `.session.ipc`。最后那个记的是**本机的
套接字路径**，拷到新机器上是错的。

> ### 这个仓库必须是 private
>
> 里面有输入法的学习历史 —— 那是你打过的字的统计痕迹。
>
> 建的时候：
>
> ```bash
> cd ~/dotfiles-state
> git add -A && git commit -m "初始状态"
> gh repo create SenorToru/dotfiles-state --private --source=. --push
> ```
>
> 推之前先看一眼收进来的是什么：
>
> ```bash
> find ~/dotfiles-state -path '*/.git' -prune -o -type f -print
> ```
>
> 应该只有 fcitx5 的三项、mozc 目录、以及四个零碎状态文件，
> 一共十几个文件、几百 KB。**看到任何 `gh`、`keyrings`、`.ssh`
> 相关的东西就停下来** —— 那是 C 类，不该在这里。

### 7.2 输入法

B 类那部分（`~/.config/fcitx5/`、`~/.config/mozc/`）`state-sync restore`
已经搞定了。剩下三件事：

**删掉 rime 的编译缓存**（如果 restore 误带了的话）：

```bash
rm -rf ~/.local/share/fcitx5/rime/build
```

首次部署要一两分钟（白霜 29 MB 词库 + 7 MB 语法模型要编译成 `.bin`），
属正常，别以为卡死了。

**让 Rime 自己生成 `installation.yaml`**，然后在里面加一行开启同步：

```yaml
sync_dir: "/home/toru/Sync/rime"
```

两台机器指向同一个目录（Syncthing / git / 网盘都行），在输入法菜单里点「同步」。
它会导出成文本再**双向合并词频** —— 这是 `*.userdb/` 那个 LevelDB
唯一正确的搬运方式，手工拷贝没法合并，两台机器各自学的东西只能二选一。

> **不要用 home-manager 去管 `installation.yaml`。**
> Rime 自己要往里写 `install_time` 等字段，软链成只读会让它写失败。

**Mozc 没有同步功能**，只能靠 `state-sync` 整个目录搬。
`.history.db` 是加密的，`.encrypt_key.db` 必须一起 —— 少了密钥等于学习记录全丢。

### 7.2.5 让 home-manager 接管一个已存在的配置文件

把某个手写的配置收进 Nix 时（比如 `~/.gitconfig` → `programs.git`），
**顺序是「先让新的生效，确认无误，再删旧的」，不能反过来。**

反过来做会有一段**空窗期**：旧的删了、新的还没 switch 上去，
这期间那个程序没有配置。`git` 的表现是 `git commit` 直接被拒
（`Please tell me who you are`）。实际踩过一次。

正确顺序：

```bash
sudo nixos-rebuild switch --flake .#<主机>   # 1. 新配置先生效
git config --list --show-origin              # 2. 确认来源变成了新文件
rm ~/.gitconfig                              # 3. 再删旧的
```

> **`~/.gitconfig` 这个例子还有个额外的坑**：home-manager 写的是
> `~/.config/git/config`，而 git 读完 XDG 路径**之后**才读 `~/.gitconfig`
> —— 后读的赢。所以旧文件不删的话，switch 完仍然是旧配置在生效，
> 看起来像「改了没用」。

`backupFileExtension = "hm-bak"` 会把被接管的原文件改名成
`<原名>.hm-bak` 保留下来。那是接管成功的证据，核对完就该删：

```bash
migration-check        # 它会列出所有 .hm-bak 并告诉你内容和现役是否一致
```

不删的话它们会一直躺着，而且会让 `migration-check` 把整个目录
误报成「没人认领」（因为目录里混进了一个不是 store 链接的真实文件）。

### 7.3 C 类：重新签发清单

**顺序有意义。** SSH 密钥排在第一条不只是因为推仓库要用它 ——
仓库配了 `commit.gpgsign = true`（用 SSH 密钥签提交），
密钥不存在时 `git commit` 会**直接失败**。
先克隆、先 `nrb`、最后才想起来生成密钥的话，第一次提交就会撞上这个。

```bash
# 1. SSH key。一台机器一把，不要从旧机器拷。
ssh-keygen -t ed25519 -C "<新机器标识>"
cat ~/.ssh/id_ed25519.pub
```

**这把公钥要在 GitHub 上登记两次**，位置都在
Settings → SSH and GPG keys，但是两个独立的条目：

| 登记成 | 干什么用 | 不登记的症状 |
|--------|----------|--------------|
| **Authentication key** | `git push` / `git clone` 走 SSH | 推不上去，`Permission denied (publickey)` |
| **Signing key** | 提交显示 Verified 徽章 | 能推，但 GitHub 上显示 Unverified |

两种症状完全不像，所以**容易只登记一个然后查错方向**。
加的时候页面上有个 Key type 下拉框，选对再提交。

**忘了登记 Signing key 不用重签。** GitHub 是**每次展示页面时**拿当前
登记的公钥去验的，不是提交时固化一个结论。所以补登记之后，
之前推上去显示 Unverified 的提交会**自动变成 Verified**，
不需要 rebase、不需要 `--amend`、不需要重推。

> 这条对**已经在用的机器**同样成立，而且那种机器更容易漏 ——
> 本节是按「装新机器」写的，老机器不会有人翻到这里。
> thinkpad 第一次签名提交就是这么推成 Unverified 的。
> **判据不是「这台机器新不新」，是「这把公钥登记过 Signing key 没有」。**

```bash
# 2. 把这台机器的公钥加进仓库的验签清单。
#    home/toru.nix 开头的 signingKeys，键名用 hosts/ 下的目录名，
#    值是裸公钥（去掉 ssh-keygen 加在末尾的那段 comment）。
#
#    不加的话签名照样能打、GitHub 照样显示 Verified，
#    但**别的机器**验不了这台机器签的提交
#    （`git log --show-signature` 报 no principal matched）。
#
#    改完要 nrb，并且这个改动要推回去让其它机器也拿到。
#
#    注意这里是**不对称**的，第一次撞上会以为坏了（2026-09 实测）：
#
#      加钥匙的那台机器    清单里立刻两行都有，能验所有人的提交
#      其它机器            要 pull 到这个提交、**再重建一次**才验得了它
#
#    所以新机器签的第一个提交，在老机器上会显示
#    `Good "git" signature ... No principal matched.` ——
#    签名本身是有效的，只是那台机器还不认识这把钥匙。
#    这是鸡生蛋，不是故障：钥匙只能跟着它自己的提交进来。
#    想确认签它的确实是要加的那把，比对指纹即可：
#    `ssh-keygen -lf ~/.ssh/id_ed25519.pub` 和报错里那串 SHA256 对一下。

# 3. GitHub CLI
gh auth login

# 4. Claude Code
claude          # 首次启动会引导登录
#    会话记录要在「第一次在项目目录里启动 claude」之前放回去，见 7.5

# 4b. Grok Build（xAI 的终端 agent，需要 SuperGrok / X Premium+ 订阅）
grok login
#    不要跑 `grok update` —— 它会在 ~/.grok/bin/ 另装一份不归 Nix 管的 grok

# 5. Cloudflare（wrangler）。它是项目的 devDependency，要先 clone 项目、
#    direnv allow、pnpm install，然后在项目目录里登录。
#    旧机器的令牌不要拷 —— 那是能直接部署到生产的凭据。
cd ~/Projects/dev/craft-crm && pnpm exec wrangler login
#    项目自己的完整步骤（带哪些文件、自检 pnpm run doctor）在 craft-crm 的 README §2.1

# 6. 把 nixos-config 的 remote 从 https 换成 ssh
cd ~/nixos-config
git remote set-url origin git@github.com:SenorToru/nixos-config.git

# 7. 验证整条链路通了
ssh -T git@github.com                     # 应该回 "Hi SenorToru! You've successfully authenticated"
git -C ~/nixos-config log --show-signature -1   # 应该看到 Good "git" signature
```

剩下的靠图形界面：

- **WiFi**：GNOME 设置里重新输
- **GNOME keyring**：首次用到时解锁
- **浏览器**：Zen / Brave / Firefox 各自登录账号，靠它们自己的同步拉回书签和扩展设置
- **Proton Pass**：浏览器扩展里登录
- **VS Code**：登录 GitHub Copilot 账号。**扩展要手工装**，见下面 7.4。

### 7.4 手工装的东西

这几样**有意不进 Nix**，所以新机器上要自己装。
`migration-check` 会盯着它们，少了会报「清单里有但没装」。

#### VS Code 扩展（4 个）

```
anthropic.claude-code
brettm12345.nixfmt-vscode
jnoortheen.nix-ide
shd101wyy.markdown-preview-enhanced
```

在 VS Code 里按 `Ctrl+P`，逐个输 `ext install <上面的 ID>`。

> **为什么不声明进 Nix：** nixpkgs 里那几个版本比实际用的旧。
> `anthropic.claude-code` 会退到 **2.1.223** —— 正是
> [Lesson-Learn/0010](Lesson-Learn/0010_CLAUDE_CODE_VERSION_PINNING.md)
> 记的那个被发布分支冻住的版本，而 CLI 那边已经用 manifest 覆写
> 升上去了。装个旧扩展自相矛盾。
>
> `jnoortheen.nix-ide` 和 `shd101wyy.markdown-preview-enhanced` 同样偏旧。
>
> 权衡的结果是**宁可手工装、让 `migration-check` 盯着**，
> 也不要为了声明式的纯度把常用工具拽回旧版本。
>
> 清单在 `home/migration.nix` 的 `vscodeExtensions`。
> **改那里的同时要改这一节** —— 两处都是给人看的，漂移了就会互相矛盾。

### 7.5 Claude Code 的会话记录

和各项目里 Claude Code 的全部对话、以及它攒下的记忆（`memory/`），都在
`~/.claude/projects/<目录名>/` 下。**目录名就是项目的绝对路径把 `/` 换成 `-`**：

    /home/toru/Projects/dev/craft-crm  ->  -home-toru-Projects-dev-craft-crm
    /home/toru/nixos-config            ->  -home-toru-nixos-config

所以只要新机器上项目放在**同一个路径**（用户名 toru、目录一致），原样拷过去就能用，
不需要改写里面的路径。换了路径的话，Claude Code 会当成另一个项目，历史和记忆都看不见。

**它含密钥明文**（对话里贴过、命令输出里出现过的 token 和 secret），处理规格等同 `.env`：
**只走 U 盘，用完删掉 U 盘上的副本；绝不进任何 git 仓库，包括 `dotfiles-state`，也不进云同步。**

搬的只有 `projects/` 下这两个目录（连同里面的 `memory/` 和 `<会话id>/subagents/`）。
`.credentials.json`、`sessions`、`file-history`、`shell-snapshots` 这些是本机的凭据
和运行时状态，不搬（`migration-check` 的 `ignoredClaude` 也是这么分的）。
`~/.claude.json` 里的项目条目不用手工合并：它记的 `allowedTools` 等目前都是空的，
新机器上第一次打开项目时点一次「信任」即可。

**一次性搬、单向搬。** 搬完之后旧机器不再在这两个项目里开 Claude Code，
不做两台机器之间的同步 —— `memory/` 里是许多小文件，两边都写的话会互相覆盖，
而且覆盖掉的是哪条记忆事后很难发现。

```bash
# ---- 旧机器 ----
# 1. 先确认没有 Claude Code 在跑。运行中的实例会继续往 jsonl 和 memory/ 里写，
#    拷到一半的快照可能缺掉最后一段。
pgrep -af claude || echo "没有在跑的 claude"

# 2. 拷到 U 盘（<U盘> 换成实际挂载点，lsblk 或 ls /run/media/toru 查）
USB=/run/media/toru/<U盘>
mkdir -p "$USB/claude-projects"
cp -a ~/.claude/projects/-home-toru-Projects-dev-craft-crm \
      ~/.claude/projects/-home-toru-nixos-config \
      "$USB/claude-projects/"

# ---- 新机器 ----
# 3. 放回去。最好在「第一次在这两个项目目录里启动 claude」之前做；
#    已经启动过也没关系，cp 是合并，只是 memory/MEMORY.md 会被旧机器那份覆盖（通常正是想要的）。
mkdir -p ~/.claude/projects
cp -a "$USB/claude-projects/." ~/.claude/projects/

# 4. 校验：会话数和记忆数与旧机器上一致
for d in -home-toru-Projects-dev-craft-crm -home-toru-nixos-config; do
  echo "$d: $(ls ~/.claude/projects/$d/*.jsonl | wc -l) 个会话, $(ls ~/.claude/projects/$d/memory 2>/dev/null | wc -l) 个记忆文件"
done
#    再到项目目录里 `claude --resume`，应该能列出旧机器上的会话。

# 5. 删掉 U 盘上的副本
rm -rf "$USB/claude-projects"
```

U 盘是闪存，`rm` 之后数据在物理上不一定马上消失。这份归档里的密钥如果在意，
搬完之后把 U 盘整个格式化一次；最稳妥的是把归档里出现过的那几把钥匙轮换掉。

---

## 8. 验证清单

**构建通过不等于可用。** 按下面逐条跑，有一条对不上就别往下走。

```bash
# 系统身份
hostnamectl                                   # 主机名对不对
nixos-rebuild list-generations | head -3      # 真的生成了 generation

# 文件系统与压缩
findmnt -t btrfs -o TARGET,OPTIONS            # 四个 subvolume + compress=zstd:N
sudo btrfs filesystem usage /                 # 实际占用
swapon --show                                 # zram 和磁盘 swap 都在，优先级 zram 高

# 字体（族名写错会静默回退，这是本仓库最老的坑）
fc-match "Sarasa Mono J"
fc-match "Noto Serif CJK JP"

# 显卡硬解（配错只会静默软解，不报错）
nix shell nixpkgs#libva-utils -c vainfo       # 应该看到驱动名和一串 VAProfile

# shell 与工具
echo $SHELL                                   # /run/current-system/sw/bin/zsh
claude --version
skills status                                 # 三个目录各能看见多少个 skill
skills list | tail -3                         # 数量要和每个 AI 工具里实际看到的对上

# git 身份与签名
ssh -T git@github.com                         # Hi SenorToru! ...（认证用的那把登记好了）
git -C ~/nixos-config log --show-signature -1 # Good "git" signature for dev@toru-leathers.com
cat ~/.config/git/allowed_signers             # 每台机器一行，本机那行在不在

# DNS：加密解析生效了没有（modules/dns.nix）
resolvectl status                             # Global 段是四个带 # 主机名的；
                                              # 每个 Link 段的 Current Scopes 不含 DNS、
                                              # 且没有 DNS Servers: 那一行。别加 head，
                                              # Link 段在后面，截断就看不见了
resolvectl query --type=AAAA lwn.net          # 拿到地址，不是 SERVFAIL
nix shell nixpkgs#dnsutils -c dig +time=3 +tries=1 A example.org @192.0.2.1
# 上面这条**必须超时**。192.0.2.1 全球不可路由，能拿到应答就是
# 有中间设备在截 UDP/53，见 Lesson-Learn/0014

# 服务
systemctl is-active fwupd
systemctl --failed                            # 应该是 0 loaded units listed

# 输入法：图形界面里实际打几个字
#   中文：白霜拼音，试一下 Shift 切换和候选词
#   日文：mozc-ut，试一个专有名词（UT 词典补的正是这块）

# 引导（第 6 节做完之后）
sudo ls /boot/EFI/refind/                     # /boot 是 dmask=0077，必须 sudo
nix shell nixpkgs#efibootmgr -c sudo efibootmgr   # rEFInd 在第一位，Linux Boot Manager 还在

# 仓库属主（跑过 sudo 之后）
cd ~/nixos-config && find . ! -user toru -printf '%u  %p\n'
# 应该没有任何输出
```

> **`efibootmgr` 不在默认 PATH 上**，要 `nix shell nixpkgs#efibootmgr` 临时取。

最后：**重启一次，确认 rEFInd 菜单出现、两个系统都能选、分辨率正常。**

---

## 9. 把已有机器导入 rEFInd

现在这台 thinkpad 用这一节。它已经在跑 systemd-boot，
所以只是**在上面加一层 rEFInd**，不换引导器。

> **本节已在 thinkpad 上实测跑通**（2026-09-20）。下面是实际走过的顺序。

### 9.1 先把退路走一遍 —— 这一步不能跳

```bash
nix shell nixpkgs#efibootmgr -c efibootmgr    # 读 NVRAM 不需要 root
df -h /boot                                   # rEFInd + 主题约 5 MB
```

在输出里找到 **`Linux Boot Manager`** 那一项（指向
`\EFI\systemd\systemd-bootx64.efi`），记下它的 `Boot####` 号。

然后**重启，敲启动菜单键（ThinkPad 是 F12），选中它，真的进一次系统**。
回来确认 `BootCurrent` 变成了那个号。

> **「理论上有退路」和「亲手走过一遍退路」是两回事。**
> 花的是三分钟，换的是出事时不用慌。这应该是固定环节，不是可选项。
>
> 有些 ThinkPad 要先在固件里打开 `Startup Interrupt Menu` 才有 F12。

顺便看一眼有没有指向**不存在分区**的死启动项（以前装别的系统留下的）。
有的话清掉，开机能快几秒：

```bash
sudo efibootmgr -b 0001 -B
sudo efibootmgr -b 0002 -B
```

> **一条一条跑。** 用 `&&` 串起来实测只有第一条生效。
> `-B` 会同时把该项从 `BootOrder` 里摘掉，不用手动改顺序。

### 9.2 改配置

在 `hosts/<主机>/default.nix` 里：

```nix
  imports = [ ... ./hwinfo.nix ];            # 下一步生成

  boot.loader.efi.canTouchEfiVariables = false;   # 必须，见 6.2

  custom.refind = {
    enable = true;
    flakeHost = "thinkpad";                  # hosts/ 目录名，可能 ≠ hostName
    resolution = { width = 2560; height = 1440; };   # 先随便填，6.4 再校
  };
```

并把 `../../modules/refind.nix` 加进 `imports`。

### 9.3 装上去 —— 要 `nrb` 两次

> ### 鸡生蛋：`refind-hwinfo` 要 `nrb` 之后才存在
>
> 那个命令来自 `modules/refind.nix`，只在 `custom.refind.enable = true`
> **且构建生效之后**才进 PATH。所以**第一次**在一台机器上配 rEFInd 时，
> 不能先跑它。
>
> 第一次 `nrb` 能过，是因为 `custom.refind.bootRows` 默认是空列表 ——
> 主题照样生成，只是启动画面上只有内核那一行。第二次才补上硬件。

```bash
cd ~/nixos-config

# ① 先构建一次，把 refind-hwinfo / refind-sync 装进 PATH。
#    此时 ./hwinfo.nix 还不存在，也不要 import 它。
git add hosts/<主机>/                                # 新文件必须 add
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
nix build .#nixosConfigurations.<主机>.config.system.build.toplevel --out-link /tmp/res
sudo nixos-rebuild switch --flake .#<主机>

# ② 现在探测硬件
sudo refind-hwinfo

# ③ 把生成的文件让 git 看见，并加进 imports
git add hosts/<主机>/hwinfo.nix
#    在 hosts/<主机>/default.nix 的 imports 里 ./tuning.nix 下面加一行：
#        ./hwinfo.nix

# ④ 再构建一次，这次主题才带上 CPU / GPU / 内存 / 磁盘
sudo nixos-rebuild switch --flake .#<主机>

# ⑤ 写进 ESP
sudo refind-sync
```

**第 ⑤ 步必须在 switch 之后。** 反过来的话，那次 switch 会把
`refind-sync` 里烤死的主题 store 路径换成新的，而 ESP 里还是旧的 ——
等于白同步。

> 已经配过 rEFInd 的机器（比如换了硬件要重新探测）没有这个问题，
> 三步就够：`sudo refind-hwinfo` → `nrb` → `sudo refind-sync`。

### 9.4 重启验证

要看四件事：

1. rEFInd 菜单出现（没出现说明落回 systemd-boot 了）
2. 背景是 finn-term，左上角硬件信息是**这台机器的**
3. **有一个 NixOS 图标**，不是一个约 32×32 的黄黑斜条小方块 ——
   那个方块是 rEFInd 内置的「图片加载失败」占位符，说明 `icon` 路径不对
4. 背景填满屏幕，没有被拉伸或平铺

然后按 6.4 校分辨率，`nrb` + `sudo refind-sync` 再来一次。

任何一步出问题：**敲 F12 选 `Linux Boot Manager`**，一切照旧 ——
`refind-sync` 只往 `\EFI\refind\` 这个新目录写东西，
`\EFI\systemd\` 和 `\EFI\BOOT\` 原封不动。

---

## 10. 维护这份文档

### 什么时候必须回来改

**加了任何新的开发工具，就要问一句：它有没有留下 Nix 管不到的状态？**

| 加了什么 | 要检查 |
|----------|--------|
| 新的语言工具链（Rust / Go / Python…） | 有没有用户级的 registry / 缓存 / 凭据（`~/.cargo/credentials`、`~/.npmrc`）|
| 虚拟机（QEMU / VirtualBox / Docker） | 镜像和虚拟磁盘在哪、要不要搬 |
| 需要登录的服务 | 加进 7.3 的重新签发清单 |
| 新的 GUI 程序 | 它的配置在 `~/.config/` 下，看是该进 Nix（A 类）还是进 `dotfiles-state`（B 类）|
| 新的 Flatpak | 加进 `modules/flatpak.nix`，**别只装不声明** |
| 新硬件类别（独显、无线网卡） | 第 5.2 节的 `tuning.nix` 要点里补一条 |
| **新机器本身** | 公钥加进 `home/toru.nix` 的 `signingKeys`，否则别的机器验不了它签的提交 |

**判据永远是第 0 节那三类。** 能进 Nix 就进 Nix（A 类），
进不了但能版本化就进 `dotfiles-state`（B 类），
是秘密就不搬、加进重新签发清单（C 类）。

### 不靠记性：`migration-check`

```bash
migration-check
```

> 已实现。首次运行就抓到三处真实漂移：没声明的 HandBrake、
> `enabled-extensions` 里一个根本没装的死 UUID、以及一条只存在于
> `~/.config/git/ignore` 里的全局 gitignore 规则。

它扫 `$HOME`，把**实际存在但本文档和 `dotfiles-state` 都没提到**的东西报出来。
加完新工具之后跑一下就知道这份指南缺了什么。

它抓得住的典型漂移，今天就有一个现成的例子：
`~/.var/app/fr.handbrake.ghb` 装着但 `modules/flatpak.nix` 里没声明 ——
新机器上 HandBrake 不会出现，而且没有任何东西会提醒你。

### 同步要求

改本文档的同时，检查这三处要不要跟着改：

- [README.md](README.md) 的「迁移到新机器」一节（应该只是一个指向这里的链接）
- [CLAUDE.md](CLAUDE.md) 的维护约定清单
- `migration-check` 的检查规则

---

## 附：还没解决的问题

| 问题 | 状态 |
|------|------|
| `users.users.toru` 没有密码字段，新机器装完账户是锁定的 | **有意不改**。密码属 C 类，塞进仓库是倒退。第 5.4 节的 `nixos-enter … passwd toru` 是正解 |
| B 类清单是否还有该收未收的 | 加了新工具之后跑 `migration-check`，它会报出 `$HOME` 里没人认领的东西 |
| 第 1-5 节没在全新机器上从头跑过 | 只能等下次真装新机器时验证，对不上的地方回来改 |
| 独显探测判据未经多显卡机器验证 | AMD 的 APU 不在 PCI bus 00 上且也报显存，可能被误判成独显。真遇到直接改 `hwinfo.nix` |
| `~/.grok/` 的 A / B / C 划分 | 2026-09-23 刚装，还没登录用过，目录里会有什么未实测。凭据先按 C 类记；登录并用过几天后跑 `migration-check`，它会把 `~/.grok` 报成没人认领，届时逐项分类、补进 `ignoredHome` 或 `stateFiles`，再改这一行 |
| VS Code 的四个扩展仍是手工装的 | nixpkgs 里的版本比实际装的旧（claude-code 会退到 2.1.223），声明进 Nix 等于降级。归手工清单，`migration-check` 盯着 |

**已解决**（原先列在这里）：

- **rEFInd 的实际 GOP 模式**（批二）—— 是 `Mode 0: 2560x1440`（面板原生），
  **没有 1080p**。和另外四个实机坑一起记在
  [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。
- **四个别名写死 `#thinkpad`**（批三）—— 改成从
  `osConfig.custom.flakeHost` 和 `config.home.homeDirectory` 取。
- **`~/.gitconfig` 钉死 gh 的 store 路径**（批三）—— 改成
  `programs.git` 声明，helper 写成 `${pkgs.gh}/bin/gh`，跟着 store 走。

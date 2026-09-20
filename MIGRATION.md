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
| 三 | A 类配置补全、`migration-check`、`state-sync`、README/CLAUDE.md 同步 | **未开始** |

**第 6 节和第 9 节（rEFInd）已经在这台 thinkpad 上完整跑过一遍**，
包括重启验证菜单、图标和分辨率。过程中踩的五个坑和修法记在
[Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)，本文相应步骤已按实测结果改写。

**还没落地的是第 7 节**：`state-sync` 和 `migration-check` 两个命令尚不存在，
`dotfiles-state` 仓库也还没建（批三）。该节步骤按设计写，未经验证。

第 1-5 节和第 8 节是基于现有仓库和 NixOS 标准流程写的，可以照做，
但**没有在一台全新机器上从头跑过** —— 下次真装新机器时按它走，
对不上的地方要回来改。

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

### C 类 —— 不搬，新机器重新签发

秘密。**刻意不做迁移**，因为密钥本来就该一机一把 —— 泄露时能单独吊销，
而不是一把钥匙开所有门。

| 东西 | 新机器上怎么办 |
|------|----------------|
| `~/.ssh/id_ed25519` | 新生成一把，公钥加到 GitHub |
| `~/.gnupg/` | 需要时新生成 |
| `~/.config/gh/` | `gh auth login` |
| `~/.claude.json`、`~/.claude/` | `claude` 首次启动时登录 |
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
**这个决定在第 4.4 节落地，之后会被 `nixos-generate-config` 写进
`hardware-configuration.nix`，改起来要重挂载 + 重新生成。**

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

> **这一节的每条命令都会不可逆地抹掉数据。**
> 每次动手前先跑一遍 `lsblk -o NAME,SIZE,MODEL,SERIAL`，
> 靠**型号和序列号**确认目标盘，不要靠 `/dev/nvme0n1` 这种会变的名字。

下面以 `/dev/nvme0n1` 为例。**把它换成你确认过的那块盘。**

### 4.1 分区表与分区

```bash
parted /dev/nvme0n1 -- mklabel gpt

# ESP：2 GiB。比常见的 512 MiB 大得多，是有理由的 ——
# 每换一次内核，systemd-boot 就要在这里多存一份约 50-60 MiB 的
# kernel + initrd。1 GiB 的 ESP 会把 configurationLimit 逼到 20 以下。
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 2GiB
parted /dev/nvme0n1 -- set 1 esp on

# swap：按决策点 D，取内存的 1-1.5 倍。这里以 16 GiB 为例。
# 不要磁盘 swap 的话跳过这两行，并把下面 root 分区的起点改成 2GiB。
parted /dev/nvme0n1 -- mkpart swap linux-swap 2GiB 18GiB

# root：剩下全部
parted /dev/nvme0n1 -- mkpart root btrfs 18GiB 100%
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

### 4.4 挂载 —— 压缩等级在这里定

**决策点 C 在这一步落地。** 这里用什么选项挂载，
`nixos-generate-config` 就把什么选项写进 `hardware-configuration.nix`。

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
# ！！改这一行就是改压缩等级：zstd:1 或 zstd:3 ！！
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
```

建新主机目录：

```bash
HOST=<新主机名>          # 例如 desktop
mkdir -p hosts/$HOST
cp /mnt/etc/nixos/hardware-configuration.nix hosts/$HOST/
```

然后写两个文件。**照抄 `hosts/thinkpad/` 的骨架，但 `tuning.nix` 必须重写** ——
里面每一条都绑死在那台的硬件上（Intel 核显驱动、`vm.swappiness` 的数值、
`thermald`），照抄到别的机器上是错的。

`hosts/$HOST/default.nix` 要改的地方：

| 位置 | 改成 |
|------|------|
| `networking.hostName` | 新主机名 |
| `console.keyMap` / `services.xserver.xkb.layout` | 新机器的键盘布局（台式机接美式键盘就是 `us`） |
| `boot.loader.systemd-boot.configurationLimit` | ESP 有 2 GiB 了，可以放宽到 50 |
| `imports` 里的 `./tuning.nix` | 保留，但内容重写 |

`hosts/$HOST/tuning.nix` 按新硬件写，参考判据见 [CLAUDE.md](CLAUDE.md)：

- 显卡驱动：AMD 用 `mesa` 系，NVIDIA 用 `nvidia` 系，别照抄 `intel-media-driver`
- `vm.swappiness`：按实际内存大小和 swap 布局重算
- `services.thermald`：**Intel 专用**，AMD 机器上去掉
- NTFS 共享盘的挂载（如果有，见 4.3）：

```nix
  # NTFS 共享盘。ntfs3 是内核态驱动，比 ntfs-3g 的 FUSE 快一个量级。
  # UUID 用 blkid 查。挂载点和 UUID 是本机的事，所以写在这里而不是 modules/。
  fileSystems."/mnt/share" = {
    device = "/dev/disk/by-uuid/<blkid 查到的>";
    fsType = "ntfs3";
    options = [ "nofail" "uid=1000" "gid=100" "umask=0022" ];
  };
```

`nofail` 不能省 —— 拔掉那块盘时没有它会卡在开机。

最后在 `flake.nix` 的 `nixosConfigurations` 里加一条：

```nix
        <新主机名> = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            nix-flatpak.nixosModules.nix-flatpak
            ./hosts/<新主机名>/default.nix
          ];
        };
```

> ### 别忘了 `git add`
>
> ```bash
> nix-shell -p git --run 'git add hosts/'$HOST'/'
> ```
>
> **flake 看不见未跟踪的文件。** 不 add 就会
> `Path 'hosts/xxx/default.nix' ... is not tracked by Git`，安装直接失败。
> 每个新文件只需 add 一次，之后再改不用重复。

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

### 6.5 双启动：Windows 侧的防御

Windows 的功能更新会擅自把 UEFI 启动顺序第一位重置成
`Windows Boot Manager`。对策是让 Windows 自己的引导入口也指向 rEFInd：

```powershell
# 管理员 PowerShell
bcdedit /set {bootmgr} path \EFI\refind\refind_x64.efi
```

> **前提：Windows 所在盘的 ESP 里也得有一份 rEFInd。**
> `bcdedit` 的 path 是**相对于 Windows 自己所在的那个 ESP** 的，
> 它指不到另一块盘的 ESP 里去。
>
> 所以双盘双启动时**两个 ESP 各装一份**：
>
> - NixOS 盘的 ESP：日常走这条，NVRAM 第一顺位指它
> - Windows 盘的 ESP：`bcdedit` 劫持用，Windows 抢回第一顺位时的兜底
>
> 两条路都通到 rEFInd，怎么冲都坏不了。代价是升级 rEFInd 时两份都要更新。

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

> **本节尚未验证**，`state-sync` 命令目前还不存在（批三）。

### 7.1 B 类状态

```bash
git clone git@github.com:SenorToru/dotfiles-state ~/dotfiles-state
state-sync restore
```

`state-sync` 的三个子命令：

| 命令 | 作用 |
|------|------|
| `state-sync push` | 把本机的 B 类路径收进仓库并提交 |
| `state-sync pull` | 拉远程最新 |
| `state-sync restore` | 把仓库内容铺回 `$HOME` |

**推送是手动的**，没有定时器。理由和这个仓库「Toru 实机验证过再提交」
是同一条：不能让一个刚改坏的配置被自动推上去覆盖掉好的。

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

### 7.3 C 类：重新签发清单

按顺序做，每条都是一次性的：

```bash
# 1. SSH key（之后才能用 git@github.com 推仓库）
ssh-keygen -t ed25519 -C "<新机器标识>"
cat ~/.ssh/id_ed25519.pub        # 贴到 GitHub → Settings → SSH keys

# 2. GitHub CLI
gh auth login

# 3. Claude Code
claude          # 首次启动会引导登录

# 4. 把 nixos-config 的 remote 从 https 换成 ssh
cd ~/nixos-config
git remote set-url origin git@github.com:SenorToru/nixos-config.git
```

剩下的靠图形界面：

- **WiFi**：GNOME 设置里重新输
- **GNOME keyring**：首次用到时解锁
- **浏览器**：Zen / Brave / Firefox 各自登录账号，靠它们自己的同步拉回书签和扩展设置
- **Proton Pass**：浏览器扩展里登录
- **VS Code**：扩展由 `programs.vscode` 声明式装好了，只需登录 GitHub Copilot 账号

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

### 9.3 装上去

```bash
cd ~/nixos-config
sudo refind-hwinfo                                   # 生成 hwinfo.nix
git add hosts/<主机>/hwinfo.nix modules/refind.nix   # 新文件必须 add
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
nix build .#nixosConfigurations.<主机>.config.system.build.toplevel --out-link /tmp/res
sudo nixos-rebuild switch --flake .#<主机>
sudo refind-sync
```

**顺序不能反：先 switch 再 sync。** 反过来的话，那次 switch 还带着
`canTouchEfiVariables = true`，systemd-boot 会把自己重新设回第一位，
rEFInd 白装。

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

**判据永远是第 0 节那三类。** 能进 Nix 就进 Nix（A 类），
进不了但能版本化就进 `dotfiles-state`（B 类），
是秘密就不搬、加进重新签发清单（C 类）。

### 不靠记性：`migration-check`

```bash
migration-check
```

> 这个命令目前还不存在（批三）。

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
| `users.users.toru` 没有密码字段，新机器装完账户是锁定的 | 第 5.4 节绕过了。根治要加 `initialPassword` 或 `hashedPasswordFile`（批三）|
| `nrb` / `nrt` / `ncheck` / `nhm` 四个别名把 `#thinkpad` 写死了 | 新机器上这些别名会去构建 thinkpad 的配置。要改成跟着 `networking.hostName` 走（批三）|
| `~/.gitconfig` 里钉死了 `/nix/store/…-gh-2.99.0/…` 绝对路径 | 那个版本被 GC 掉后 git 的 GitHub 凭据助手就失效。改成 `programs.git` 声明（批三）|
| 第 7 节（`state-sync` / `dotfiles-state`）未实现 | 两个命令还不存在，仓库也还没建（批三）|
| 第 1-5 节没在全新机器上从头跑过 | 只能等下次真装新机器时验证，对不上的地方回来改 |
| 独显探测判据未经多显卡机器验证 | AMD 的 APU 不在 PCI bus 00 上且也报显存，可能被误判成独显。真遇到直接改 `hwinfo.nix` |

**已解决**（原先列在这里，批二做掉了）：
rEFInd 在 thinkpad 上的实际 GOP 模式 —— 是 `Mode 0: 2560x1440`（面板原生），
**没有 1080p**。经过和五个实机坑一起记在
[Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。

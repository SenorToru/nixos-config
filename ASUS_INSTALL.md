# asus 重装指南：Windows + NixOS 双系统

把 ASUS TX Air (FA401KM)，也就是原来跑 Bluefin 的那台，格式化后重装成
**Windows + NixOS 双系统**，主机名 `asus`。

> ## 这份文档是一份「照着做」的操作手册
>
> 从数据备份好之后开始，到 asus 用起来和 thinkpad 一样为止。
> **按顺序一步一步做，每一步末尾的「看到什么算对」对不上就停下来**，
> 别硬着头皮往下走。
>
> 和其它文档的分工：
>
> | 文件 | 管什么 |
> |------|--------|
> | **本文件** | **asus 这一台机器**从头到尾怎么装 |
> | [MIGRATION.md](MIGRATION.md) | 装任意新机器的通用流程和背后的道理（本文很多命令出自那里，想知道「为什么」去翻它） |
> | [REHEARSAL.md](REHEARSAL.md) | 当初在虚拟机里演练的记录 |
> | [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md) | rEFInd 踩过的五个坑 |
> | [README.md](README.md) | 装好之后的日常操作 |

---

## 0. 先看全局

### 0.1 装完是什么样子

```
Samsung 990 PRO 2TB（nvme，归 Windows）
├── 1  ESP          1 GiB      FAT32   卷标 SYSTEM     Windows 的引导
├── 2  MSR          16 MiB
├── 3  C:           约 859 GiB NTFS    卷标 Windows
├── 4  恢复分区     1 GiB      NTFS    卷标 Recovery
└── 5  共享盘       1000 GiB   NTFS    卷标 share      Windows 和 NixOS 共用

KIOXIA 3.7T（nvme，归 NixOS）
├── 1  ESP          约 2 GiB   FAT32   卷标 BOOT       NixOS 的引导
└── 2  Btrfs        其余约 3.7 TiB     卷标 nixos      子卷 @ @home @nix @snapshots
                                        没有 swap 分区，只用内存里的 zram
```

引导是两层：

```
UEFI 固件
   │
   ▼
rEFInd（顶层菜单）
   ├── Windows 11   →  Samsung 上的 bootmgfw.efi
   └── systemd-boot →  KIOXIA 上，管 NixOS 的全部 generation（回滚在这一层）
```

**两个系统各有自己的 ESP，谁也不碰谁的。** 两个 ESP 里各放一份 rEFInd：
日常走 NixOS 那份，Windows 更新抢回第一顺位时走 Windows 那份兜底。
道理见 [MIGRATION.md 6.5](MIGRATION.md)。

### 0.2 已经定下来的决定（不用再想）

| 决定 | 结论 |
|------|------|
| 谁装在哪块盘 | 大盘 KIOXIA 给 NixOS，Samsung 给 Windows |
| 装的顺序 | **先 Windows，后 NixOS** |
| swap | 不要磁盘 swap，不休眠，只用 zram |
| 内核 | **明确钉在 6.18 LTS**（`linuxPackages_6_18`），不用 latest，也不用不带版本号的默认。原因见 `hosts/asus/default.nix`：nixpkgs 里的 NVIDIA 驱动在 7.2 内核上编译不过。6.18 退役时怎么办见附录 D |
| Secure Boot | 保持关闭 |
| BitLocker / 设备加密 | 现在没开。**装完 Windows 要回头确认，见 7.3** |
| 键盘 | US |
| 浏览器 profile | 全丢，只装应用 |
| Syncthing | NixOS 服务，新建设备 ID，不沿用旧的 |
| 指纹 | 不配（Bluefin 上查不到指纹读头） |
| 装什么应用 | 见 `modules/`，Steam 用 `programs.steam`，Telegram 和 Chrome 两台机器都装 |

### 0.3 不可逆的点

**第 6.3 节里的 `clean`（清空 Samsung 的分区表）是第一个不可逆的点。**
做了之后，Bluefin 就起不来了（它的 `/boot` 和系统盘都在 Samsung 上）。

KIOXIA 上的数据要到第 9.2 节才会被抹掉。

**所以在做 6.3 之前，必须确认第 2 节的每一项都打了勾。**

### 0.4 大概要多久

只是量级，不是承诺：

| 阶段 | 大概 |
|------|------|
| 准备（第 2-5 节） | 1-2 小时，主要是下载和写 U 盘 |
| 装 Windows（第 6-7 节） | 1 小时左右，主要是 Windows 自己在装和更新 |
| 装 NixOS（第 8-9 节） | 首次 30 分钟到 1 小时以上。NVIDIA 内核模块要现场编译，看网速和 CPU |
| 装完之后的配置（第 10-12 节） | 1-2 小时 |

**建议留一整个下午或晚上，中途不要赶时间。** 引导这一块出错的代价大，急不得。

---

## 1. 这份指南没有在真机上走过

**诚实地说清楚验证到了哪里：**

| 部分 | 状态 |
|------|------|
| NixOS 的分区、安装、rEFInd | 在虚拟机里完整演练过，thinkpad 上 rEFInd 也实测过 |
| `hosts/asus/` 的配置 | 三个方向的构建都通过了（asus 系统层 + home 层、thinkpad 回归），**没有在 asus 硬件上跑过** |
| 双 ESP 的做法 | **只在虚拟机里验证过**，用的是假的 Windows ESP |
| diskpart 预建 Windows 分区 | 没试过。第 6.4 节给了退路 |
| Windows 那一侧的所有操作 | 没有验证过 |
| 华硕的启动菜单键、BIOS 键 | 只是「通常」是 Esc / F2，**没有查证** |

三件虚拟机验证不了的事，这次会第一次碰到：
**GOP 分辨率**（第 11.4 节）、**NTFS 脏状态**（第 7.2 节）、**硬件探测的值**（第 11.1 节）。

**遇到和文档对不上的地方，把实际输出记下来。**
这份文档就是靠这样一轮轮改对的，装完要按第 15 节回头更新它。

---

## 2. 动手前：检查清单

**每一项都要打勾。** 这是不可逆操作之前最后的关。

### 2.1 数据

- [ ] Bluefin 上的备份已经完成，放在外置硬盘上，范围是：
  - `~/Documents` 里的 `bruno`（含 Sample API Collection）、`Note.com`、
    `CRAFT-CRM 指示書`、`個人証明書`、`TORU-LEATHERS`、`ObsidianNote`
  - `~/Pictures`（约 65M）
  - `~/Videos` 里的 `Camera`、`AIGEN`（约 4.3G）
- [ ] **在另一台机器上**（比如 thinkpad）插上外置硬盘，抽查几个文件能真的打开
  （PDF、Obsidian 笔记、一张照片）。**「拷贝完成」不等于备份可用。**
- [ ] 确认下面这些是**故意不备份**的，没有漏：
  Homebrew、容器、开发环境、终端和编辑器配置、GNOME 扩展、代码、`~/.ssh`、
  Steam 库、Bottles、Wi-Fi 连接、MongoDB、Firefox / Zen / Brave / Chrome 的 profile、
  `.xwechat`、`xwechat_files`、`Shared` 里的 Game 和 Video、Henkel、
  BELLATECH 作業指示書、libvirt 里的虚拟机镜像
- [ ] Windows 一侧的数据 toru 自己备份过了

### 2.2 仓库

在 **thinkpad** 上：

- [ ] `git status` 是干净的，`git log origin/master..HEAD` 没有输出（都推上去了）
- [ ] `hosts/asus/` 已经在 GitHub 上：
  浏览器打开 `https://github.com/SenorToru/nixos-config/tree/master/hosts/asus` 能看到
- [ ] 跑一次 `state-sync push`，再 `git -C ~/dotfiles-state status`，
  确认 B 类状态是最新的（输入法学习记录等），并且已经推到远程
- [ ] 跑一次 `migration-check`，没有意外的漂移
- [ ] 把整个 `~/nixos-config` 再拷一份到**装机用的 U 盘**（第 3 节那个）里，
  万一装机时联网有问题，离线也能用

### 2.3 记下现在的状态（留作对照）

在 **Bluefin** 上，拍照或截图存到外置硬盘之外的地方（比如手机）：

- [ ] `lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS` 的输出
- [ ] `efibootmgr -v` 的输出
- [ ] 开机时进 BIOS 的按键和启动菜单的按键（**亲自按一次确认**，别只信「通常是 F2 / Esc」）

### 2.4 别的

- [ ] 笔记本**接着电源**，全程不能断电
- [ ] 手机可以用（USB 共享网络当备用，查文档也用）
- [ ] 有一台能上网、能看这份文档的**另一台设备**（thinkpad 或手机）。
  **安装期间 asus 自己没有桌面可以开文档。**
- [ ] 想清楚：接下来这几个小时，asus 上原来的东西**全部**没了

**全部打勾，再往下。**

---

## 3. 准备两个 U 盘

在 **thinkpad** 上做。需要两个 U 盘，**每个至少 8 GB**，里面的东西会被抹掉。

### 3.1 Windows 安装盘

**1. 下载 Windows 11 的 ISO**，官方地址：
`https://www.microsoft.com/software-download/windows11`
（选「下载 Windows 11 磁盘映像 (ISO)」）。

**2. 写盘。** Windows 的 ISO 不能像 NixOS 的那样直接 `dd`，
因为里面的 `install.wim` 通常超过 4GB，放不进 FAT32，而 UEFI 只认 FAT32。
三种办法，任选一个：

| 办法 | 在哪做 | 说明 |
|------|--------|------|
| **Rufus** 或微软官方的 **Media Creation Tool** | 任何一台 Windows 电脑 | 最省心，它们会自己处理 4GB 的问题 |
| `woeusb-ng` | thinkpad | `nix shell nixpkgs#woeusb-ng`，然后 `sudo woeusb --device <ISO文件> /dev/sdX`。**未验证过**，能用最好，不行换上一个 |
| Ventoy | 任何一台 | 装一次，之后直接把 ISO 拖进去，缺点是多一层 |

> 写盘之前先确认 U 盘是哪个设备，**写错设备 = 抹掉一块硬盘**：
> ```bash
> lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT
> ```
> 对着**型号和容量**认，不要靠 `sdb` 这种会变的名字。

- [ ] Windows 安装 U 盘做好了

### 3.2 NixOS 安装盘

**1. 下载 26.05 的 Graphical ISO**（约 3.9 GB，版本和 `flake.nix` 里的
`nixos-26.05` 对齐）。这个地址永远指向 26.05 分支上最新的一份：

```bash
curl -L -o nixos-graphical.iso \
  https://channels.nixos.org/nixos-26.05/latest-nixos-graphical-x86_64-linux.iso
```

> 为什么选 Graphical 不选 Minimal：这次要认盘、看分区，
> Graphical 自带 GParted 可以目视确认；联网也是点两下。
> 详细比较见 [MIGRATION.md 决策点 A](MIGRATION.md)。
>
> **ISO 自带的内核版本不重要。** 装好之后的内核由
> `hosts/asus/default.nix` 的 `boot.kernelPackages` 决定（钉在 6.18），
> 和 ISO 无关。ISO 的内核只影响安装那一小时里屏幕能不能正常显示，
> 出问题见 8.1 节的 `nomodeset`。

**2. 校验。别跳过，下载损坏在装到一半时才暴露最难受。**

上面那个地址会跳转到带具体版本号的文件，校验值在同一个地址后面加 `.sha256`：

```bash
curl -L https://channels.nixos.org/nixos-26.05/latest-nixos-graphical-x86_64-linux.iso.sha256
sha256sum nixos-graphical.iso
# 两个哈希逐位比对，必须完全一致。
# 注意 .sha256 里的文件名是带版本号的，和你本地的文件名不同，只比哈希那一串。
```

**3. 写盘。**

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT      # 认清 U 盘，再往下
sudo dd if=nixos-graphical.iso of=/dev/sdX bs=4M status=progress conv=fsync
#                                   ^^^^^^^^ 换成 U 盘本身（不带数字）
```

- [ ] NixOS 安装 U 盘做好了

**给两个 U 盘贴标签**（写在胶带上就行），别装机中途分不清。

---

## 4. 进 BIOS 检查设置

开机时按 BIOS 键（**通常是 `F2`**，你在 2.3 节确认过），进固件设置。
菜单名称因固件版本而异，下面写的是要找的东西，找不到一模一样的字眼时找意思相近的。

| 要检查的 | 应该是 | 为什么 |
|----------|--------|--------|
| 启动模式 | UEFI（不是 Legacy / CSM） | rEFInd、systemd-boot 都只走 UEFI |
| Secure Boot | **Disabled** | NixOS 和 rEFInd 都不签名，开着会被挡。Windows 11 装机只要求「支持」，关着通常也能装 |
| TPM / fTPM（AMD） | **Enabled** | Windows 11 要 TPM 2.0。AMD 平台叫 fTPM |
| Fast Boot | Disabled | 开着会跳过 USB 检测，U 盘启动不了 |
| BIOS 密码 | 记下有没有 | 有的话装机前要能解开 |

同时确认：**启动菜单键**（通常是 `Esc`）和你在 2.3 节记的一致。

- [ ] 以上设置确认过
- [ ] 保存并退出（`F10`）

---

## 5. 最后确认一次

- [ ] 第 2 节所有项目都是勾着的
- [ ] 两个 U 盘做好了、贴了标签
- [ ] 接着电源
- [ ] 手边有另一台能看这份文档的设备

**接下来是不可逆的。**

---

## 6. 装 Windows

### 6.1 从 U 盘启动

1. 插上 **Windows 安装 U 盘**。外置硬盘先拔掉，避免认错盘。
2. 开机，**连按启动菜单键**（通常是 `Esc`）。
3. 在菜单里选你的 U 盘（名字里通常带 `UEFI:`）。
4. 出现「Press any key to boot from CD or DVD」时按任意键。

进到 Windows 安装界面：选语言 → 「现在安装」→ 「我没有产品密钥」
→ 选版本（Home / Pro 都行，**装完自动激活，见 7.4**）→ 接受协议 →
**「自定义：仅安装 Windows（高级）」**。

**停在「你想将 Windows 安装在哪里？」这个界面。先不要点任何东西。**

### 6.2 认盘

这个界面会列出所有磁盘。asus 有两块：

| 盘 | 大小 | 现状 |
|----|------|------|
| Samsung 990 PRO | 约 1863 GB（界面里可能显示 `1.8 TB`） | 有 5 个分区，是 Bluefin 的 |
| KIOXIA | 约 3815 GB（`3.7 TB`） | 有 3 个分区，是 WinData / LinuxData / Shared |

**认盘靠大小。** Windows 里的「驱动器 0 / 驱动器 1」编号和 NixOS 里的
`nvme0n1` / `nvme1n1` 毫无关系，两边都可能对调。

**本步骤只动 Samsung（约 1863 GB 那块）。KIOXIA 一个分区都不要碰。**

### 6.3 用 diskpart 清盘并建分区

Windows 安装器默认只给 ESP 100MB 左右，我们要 1 GiB（原因是 Windows 更新
偶尔要往里放东西，太小会失败），所以自己建。

**在安装界面按 `Shift + F10`**，弹出一个命令提示符窗口。

```
diskpart
list disk
```

输出类似：

```
  Disk ###  Status         Size     Free     Dyn  Gpt
  --------  -------------  -------  -------  ---  ---
  Disk 0    Online         1863 GB  ....        *
  Disk 1    Online         3815 GB  ....        *
```

**找到 `1863 GB` 那一行的编号，下面叫它 N。** 如果两行你分不清，停下来，
不要猜。（分不清说明和文档描述的不一致，先弄清楚。）

```
select disk N
detail disk
```

**核对 `detail disk` 的输出里有 `Samsung SSD 990 PRO`。** 不是就 `exit` 重来。

> ### 下面这一步不可逆
>
> `clean` 会抹掉这块盘的全部分区表。做完 Bluefin 就没了。
> **确认过 N 是 Samsung 再执行。**

```
clean
convert gpt

create partition efi size=1024
format quick fs=fat32 label="SYSTEM"

create partition msr size=16

create partition primary size=880000
format quick fs=ntfs label="Windows"

create partition primary size=1024
format quick fs=ntfs label="Recovery"
set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
gpt attributes=0x8000000000000001

create partition primary size=1024000
format quick fs=ntfs label="share"

list partition
exit
```

说明：

- diskpart 里的 `size=` 单位是 **MB，实际等于 MiB**（1024 就是 1 GiB）。
- `880000` MiB ≈ 859 GiB，是 C: 的大小。
- `1024000` MiB = 1000 GiB，是共享盘。
- 三个数加起来（含 ESP、MSR、恢复分区）比整盘少约 1.6 GiB，那点余量是有意留的。
- 那个奇怪的 `set id` 是「Windows 恢复分区」的类型 GUID，
  `gpt attributes` 让 Windows 隐藏它并且不给盘符。

`list partition` 的输出应该有 5 行：

```
  Partition 1    System             1024 MB
  Partition 2    Reserved             16 MB
  Partition 3    Primary             859 GB
  Partition 4    Recovery           1024 MB
  Partition 5    Primary            1000 GB
```

- [ ] 五个分区都在，大小对得上

然后在命令提示符里：

```
exit
```

（回到安装界面。再 `exit` 一次会关掉命令提示符窗口，没关系。）

### 6.4 选安装位置

回到安装界面，点「刷新」。**你应该看到 Samsung 上有 5 个分区**：
「系统」、「MSR」、「主分区 859 GB」、「恢复」、「主分区 1000 GB」。

**选那个 859 GB 的分区**（不是 1000 GB 的，不是 KIOXIA 上的任何分区），点「下一步」。

> **如果安装器拒绝，或者报「无法在此驱动器上安装」：**
> 这说明它不接受预建的分区。退路是：
> `Shift+F10` → `diskpart` → `select disk N` → `clean` → `convert gpt` → `exit`，
> 然后回到安装界面，选那块盘的「未分配空间」，点「新建」，
> **在「大小」里填 `880000`**，让安装器自己划 ESP、MSR、C: 和恢复分区。
> 装完再回 Windows 的「磁盘管理」，把剩下的未分配空间建成一个 1000 GiB 的
> NTFS 分区，卷标 `share`。
> **这种情况下 ESP 会比 1 GiB 小，卷标也不是 `SYSTEM`。** 到了 9.7 节，
> `blkid -L SYSTEM` 会找不到它，按那里的说明用 `fatlabel` 补一个卷标就行。

### 6.5 等 Windows 装完，跑完首次设置

1. 安装过程会重启几次。**重启到「Press any key to boot from CD」时不要按键**，
   让它从硬盘走。或者干脆此时拔掉 U 盘。
2. 首次设置里问账户：
   - 想用微软账户就登录。
   - 想跳过（本地账户）的话，具体做法**随 Windows 版本变**，
     查一下当前可用的方法。不影响本文其它部分。
3. 到桌面之后，**先让 Windows 联网并跑一遍 Windows Update**，
   更新驱动（含 Wi-Fi 和显卡）。可能需要重启多次。

> 如果这时没有网络：Windows 里的 Wi-Fi 网卡是 Realtek RTL8852CE，
> 系统通常自带驱动。没有的话，事先在 thinkpad 上从华硕官网下载
> 这个机型的 Wi-Fi 驱动放在 U 盘里，装上再联网。

> **ESP 的卷标要叫 `SYSTEM`**，rEFInd 靠它找到 Windows 的引导文件。
> 6.3 里的 `format ... label="SYSTEM"` 已经设了。Windows 在 Windows 里看不见
> ESP（没有盘符），所以**这里不验证**，等到 NixOS 安装环境里
> 用 `blkid -L SYSTEM` 验证（9.7 节）。卷标不对也不用回 Windows，
> 在 NixOS 里一条 `fatlabel` 就能改。

- [ ] Windows 能进桌面、能联网

---

## 7. Windows 装完后必须做的事

**这一节在装 NixOS 之前完成。** 特别是 7.1 和 7.2，
不做的话共享盘迟早会出问题。

### 7.1 关闭快速启动

「控制面板」→「电源选项」→「选择电源按钮的功能」→
点「更改当前不可用的设置」→ **取消勾选「启用快速启动」** → 保存修改。

### 7.2 关闭休眠

**管理员**身份打开 PowerShell（开始菜单搜 PowerShell，右键「以管理员身份运行」）：

```powershell
powercfg /h off
```

> **为什么这两条是死规定：** 快速启动和休眠都会让 Windows 关机时
> **不真正卸载文件系统**，NTFS 停在「脏」状态。之后 NixOS 侧的共享盘
> 要么只读挂载，要么强写导致文件损坏。这是 NTFS 双系统共享盘
> **最常见的翻车方式**，和用哪个 Linux 驱动无关。

### 7.3 检查 BitLocker / 设备加密

**为什么要查：** Windows 11 有的版本在登录微软账户后会**自动**打开设备加密。
一旦打开，以后改启动顺序、改固件设置都可能弹「请输入恢复密钥」，
恢复密钥又存在微软账户里，麻烦。

「设置」→「隐私和安全性」→「设备加密」。

- 显示**关闭**：什么都不用做。
- 显示**开启**：
  1. 先确认恢复密钥能在 `https://account.microsoft.com/devices/recoverykey` 查到；
  2. 想省事就关掉它（点「关闭」，等它解密完成）。

管理员 PowerShell 里也能查：

```powershell
manage-bde -status
```

看 `C:` 的 `Protection Status` 是 `Protection Off`。

### 7.4 确认激活

「设置」→「系统」→「激活」。原来的 Windows 是数字许可证的话，
联网后会自动激活。**不用管产品密钥。**

### 7.5 让 Windows 用 UTC 时间

**双系统的经典毛病：** Windows 把硬件时钟当**本地时间**，Linux 当 **UTC**。
装完之后你在一个系统里对好时间，进另一个系统就差 9 个小时（日本是 UTC+9）。

**办法是让 Windows 也用 UTC。** 管理员命令提示符（`cmd`）：

```
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

然后重启一次，再到「设置」→「时间和语言」里打开「自动设置时间」，让它重新对时。

> 另一个办法是在 NixOS 里设 `time.hardwareClockInLocalTime = true`。
> **不推荐** —— 那会让 NixOS 这一侧偏离标准做法，而且夏令时地区会更乱。
> 日本不用夏令时，两种办法都行，选了 Windows 这个就不要再动 NixOS 那边。
>
> 这一条**没在 asus 上验证过**。装完 NixOS 之后（第 13 节）会验证。

### 7.6 最后关机

**「关机」，不是「重启」。** 然后拔掉 Windows U 盘。

- [ ] 快速启动已关
- [ ] 休眠已关（`powercfg /h off`）
- [ ] 设备加密是关的或恢复密钥已确认
- [ ] 时间设成 UTC
- [ ] Windows 已关机（不是休眠）

---

## 8. 启动 NixOS 安装盘并联网

### 8.1 启动

1. 插上 **NixOS 安装 U 盘**。**外置硬盘仍然拔着。**
2. 开机，连按启动菜单键（`Esc`），选 U 盘。
3. NixOS 的启动菜单出现后，选默认的那一项，回车。

进到 GNOME 桌面（自动以 `nixos` 用户登录）。

> **如果屏幕黑了或者花了：** 独显 RTX 5060 是很新的卡，安装盘里的
> 开源驱动不一定支持。重启，在启动菜单里选带 `safe graphics` 之类字样的项；
> 没有的话，在默认项上按 `e`，在内核参数行末尾加一个空格和 `nomodeset`，
> 再按 `Ctrl+X` 或 `F10` 启动。这只影响安装环境，不影响装好的系统。

### 8.2 联网

右上角状态菜单 → 选 Wi-Fi → 连接你的网络。

> 装机需要下载几个 GB，**有线更稳**。有 USB 网线转接头就用。
> 手机 USB 共享网络也可以，插上就出现有线连接。

如果 Wi-Fi 列表是空的：RTL8852CE 的固件在安装盘里，通常没问题；
空的话先用手机 USB 共享网络顶上。

打开 **Console**（终端），拿 root 权限：

```bash
sudo -i
ping -c3 nixos.org
```

- [ ] `ping` 通

> **接下来所有命令都要 root。** 换终端窗口、SSH 断线重连都会回到普通用户，
> 到时候再 `sudo -i`。

---

## 9. 给 KIOXIA 分区并装 NixOS

### 9.1 认盘 —— 用 by-id，不用 nvme0n1

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL
```

你应该看到：

```
NAME        SIZE  MODEL                   FSTYPE  LABEL
nvme0n1     1.8T  Samsung SSD 990 PRO ..
├─nvme0n1p1 1G                            vfat    SYSTEM
├─nvme0n1p2 16M
├─nvme0n1p3 859G                          ntfs    Windows
├─nvme0n1p4 1G                            ntfs    Recovery
└─nvme0n1p5 1000G                         ntfs    share
nvme1n1     3.7T  KIOXIA KXG80ZN84T09 ..
├─nvme1n1p1 1.5T                          ntfs    WinData
├─nvme1n1p2 1.5T                          ext4    LinuxData
└─nvme1n1p3 815G                          exfat   Shared
```

**`nvme0n1` 和 `nvme1n1` 哪个是 Samsung 哪个是 KIOXIA，这次可能和上面写的对调。**
以 `MODEL` 那一列为准。

为了不受编号影响，后面的命令全部用 **by-id 路径**：

```bash
ls -l /dev/disk/by-id/ | grep -E 'KIOXIA|Samsung' | grep -v part
```

会看到形如 `nvme-KIOXIA_KXG80ZN84T09_<序列号>` 的链接。把 KIOXIA 那个记进变量：

```bash
DISK=/dev/disk/by-id/nvme-KIOXIA_KXG80ZN84T09_<换成你看到的序列号>
lsblk $DISK
```

**核对 `lsblk $DISK` 输出的大小是 3.7T，型号是 KIOXIA。** 对不上就停。

> ### 从这里开始，KIOXIA 上的全部数据会被抹掉
>
> 你在 2.1 节确认过备份了。KIOXIA 上的 WinData、LinuxData、Shared 都没了。

### 9.2 分区

```bash
# 先把旧的文件系统签名擦掉，避免 mkfs 之后 blkid 认出重叠的残留
for p in ${DISK}-part*; do wipefs -a "$p"; done
wipefs -a "$DISK"

parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart ESP fat32 1MiB 2GiB
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart root btrfs 2GiB 100%

udevadm settle
lsblk "$DISK"
```

`lsblk` 应该看到两个分区：约 2G 的 `part1` 和约 3.7T 的 `part2`。

- [ ] 两个分区，大小对得上

> **ESP 为什么 2 GiB：** 每换一次内核，systemd-boot 就要在 ESP 里多存一份
> 约 50-60 MiB 的 kernel + initrd。1 GiB 撑不了几轮。
> 这里没有 swap 分区（决定过不休眠），所以 root 从 2 GiB 直接开始。

### 9.3 格式化

```bash
mkfs.fat -F 32 -n BOOT ${DISK}-part1
mkfs.btrfs -f -L nixos ${DISK}-part2
```

（`-f` 是因为旧分区的位置上可能还有别的文件系统痕迹，不加它 `mkfs.btrfs` 会拒绝。）

### 9.4 建子卷并挂载

```bash
mount ${DISK}-part2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@snapshots
umount /mnt
```

```bash
OPTS=compress=zstd:1,noatime

mount -o subvol=@,$OPTS          ${DISK}-part2 /mnt
mkdir -p /mnt/{home,nix,.snapshots,boot}
mount -o subvol=@home,$OPTS      ${DISK}-part2 /mnt/home
mount -o subvol=@nix,$OPTS       ${DISK}-part2 /mnt/nix
mount -o subvol=@snapshots,$OPTS ${DISK}-part2 /mnt/.snapshots
mount -o umask=0077              ${DISK}-part1 /mnt/boot
```

确认：

```bash
findmnt -R /mnt
```

- [ ] 四个 btrfs 子卷都在，`/mnt/boot` 是 vfat，选项里有 `compress=zstd:1`

> 这里挂载用的选项**只影响安装过程本身**。装好之后持久生效的那份写在
> `hosts/asus/tuning.nix`（`nixos-generate-config` 不记 `compress` 和 `noatime`）。
> 背景见 [MIGRATION.md 决策点 C](MIGRATION.md)。

### 9.5 生成硬件配置

```bash
nixos-generate-config --root /mnt
cat /mnt/etc/nixos/hardware-configuration.nix
```

看一眼：

- `fileSystems."/"` 的 `options` 里有 `subvol=@`
- `fileSystems."/boot"` 是 `vfat`，有 `fmask=0077`、`dmask=0077`
- 有 `boot.kernelModules = [ "kvm-amd" ]`
- **没有** swap 相关条目（`swapDevices = [ ]`）

生成了两个文件，**只用其中一个**：

| 文件 | 处理 |
|------|------|
| `/mnt/etc/nixos/hardware-configuration.nix` | **要**。下一步拷进仓库 |
| `/mnt/etc/nixos/configuration.nix` | **不要**。仓库的 `hosts/asus/default.nix` 取代它 |

### 9.6 把仓库接进来

```bash
nix-shell -p git --run '
  git clone https://github.com/SenorToru/nixos-config /mnt/home/toru/nixos-config
'
cd /mnt/home/toru/nixos-config
ls hosts/asus/
```

应该有 `default.nix hardware-configuration.nix hwinfo.nix tuning.nix`。

> 联网有问题的话，用 2.2 节拷进 U 盘里的副本：
> 挂上 U 盘，`cp -a <U盘>/nixos-config /mnt/home/toru/`。

**用刚生成的真的硬件配置覆盖仓库里的占位：**

```bash
cp /mnt/etc/nixos/hardware-configuration.nix hosts/asus/hardware-configuration.nix
```

> ISO 里全程是 root，所以这些文件的属主都是 root。
> **9.9 的 `chown` 会一次性修好**，别提前做 ——
> `nixos-install` 读 dirty 工作树时还可能往 `.git/objects` 里写东西。
> 背景见 [Lesson-Learn/0011](Lesson-Learn/0011_ROOT_OWNED_FILES_IN_REPO.md)。

### 9.7 填 tuning.nix 里的两个占位

`hosts/asus/tuning.nix` 里有两个占位值，**不换的话 Windows 的 ESP 和共享盘
装完都挂不上**，而且是静默失败：

```bash
# 查两个 UUID。-L 按文件系统卷标找，不依赖盘符或编号
blkid -L SYSTEM
blkid -L share

WINESP=$(blkid -s UUID -o value "$(blkid -L SYSTEM)")
SHARE=$(blkid -s UUID -o value "$(blkid -L share)")
echo "winesp = $WINESP"
echo "share  = $SHARE"
```

- `WINESP` 应该是 8 位短格式，形如 `1D5C-9F1B`
- `SHARE` 应该是 16 位十六进制，形如 `1A2B3C4D5E6F7A8B`

**`blkid -L SYSTEM` 找不到东西**：说明 Windows 的 ESP 没有 `SYSTEM` 卷标
（走了 6.4 的退路，或者被改过）。找到它，补一个卷标，然后重跑上面的命令：

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPE     # 找 Samsung 上那个 vfat 的小分区
fatlabel /dev/<那个分区，如 nvme0n1p1> SYSTEM
```

**`blkid -L share` 找不到**：共享盘没有 `share` 卷标。同理用
`ntfslabel /dev/<分区> share`（需要先 `nix-shell -p ntfs3g`）。

两个 UUID 变量是空的也一样：多半是上面没找到设备。

```bash
sed -i "s|winEspUuid = \"0000-0000\"|winEspUuid = \"$WINESP\"|" hosts/asus/tuning.nix
sed -i "s|shareUuid = \"0000000000000000\"|shareUuid = \"$SHARE\"|" hosts/asus/tuning.nix
grep -nE 'winEspUuid =|shareUuid =' hosts/asus/tuning.nix
```

- [ ] 输出里两个值都不再是全零

### 9.8 安装

```bash
nixos-install --flake /mnt/home/toru/nixos-config#asus
```

**第一次会很久。** 要下载并构建整棵依赖树，里面有 NVIDIA 开源内核模块（现场编译）、
Steam、Chrome、GNOME 全套。

- 过程中会有很多 `building` 和 `copying path` 的输出，正常。
- 结束时会提示设置 **root 密码**，设一个。
- **如果卡在某个包上超过十几分钟没有输出**，用另一个终端窗口 `top` 看看
  是不是在编译，是的话耐心等。
- 报错的话，把错误最后 30 行记下来。

> **别在构建期间合上盖子或让它睡眠。**

### 9.9 装完、重启之前：四件事

**一、设用户密码。** 仓库里 `users.users.toru` 没有密码字段，
刚装完是**锁定账户**，GDM 登不进去：

```bash
nixos-enter --root /mnt -c 'passwd toru'
```

**二、确认引导文件都在。** `canTouchEfiVariables = false` 的意思是
NixOS **不会**往固件里写启动项，只往 ESP 里放文件：

```bash
ls /mnt/boot/EFI/
ls /mnt/boot/EFI/systemd/ /mnt/boot/EFI/BOOT/
```

应该有 `systemd` 和 `BOOT` 两个目录，里面有 `systemd-bootx64.efi` 和 `BOOTX64.EFI`。

**三、手动建一条 `Linux Boot Manager` 启动项 —— 这是安全网。**

因为上面说的原因，固件里现在**没有**指向 NixOS 的启动项，
而 Windows 已经占着第一位。手动补一条：

```bash
nix-shell -p efibootmgr --run "
  efibootmgr --create \
    --disk $(readlink -f $DISK) --part 1 \
    --loader '\\EFI\\systemd\\systemd-bootx64.efi' \
    --label 'Linux Boot Manager'
"
```

输出里应该能看到新的 `Boot0004* Linux Boot Manager`（编号可能不同），
并且它在 `BootOrder` 的最前面。这样重启后直接进 systemd-boot → NixOS。

> **这一条是之后整个引导体系的退路**：rEFInd 出任何问题，
> 开机按启动菜单键选它，照样进系统。见 [MIGRATION.md 6.2](MIGRATION.md)。

**四、修属主并重启：**

```bash
# 仓库是以 root 身份放进去的，改回 toru（uid 1000 / gid 100）
chown -R 1000:100 /mnt/home/toru

umount -R /mnt
reboot
```

**重启时拔掉 NixOS U 盘。**

---

## 10. 第一次进 NixOS

### 10.1 登录

重启后：

- 应该先看到 systemd-boot 的菜单（列着 NixOS 的 generation），几秒后自动进第一项。
  **这时还没有 rEFInd，是对的。**
- 然后是 GDM 登录界面。用 `toru` 和你在 9.9 设的密码登录。

进不了系统的话，看第 14 节。

### 10.2 联网

右上角连 Wi-Fi。

> 仓库里的 DNS 是 DoT 严格模式（[Lesson-Learn/0014](Lesson-Learn/0014_DNS_HIJACK_AND_DOT.md)），
> 连上了但解析不了的话，先看是不是被路由器/热点挡了 853 端口。

### 10.3 验证系统层（构建通过不等于可用）

```bash
hostnamectl                                   # Static hostname: asus
nixos-rebuild list-generations | head -3      # 有 generation
findmnt -t btrfs -o TARGET,OPTIONS            # 4 个子卷，选项含 compress=zstd:1
swapon --show                                 # 只有 zram，没有磁盘 swap
sysctl vm.swappiness                          # 180
findmnt /mnt/winesp /mnt/share                # 两个都挂上了
```

**`findmnt /mnt/winesp /mnt/share` 没输出**：`nofail` 让它静默失败了。
看 `tuning.nix` 里的 UUID 对不对，`sudo blkid` 对照一遍。

**`/mnt/share` 是只读或挂不上**：Windows 那侧的快速启动或休眠没关干净，
NTFS 是脏的。回 Windows 里做 7.1 和 7.2，**然后关机（不是重启）**，再回 NixOS。

```bash
touch /mnt/share/nixos-test && rm /mnt/share/nixos-test && echo "共享盘可写"
```

### 10.4 验证显卡

```bash
nvidia-smi                                    # 应该看到 RTX 5060 Laptop，驱动版本
lspci -k | grep -EA3 'VGA|3D'                 # 核显用 amdgpu，独显用 nvidia
```

再确认 **PRIME offload** 真的在工作（默认是核显出图，独显只在被点名时启动）：

```bash
nix shell nixpkgs#mesa-demos -c glxinfo -B | grep -i 'renderer'
# 应该是 AMD Radeon ... 核显

nix shell nixpkgs#mesa-demos -c nvidia-offload glxinfo -B | grep -i 'renderer'
# 应该是 NVIDIA GeForce RTX 5060 ...
```

**两条输出是同一块卡**（都是 AMD，或 offload 那条也不是 NVIDIA）就是配错了，
检查 `hosts/asus/tuning.nix` 的 `amdgpuBusId` / `nvidiaBusId`：

```bash
lspci -D | grep -E 'VGA|3D'
# 0000:66:00.0 → PCI:102:0:0    （0x66 = 102）
# 0000:64:00.0 → PCI:100:0:0    （0x64 = 100）
```

**总线号是十六进制转十进制**，抄错了 Wayland 找不到设备。

### 10.5 验证桌面与输入

- [ ] GNOME 桌面正常，字体不是丑的回退字体：`fc-match "Sarasa Mono J"`
- [ ] `echo $SHELL` 是 zsh
- [ ] 外接鼠标：滚轮方向是自然滚动，指针无加速
- [ ] **内置触摸板是禁用的**（这台机器的既定设置，见 `home/desktop-prefs.nix`）
- [ ] `Ctrl+Alt+T` 和 `Ctrl+Alt+Return` 都能开出 Ghostty
- [ ] 输入法：中文（白霜拼音）和日文（mozc）都能打

### 10.6 验证应用

- [ ] Steam 能启动，能登录（游戏库不搬，重新下载）
- [ ] Google Chrome 能启动
- [ ] Telegram 能启动
- [ ] `claude --version` 有输出

---

## 11. 装 rEFInd（两个 ESP）

配置里已经开了 `custom.refind`，所以 `refind-hwinfo` 和 `refind-sync`
这两个命令**第一次 `nixos-install` 之后就已经在 PATH 上**，
不需要像 [MIGRATION.md 9.3](MIGRATION.md) 那样先 `nrb` 两次。

### 11.1 探测硬件

进仓库，跑探测：

```bash
cd ~/nixos-config
sudo refind-hwinfo
```

**跑完先修属主**（sudo 往仓库里写了文件，这是仓库的老坑）：

```bash
sudo chown toru:users hosts/asus/hwinfo.nix
find . ! -user toru -printf '%u  %p\n'      # 应该没有输出
```

看一眼生成的内容对不对：

```bash
git diff hosts/asus/hwinfo.nix
```

应该是 AMD Ryzen AI 7 H 350、Radeon / RTX 5060、内存约 30G、Samsung 或 KIOXIA
的磁盘那几行。**探测错了可以直接改这个文件**，它不在开机路径上，
错了只是启动画面上一行字不对。

### 11.2 重建并写进两个 ESP

```bash
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
nix build .#nixosConfigurations.asus.config.system.build.toplevel --out-link /tmp/res
sudo nixos-rebuild switch --flake /home/toru/nixos-config#asus
sudo refind-sync
```

（中间那条不用 sudo 的 `nix build` 不能省：它先以 toru 的身份把 `flake.lock`
之类写好，免得 root 往仓库里写东西，见 CLAUDE.md 的坑 5。）

`refind-sync` 的输出里会看到对 `/boot` 和 `/mnt/winesp` 各写一次，
最后列出 NVRAM。确认两个 ESP 都写到了：

```bash
sudo ls /boot/EFI/refind/
sudo ls /mnt/winesp/EFI/refind/
```

**第二条报「没有那个文件或目录」**：`/mnt/winesp` 没挂上（10.3 已经验过），
回去查 UUID。

```bash
nix shell nixpkgs#efibootmgr -c efibootmgr
```

- [ ] `rEFInd` 在 `BootOrder` 第一位
- [ ] `Linux Boot Manager` 还在（那是安全网，**不要删**）

### 11.3 重启，看菜单

**重启，别关机。** 应该看到 rEFInd 菜单：

- [ ] 背景是 finn-term 主题，左上角是 asus 的硬件信息
- [ ] 有 **NixOS** 图标，**不是**一个约 32×32 的黄黑斜条小方块
  （那是 rEFInd 内置的「图片加载失败」占位符，说明 `icon` 路径错了，
  见 [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md) 坑 1）
- [ ] 有 **Windows 11** 图标，同样不是黄黑方块
- [ ] 选 NixOS，能进系统
- [ ] 选 Windows，能进 Windows

**Windows 这一项进不去：** 最常见的原因是 `volume SYSTEM` 找不到卷 ——
回到 NixOS 用 `sudo blkid -L SYSTEM` 确认卷标就是 `SYSTEM`。

### 11.4 校准分辨率

**这一步在每台新机器上都必须做。** `hosts/asus/default.nix` 里现在填的
1920×1080 只是占位。rEFInd 的分辨率只能从**固件 GOP 实际提供的模式**里挑，
写了固件没有的值，背景图会被拉伸或平铺。thinkpad 就是这么踩过的：
固件压根不提供 1080p。

流程：

1. 把 `hosts/asus/default.nix` 里 `custom.refind.resolution` 临时改成一个
   明显无效的值：`width = 1; height = 1;`
2. `sudo nixos-rebuild switch --flake /home/toru/nixos-config#asus`，
   然后 `sudo refind-sync`，重启。
3. rEFInd 启动时会**列出固件支持的全部模式**。拍照或抄下来。
4. 挑面板原生的那一个（通常是 Mode 0）。这台的面板原生多半是
   2880×1800 或 1920×1200，**以固件实际列出的为准，别想当然**。
5. 改回 `default.nix`，重新 `nrb`（`sudo nixos-rebuild switch ...`），
   `sudo refind-sync`，重启。
6. 验证：在 rEFInd 界面按 `F10` 截图，会往 ESP 根目录写一张 BMP，
   `文件大小 = 宽 × 高 × 3 + 54`，反推就知道实际分辨率。看完删掉：
   `sudo rm -f /boot/screenshot_*.bmp`

详细背景见 [MIGRATION.md 6.4](MIGRATION.md)。

- [ ] 画面填满屏幕，没有被拉伸或平铺

### 11.5 Windows 侧的兜底

**这一步在 Windows 里做。** 从 rEFInd 选 Windows 进去，管理员 PowerShell：

```powershell
bcdedit /set {bootmgr} path \EFI\refind\refind_x64.efi
```

这条让 Windows 自己的引导入口也指向 Windows 那个 ESP 里的 rEFInd。
Windows 的功能更新会擅自把 UEFI 启动顺序第一位重置成 `Windows Boot Manager`，
有了这条，它抢回第一顺位也没用，开机照样先进 rEFInd。

**改完重启一次，确认 Windows 的引导没坏：**

- [ ] 重启后仍然先出 rEFInd 菜单
- [ ] 从菜单选 Windows 仍能进

### 11.6 清掉固件里的死启动项

Bluefin 时代留下的启动项现在指向的文件都不存在了。
回到 NixOS：

```bash
nix shell nixpkgs#efibootmgr -c efibootmgr -v
```

**逐条看**，找这些：

- 名字叫 `Fedora` 的
- 名字叫 `Windows Boot Manager`，但设备路径里的分区 GUID 是 `72ed08b5-e2b2-4332-a2bc-1840a09e8f59` 的
  （那是**旧的** Samsung ESP，现在已经不存在了）

删除（**一条一条跑，不要用 `&&` 串，`<号码>` 是四位十六进制，如 `0005`**）：

```bash
sudo nix shell nixpkgs#efibootmgr -c efibootmgr -b <号码> -B
```

**不要删的：**

- `rEFInd`
- `Linux Boot Manager`（安全网）
- 当前 Windows 的 `Windows Boot Manager`（分区 GUID 和现在 Samsung 的 ESP 对得上）

> **拿不准就别删。** 死启动项只是让固件的启动菜单里多几行、开机慢几秒，
> 不会出事。删错了才会出事。

---

## 12. 装完之后的配置

### 12.1 SSH 密钥、GitHub、提交签名

**顺序有意义。** 仓库配了 `commit.gpgsign = true`（用 SSH 密钥签提交），
密钥不存在时 `git commit` 会**直接失败**，所以密钥排第一。

```bash
ssh-keygen -t ed25519 -C "asus"
cat ~/.ssh/id_ed25519.pub
```

**这把公钥在 GitHub 上要登记两次**（Settings → SSH and GPG keys → New SSH key）：

| 登记成 | 干什么用 | 不登记的症状 |
|--------|----------|--------------|
| **Authentication key** | `git push` / `git clone` | 推不上去，`Permission denied (publickey)` |
| **Signing key** | 提交显示 Verified 徽章 | 能推，但显示 Unverified |

然后把公钥加进 `home/toru.nix` 开头的 `signingKeys`，键名用 `asus`
（值是**裸公钥**，只要「类型 + base64」，不要末尾的 `asus` 注释）：

```nix
    asus = "ssh-ed25519 AAAA...";
```

```bash
cd ~/nixos-config
git remote set-url origin git@github.com:SenorToru/nixos-config.git
gh auth login
```

验证：

```bash
ssh -T git@github.com                          # Hi SenorToru! ...
```

细节见 [MIGRATION.md 7.3](MIGRATION.md)。

### 12.2 提交这台机器自己的东西

装机过程中改了几个文件，需要提交：

| 文件 | 改了什么 |
|------|----------|
| `hosts/asus/hardware-configuration.nix` | 从占位换成真的 |
| `hosts/asus/hwinfo.nix` | 从占位换成探测结果 |
| `hosts/asus/tuning.nix` | 两个 UUID |
| `hosts/asus/default.nix` | rEFInd 分辨率 |
| `home/toru.nix` | `signingKeys` 加了 `asus` |

```bash
cd ~/nixos-config
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
sudo nixos-rebuild switch --flake /home/toru/nixos-config#asus
```

准备 `GIT_COMMIT_MESSAGE.txt`（纯文本，不写 Markdown，不用 emoji，不写署名尾注）：

```bash
git add -A && git commit -F GIT_COMMIT_MESSAGE.txt
git push
```

推送后，**thinkpad 上要 `git pull` 再 `nrb` 一次**才认得 asus 签的提交。
见 [MIGRATION.md 7.3](MIGRATION.md) 里那段不对称的说明。

### 12.3 其它登录

```bash
claude          # 首次启动会引导登录
```

- [ ] Steam、Telegram、Chrome、Proton Pass 等按需登录。
  这些都是 C 类，不搬。

### 12.4 还原 B 类状态

```bash
git clone git@github.com:SenorToru/dotfiles-state ~/dotfiles-state
state-sync restore
rm -rf ~/.local/share/fcitx5/rime/build       # 如果 restore 误带了
migration-check
```

细节见 [MIGRATION.md 7.1、7.2](MIGRATION.md)。

### 12.5 放回备份的文件

**外置硬盘现在可以插上了。** 按 `~/Documents/library/00 怎么放文件.md`
（thinkpad 上有，Syncthing 配对后这台也会有）的规矩归位：

| 备份里的 | 放到 |
|----------|------|
| `ObsidianNote` | `~/Documents/notes`（文件夹里的内容，不要多套一层） |
| `TORU-LEATHERS`、`CRAFT-CRM 指示書`、`個人証明書`、`Note.com` | 先放进 `~/Documents/library` 对应的编号文件夹里，编号怎么定见那份规矩；**拿不准就先放临时位置，别乱放** |
| `bruno` | 集合是项目目录里的普通文件，跟着项目走 |
| `Pictures` | `~/Pictures/library/年/月` |
| `Videos/Camera`、`Videos/AIGEN` | `~/Videos/年` |

> Obsidian 的库先放进 `~/Documents/notes`，**再**和其他机器配对 Syncthing。
> 同一个库不要再开 Obsidian 官方的 Sync。

### 12.6 Syncthing 配对

Syncthing 服务已经在跑（`home/syncthing.nix`）。六个文件夹（笔记、档案、
保险箱、照片、音乐、视频）已经声明好了，但**设备要手动配对**：

1. 打开 `http://127.0.0.1:8384/`。
2. 「添加远程设备」→ 填 thinkpad 的设备 ID
   （在 thinkpad 的网页界面 → 操作 → 显示 ID）。
3. 在 thinkpad 上会弹出请求，接受。
4. 六个文件夹分别勾选和 thinkpad 共享。

**这台是新设备，生成新的设备 ID，不沿用 Bluefin 上的。**

之后按规矩里「以后只有 Asus 能改保险箱」一节，把 thinkpad 和 Mac 上的
「保险箱」文件夹改成「仅接收」。详细步骤在
`~/Documents/library/00 怎么放文件.md` 的最后一节。

### 12.7 保险箱（Cryptomator）

Syncthing 把 `~/Documents/secrets/钥匙/` 同步过来之后，按同一份规矩的
「在另一台电脑上打开」一节做：

1. 空目录 `~/Secrets` 先建好。
2. Cryptomator → 打开已有保险箱 → 选 `masterkey.cryptomator`。
3. 用 Proton Pass 里的密码解锁。
4. 挂载路径设成 `~/Secrets`。

---

## 13. 验证清单（构建通过不等于可用）

```bash
# 系统身份
hostnamectl
nixos-rebuild list-generations | head -3

# 文件系统与 swap
findmnt -t btrfs -o TARGET,OPTIONS
swapon --show                                # 只有 zram
findmnt /mnt/winesp /mnt/share

# 显卡
nvidia-smi
nix shell nixpkgs#mesa-demos -c nvidia-offload glxinfo -B | grep -i renderer

# 字体与 shell
fc-match "Sarasa Mono J"
echo $SHELL

# 服务
systemctl is-active fwupd
systemctl --failed                           # 0 loaded units listed

# DNS（modules/dns.nix）
resolvectl status                            # 每个 Link 段没有 DNS Servers: 那一行
nix shell nixpkgs#dnsutils -c dig +time=3 +tries=1 A example.org @192.0.2.1
                                             # 必须超时

# 引导
sudo ls /boot/EFI/refind/ /mnt/winesp/EFI/refind/
nix shell nixpkgs#efibootmgr -c efibootmgr   # rEFInd 第一，Linux Boot Manager 还在

# 仓库属主
cd ~/nixos-config && find . ! -user toru -printf '%u  %p\n'   # 无输出
```

**双系统专项：**

- [ ] 在 NixOS 里对好时间，进 Windows，时间是对的
- [ ] 在 Windows 里往共享盘（`share`）写一个文件，进 NixOS 能看到、能读
- [ ] 在 NixOS 里往 `/mnt/share` 写一个文件，进 Windows 能看到
- [ ] 每次从 Windows 关机后进 NixOS，`/mnt/share` 都是可写的（不是只读）
- [ ] 在 Windows 里跑一次 Windows Update 并重启后，开机**仍然先出 rEFInd**
  （Windows 大版本更新会抢启动顺序，11.5 的 `bcdedit` 就是防这个）

最后：**重启一次，确认菜单出现、两个系统都能选、分辨率正常。**

---

## 14. 出问题了

按代价从小到大：

| 症状 | 怎么办 |
|------|--------|
| rEFInd 起来了但找不到 NixOS | 在 rEFInd 里按 `Esc` 让它重新扫描。还没有的话，看 `refind.conf` 的 NixOS 条目路径是不是 `\EFI\systemd\systemd-bootx64.efi` |
| rEFInd 本身起不来 / 黑屏 | 开机按**启动菜单键**（`Esc`），选 `Linux Boot Manager`，直接走 systemd-boot |
| 启动菜单里也没有 `Linux Boot Manager` | 固件会退到通用设备项，走 UEFI 回退路径 `\EFI\BOOT\BOOTX64.EFI`，那也是 systemd-boot。启动菜单里选 `KIOXIA` 那一项 |
| 系统起来了但配置坏了 | `sudo nixos-rebuild switch --rollback`，或者在 systemd-boot 菜单里选上一个 generation |
| Windows 更新后开机直接进了 Windows | Windows 抢回了第一顺位。进 NixOS 后 `sudo refind-sync` 重建 NVRAM 项；再确认 11.5 的 `bcdedit` 还在 |
| 从 Windows 关机后，NixOS 里 `/mnt/share` 只读 | 快速启动或休眠又被打开了（Windows 更新有时会重置）。回 Windows 重做 7.1、7.2，然后**关机而不是重启** |
| 时间差 9 小时 | 7.5 的注册表项没生效或被重置了 |
| `nixos-install` 失败 | 记下最后 30 行输出。已知一个：NVIDIA 驱动在新内核上编译失败（`hosts/asus/default.nix` 已经钉在 6.18 避开了，如果有人改回 `linuxPackages_latest` 会复现） |
| 黑屏、进不了 GDM | 开机在 systemd-boot 菜单里选上一个 generation；实在不行按 `Ctrl+Alt+F2` 切 TTY 登录排查 |
| 以上全失败 | 用 NixOS 安装 U 盘启动，`mount` 好分区后 `nixos-enter --root /mnt` 修 |

> **动手改引导之前，先确认启动菜单键是哪个，而且亲自按过一次。**
> 这件事要在改 `canTouchEfiVariables` 之前就验证过（2.3 节做过）。

---

## 15. 收尾：回头改文档和仓库

**装完之后必须做，这份指南是靠这个变准的。**

- [ ] 这份文档里和实际不符的地方，直接改掉。第 1 节的「没验证过」表格更新成
  「已验证」
- [ ] [MIGRATION.md 6.5](MIGRATION.md) 里 asus 那段，把实测出的差异补上
- [ ] 按 [CLAUDE.md](CLAUDE.md) 的规矩，在 `Lesson-Learn/` 加一篇新文档，
  记录真机上第一次遇到的问题和原因（编号取当前最大加一，同时更新
  `Lesson-Learn/README.md`）。**重点是双 ESP、GOP 分辨率、NTFS 共享盘、
  diskpart 预建分区这几件之前没在真机上验证过的事**
- [ ] 确认 asus 真机双 ESP 完全跑通之后，**再**删虚拟机相关内容：
  `hosts/vm/`、`flake.nix` 里的 `vm` 条目、`REHEARSAL.md`，
  以及 README 和 MIGRATION 里指向它们的引用。
  在那之前 `REHEARSAL.md` 第 4 节是这套方案的演练记录，留着有用
- [ ] thinkpad 上 `git pull`，再 `nrb`，让它认得 asus 的签名

---

## 附录 A：分区表精确数字

Samsung 990 PRO 2TB：`last-lba 3907029134`，共 3907029168 个 512 字节扇区
（1862.9 GiB）。

| # | 内容 | 大小 | 备注 |
|---|------|------|------|
| 1 | ESP | 1024 MiB | FAT32，`SYSTEM` |
| 2 | MSR | 16 MiB | |
| 3 | C: | 880000 MiB（≈859.4 GiB） | NTFS，`Windows` |
| 4 | 恢复 | 1024 MiB | NTFS，`Recovery`，类型 GUID `de94bba4-...` |
| 5 | 共享盘 | 1024000 MiB（=1000 GiB） | NTFS，`share` |

这些是理论值，Windows 实际建出来的起止扇区会有几 MiB 的对齐差异，
以 `diskpart` 里 `list partition` 的输出为准。

KIOXIA KXG80ZN84T09：共 8001573552 个扇区（3815.4 GiB，4,096,805,658,624 字节）。
逻辑扇区 512 字节。SMART 检查：两块盘 `PASSED`，无介质错误。

| # | 内容 | 起点 | 终点 |
|---|------|------|------|
| 1 | ESP（FAT32，`BOOT`） | 1 MiB | 2 GiB |
| 2 | Btrfs（`nixos`） | 2 GiB | 100% |

## 附录 B：被替换的旧布局（留作对照）

Bluefin 时代：

- Samsung：ESP 512M、MSR 16M、Windows 1000G（NTFS）、`/boot` 1G（ext4）、Btrfs 861.5G
- KIOXIA：WinData 1.5T（NTFS）、LinuxData 1.5T（ext4）、Shared 815G（exFAT）
- 固件启动项：Boot0000 `Windows Boot Manager`（实际指向 rEFInd）、
  Boot0003 `Windows Boot Manager`、Boot0005 `Fedora`，全部在旧的
  Samsung ESP（PARTUUID `72ed08b5-e2b2-4332-a2bc-1840a09e8f59`）上

## 附录 C：命令速查

```bash
# 认盘（NixOS 安装环境）
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL
ls -l /dev/disk/by-id/ | grep -E 'KIOXIA|Samsung' | grep -v part
blkid -L SYSTEM ; blkid -L share

# 引导（装好之后）
nix shell nixpkgs#efibootmgr -c efibootmgr -v
sudo refind-hwinfo
sudo refind-sync
sudo nixos-rebuild switch --flake /home/toru/nixos-config#asus
sudo nixos-rebuild switch --rollback

# 状态
state-sync status ; migration-check
```

```powershell
# Windows（管理员 PowerShell）
powercfg /h off
manage-bde -status
bcdedit /set {bootmgr} path \EFI\refind\refind_x64.efi
```

## 附录 D：内核 6.18 退役了怎么办

`hosts/asus/default.nix` 把内核明确钉在 `linuxPackages_6_18`，原因是 nixpkgs
里的 NVIDIA 开源驱动（写这段时是 595.71.05）在 7.2 内核上编译不过。
6.18 是长期支持版（LTS），但总有一天会到期。**这一节是那天的预案。**

> **写这一节时（2026-09-30）的实测事实**，之后会变，用来帮你理解命令输出的样子：
>
> | 组合 | 结果 |
> |------|------|
> | nixos-26.05 锁定版：驱动 595.71.05 + 内核 7.2.6 | 编译失败 |
> | nixos-unstable：驱动 595.104.02 + 内核 7.2.8 | 能编译（官方缓存里有现成产物） |
> | nixos-26.05 分支最新：驱动 595.71.05 | 驱动版本没变，估计同样编不过（只看了版本，没编） |
> | Bluefin 上的驱动 615.71.09 | NVIDIA 官网有，**任何 nixpkgs 分支都没有** |
>
> 也就是说：新驱动能解决编译问题，只是 26.05 这个稳定分支还没跟上。
> 而且**「能编译」不等于「在这块 RTX 5060 上能跑」**，这两件事要分开验证。

### D.1 「退役」会以什么形式出现

**它不会突然把系统弄坏。** 正在跑的系统完全不受影响。它只会在你**更新
`flake.lock`**（`nix flake update`，或者 `skills-update`，它内部跑的就是这个）
之后，以下面两种形式之一冒出来：

1. **构建直接失败**：nixpkgs 已经删掉了 `linuxPackages_6_18`，报错里有
   `removed because it has reached its end of life`（7.0、7.1 就是这样，
   现在都已经被删了）。**这发生在 `nix build` 那一步，`switch` 之前，
   所以当前系统毫发无损。** 这是故意想要的「响亮失败」，比悄悄升内核好得多。
2. **还能构建，但上游已经不再给 6.18 打安全补丁**（nixpkgs 删得晚一点的情况）。
   这种没有报错，所以**不能只靠报错来发现**。

**提前知道的办法：** kernel.org 的 releases 页面（`https://www.kernel.org/category/releases.html`）
里 longterm 那一栏列着每个 LTS 的预计结束日期。
**建议在 6.18 结束日期前 2-3 个月设一个日历提醒。**

### D.2 收到报错的第一反应

先把 `flake.lock` 还原，让仓库回到能构建的状态：

```bash
cd ~/nixos-config
git restore flake.lock
```

这是**权宜之计，不是解决办法**：旧的锁还能构建，但内核不再有上游安全补丁，
不要在这个状态上停太久。真正的处理从 D.3 开始。

### D.3 找候选内核

```bash
cd ~/nixos-config

# 1. nixpkgs 现在推荐的默认内核（通常就是它认定的当前 LTS，是最好的起点）
nix eval --raw .#nixosConfigurations.asus.pkgs.linuxPackages.kernel.version

# 2. 列出当前 nixpkgs 里真正还能用的内核（已被删的会被过滤掉）
nix eval --json .#nixosConfigurations.asus.pkgs.linuxKernel.packages --apply \
  'p: builtins.filter (n: (builtins.tryEval p.${n}.kernel.version).success)
       (builtins.filter (n: builtins.match "linux_[0-9]+_[0-9]+" n != null)
         (builtins.attrNames p))'

# 3. 当前锁定的驱动版本
nix eval --raw .#nixosConfigurations.asus.config.hardware.nvidia.package.version
```

第 2 条的输出形如 `["linux_5_10","linux_5_15","linux_6_1","linux_6_12","linux_6_18","linux_6_6","linux_7_2"]`
（这是 2026-09-30 的结果）。**选 LTS，不选普通版本**：普通版本几个月就到期，
选了等于过几个月再来一遍。哪些是 LTS 以 kernel.org 的 longterm 栏为准。
LTS 通常是每年最后发布的那个版本。

### D.4 试新内核能不能编译

把 `hosts/asus/default.nix` 里的 `pkgs.linuxPackages_6_18` 换成候选内核，
版本号里的点换成下划线，例如 `pkgs.linuxPackages_7_4`：

```nix
  boot.kernelPackages = pkgs.linuxPackages_X_Y;    # X_Y 换成你选的版本
```

然后**只构建，不切换**（**不用 sudo**）：

```bash
nixfmt hosts/asus/default.nix
nix build .#nixosConfigurations.asus.config.system.build.toplevel --out-link /tmp/res
nix build .#nixosConfigurations.asus.config.home-manager.users.toru.home.activationPackage --out-link /tmp/hm
```

- **两条都通过** → 去 D.5。
- **失败**，日志里有 `nvidia-open`（或 `nvidia/os-interface.c` 之类）→ 是驱动和这个
  内核的头文件不兼容，去 D.6。看日志的办法：
  `nix log <报错里给出的 .drv 路径>`。
- **失败但和 nvidia 无关** → 是别的东西，把最后 30 行日志记下来再查。

### D.5 装上去并验证

**换内核要用 `boot`，不用 `switch`。** `boot` 只写引导项、不激活，
下次重启才生效，万一起不来，重启就能选回旧的（原理见 CLAUDE.md「切换」那张表）：

```bash
sudo nixos-rebuild boot --flake /home/toru/nixos-config#asus
reboot
```

重启后**逐项验证，构建通过不等于可用**：

```bash
uname -r                                       # 是新内核
nvidia-smi                                     # 看得到 RTX 5060
nix shell nixpkgs#mesa-demos -c nvidia-offload glxinfo -B | grep -i renderer   # NVIDIA
systemctl --failed                             # 0 loaded units listed
```

再手动试：

- [ ] Wi-Fi 能连
- [ ] **合盖睡眠再唤醒**一次，屏幕正常、独显程序不花屏
  （`hosts/asus/tuning.nix` 里 `powerManagement.enable` 对应的就是这件事）
- [ ] 外接显示器能亮
- [ ] Steam 能启动一个游戏，走独显

**全部通过再提交。** 出问题就重启，在 systemd-boot 菜单里选上一个
generation（里面是旧内核），回去后 `git restore hosts/asus/default.nix` 再想办法。

> **别在一个没验证过的新内核上住太久。** `modules/common.nix` 的 `nix.gc`
> 会清掉 7 天以前的旧 generation。放着不管超过一周，能退回的旧 generation
> 就没了。验证要在一周之内做完。

### D.6 驱动编不过：按代价从小到大

| 办法 | 怎么做 | 代价与风险 |
|------|--------|------------|
| **a. 换相邻的内核试试** | D.4 换一个版本再构建 | 几乎没有。有时只是某个内核头文件不兼容，隔壁版本就好了 |
| **b. 换 NVIDIA 驱动分支** | 先看各分支版本：`for p in stable production latest beta new_feature legacy_580; do printf '%s ' $p; nix eval --raw ".#nixosConfigurations.asus.config.boot.kernelPackages.nvidiaPackages.$p.version"; echo; done`。挑一个更新的，写 `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.<分支>;` | 小。`beta` 分支比 `stable` 新但没那么稳。**RTX 50 系必须用开源内核模块**（`hardware.nvidia.open = true`），别为了兼容去关掉它 |
| **c. 内核连同驱动一起从 nixos-unstable 拿** | `flake.nix` 加一个 `nixpkgs-unstable` 输入，`boot.kernelPackages = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.linuxPackages_latest;`。`hardware.nvidia.package` 用 `config.boot.kernelPackages.nvidiaPackages.stable`，它会跟着取到 unstable 那个版本 | 中。**没有试过。** 内核和驱动必须**成对**来自同一个 nixpkgs，只换其中一个会不匹配。unstable 是滚动的，每次更新都可能变 |
| **d. 手工钉住 NVIDIA 官网的版本**（比如 Bluefin 上的 615.71.09） | 用 `nvidiaPackages.mkDriver { version = "…"; sha256_64bit = "…"; openSha256 = "…"; settingsSha256 = "…"; persistencedSha256 = "…"; }`，哈希用 `nix-prefetch-url` 逐个算 | 大。**没有试过。** 要自己维护版本和哈希，而且新版驱动不保证在新内核上编得过 |
| **e. 停在旧锁上等** | `git restore flake.lock`，不更新 | **只是拖延。** 6.18 一旦没有上游安全补丁，这就是在裸奔。给自己定个期限，别无限期 |
| **f. 应急：先让系统能用** | 把 `hosts/asus/tuning.nix` 里 NVIDIA 那一大段（`videoDrivers` 里的 `nvidia`、整个 `hardware.nvidia`）临时注释掉，再构建 | 独显暂时用不了（Steam 游戏、CUDA 之类），**但系统能起来**：显示器全部接在 AMD 核显上，桌面照常。**没有试过**，但逻辑上是通的 |

**顺序建议：a → b → c。** d 和 f 是万不得已。

### D.7 更大的一件事：26.05 这个 channel 本身也会到期

NixOS 稳定版只维护大约七个月（**以 nixos.org 的公告为准**）。26.05 是 2026 年 5 月出的，
**大约在 2026 年底结束支持**，到时整个仓库要一起升到下一个版本（26.11）。
这和内核退役经常是**同一件事**，因为新 channel 会带来新的默认 LTS 内核。

升级时三个输入要一起改，缺一个就会版本错位：

```nix
  # flake.nix
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.11";
  home-manager.url = "github:nix-community/home-manager/release-26.11";
  stylix.url = "github:danth/stylix/release-26.11";
```

然后 `nix flake update`（**不加 sudo**）。**thinkpad 和 asus 两台都要各构建两层**，
两台都通过再切换。asus 那台的内核选择和 D.3 到 D.6 一样，先看新 channel
里还有没有 `linuxPackages_6_18`，没有就按上面走。

### D.8 平时的习惯

- **更新 `flake.lock` 之后，先对 asus 做两个 `nix build`（不用 sudo），再 `switch`。**
  这条本来就在重建流程里，asus 上尤其不能省：它有独显，驱动编不过就是构建失败，
  但你要**看到**这个失败才知道。
- **`skills-update` 内部会 `nix flake update`**，也就是会顺带推进 nixpkgs 和内核。
  在 asus 上跑完它同样要先构建再切换。
- **换内核用 `nixos-rebuild boot` 不用 `switch`**，并且一周之内验证完（见 D.5 末尾）。
- **thinkpad 的内核继续用 `linuxPackages_latest` 不受影响**：它没有独显，
  没有 NVIDIA 驱动这个约束。
- 6.18 结束日期前 2-3 个月的日历提醒。

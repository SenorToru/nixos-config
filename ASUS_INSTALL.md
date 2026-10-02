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
> | [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md) | rEFInd 踩过的五个坑 |
> | [README.md](README.md) | 装好之后的日常操作 |

---

## 0. 先看全局

### 0.1 装完是什么样子

```
Samsung 990 PRO 2TB（nvme，归 Windows）
├── 1  ESP          1 GiB      FAT32   卷标 SYSTEM     Windows 的引导
├── 2  MSR          16 MiB
├── 3  C:           约 860 GiB NTFS    卷标 Windows
└── 4  共享盘       1000 GiB   NTFS    卷标 share      Windows 和 NixOS 共用

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

## 1. 验证到了哪里

**诚实地说清楚哪些走通了，哪些还没有。** 2026-09-30 开始在 asus 真机上装，
下表随进度更新，沿途踩的坑集中记在附录 E。

| 部分 | 状态 |
|------|------|
| Windows 11 的安装（第 6 章） | **真机走通，进了桌面。** 首次设置卡在联网界面，用本地账户绕过，见 6.5 节。diskpart 预建的 1 GiB ESP 和 1000 GiB 共享盘被安装器直接接受了（6.4 节的退路没用上）。Windows 装完后自己又建了一个约 892 MB 的恢复分区 |
| NixOS 的分区、格式化、挂载、`nixos-install`（第 9 章） | **真机走通。** 其中 9.9 节手动建 `Linux Boot Manager` 启动项那步实际用过，重启后直接进了 systemd-boot → NixOS |
| 首次进 NixOS（第 10 章） | **全部验证完**：系统层、显卡与 PRIME offload、桌面与输入、Wi-Fi、应用（Steam、Chrome、Telegram、Obsidian 等，toru 亲自试过）、合盖睡眠唤醒、共享盘写入（附录 E 第 10、11、12、29 条） |
| rEFInd 与双 ESP（第 11 章） | **真机走通，全部验证完**：两个 ESP 都写入，菜单、图标、进 NixOS 和 Windows、2560x1600 分辨率、Windows 侧 `bcdedit` 兜底都正常（附录 E 第 14、15、18 条） |
| Windows 那一侧的第 7 章设置 | **已核实**：休眠关、快速启动不可用、BitLocker 关、UTC 已设置（附录 E 第 16 条）。共享盘在进过 Windows 之后仍可写，时间没有错开（附录 E 第 18 条） |
| `hosts/asus/` 的运行时表现 | **验证完**：第 13 节的整体验证在 asus 上全部通过，唯一的失败服务是已知的背光那一个（附录 E 第 12 条） |
| 华硕的启动菜单键、BIOS 键 | 启动菜单键是 **`Esc`**（实测）。BIOS 键还没记录 |

三件虚拟机验证不了的事，在真机上都碰到并解决了：
**GOP 分辨率**（面板原生 2560x1600，固件有这个模式，第 11.4 节）、**NTFS 脏状态**（关了快速启动和休眠之后共享盘仍可写，第 7、10.3 节）、
**硬件探测的值**（显卡两行判反，已修，附录 E 第 13 条）。

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

create partition primary size=881000
format quick fs=ntfs label="Windows"

create partition primary size=1024000
format quick fs=ntfs label="share"

list partition
exit
```

说明：

- diskpart 里的 `size=` 单位是 **MB，实际等于 MiB**（1024 就是 1 GiB）。
- `881000` MiB ≈ 860 GiB，是 C: 的大小。
- `1024000` MiB = 1000 GiB，是共享盘。
- 四个数加起来（ESP、MSR、C:、共享盘）比整盘少约 1.6 GiB，那点余量是有意留的。

**脚本里没有预建 Windows 恢复分区（WinRE），这是有意的。** 那个分区只服务于
「重置此电脑」和系统起不来时的自动修复。好处是少四行 diskpart。

> **实测发现（2026-09-30）：Windows 装完之后自己又建了一个恢复分区。**
> 在 NixOS 里 `lsblk` 看到 Samsung 盘上多了一个约 892 MB、没有卷标的 NTFS 分区
> （`nvme0n1p4`），同时 C: 是 859.5 GiB，比脚本里 `size=881000`（约 860.3 GiB）
> 少了差不多同样的大小。所以这个分区是 Windows 安装器从 C: 里缩出来的。
> **已确认：** 在 Windows 里跑 `reagentc /info`，`Windows RE status: Enabled`，
> `Windows RE location: \\?\GLOBALROOT\device\harddisk0\partition4\Recovery\WindowsRE`，
> 也就是第 4 个分区，和 `lsblk` 里 892M 的 `nvme0n1p4` 对上了。
>
> 结论：**「不预建」并不能阻止 Windows 自己建一个，只是省了我们自己的四行脚本。**
> 这个分区没有害处，不用管它，也**不要删**。它不影响共享盘和 NixOS 的任何东西。
> 所以本节上面「没有恢复分区」的预期分区表，实际会多出一个小分区，见 9.1 节的 `lsblk` 示意。

`list partition` 的输出应该有 4 行：

```
  Partition 1    System             1024 MB
  Partition 2    Reserved             16 MB
  Partition 3    Primary             860 GB
  Partition 4    Primary            1000 GB
```

- [ ] 四个分区都在，大小对得上

然后在命令提示符里：

```
exit
```

（回到安装界面。再 `exit` 一次会关掉命令提示符窗口，没关系。）

### 6.4 选安装位置

回到安装界面，点「刷新」。**你应该看到 Samsung 上有 4 个分区**：
「系统」、「MSR」、「主分区 860 GB」、「主分区 1000 GB」。

**选那个 860 GB 的分区**（不是 1000 GB 的，不是 KIOXIA 上的任何分区），点「下一步」。

> **如果安装器拒绝，或者报「无法在此驱动器上安装」：**
> 这说明它不接受预建的分区。退路是：
> `Shift+F10` → `diskpart` → `select disk N` → `clean` → `convert gpt` → `exit`，
> 然后回到安装界面，选那块盘的「未分配空间」，点「新建」，
> **在「大小」里填 `881000`**，让安装器自己划 ESP、MSR、C:。
> **这种情况下安装器会自己多建一个恢复分区，这个没关系，不用管它。**
> 装完再回 Windows 的「磁盘管理」，把剩下的未分配空间建成一个 NTFS 分区
> （约 1000 GiB，以磁盘管理里实际剩下的为准，不必凑整），卷标 `share`。
> **这种情况下 ESP 会比 1 GiB 小，卷标也不是 `SYSTEM`。** 到了 9.7 节，
> `blkid -L SYSTEM` 会找不到它，按那里的说明用 `fatlabel` 补一个卷标就行。

### 6.5 等 Windows 装完，跑完首次设置

1. 安装过程会重启几次。**重启到「Press any key to boot from CD」时不要按键**，
   让它从硬盘走。或者干脆此时拔掉 U 盘。
2. 首次设置里问账户：
   - 想用微软账户就登录。
   - 想用本地账户：见下面「卡在联网界面」。
3. 到桌面之后，**先让 Windows 联网并跑一遍 Windows Update**，
   更新驱动（含 Wi-Fi 和显卡）。可能需要重启多次。

> ### 卡在「让我们连接你到网络」，Wi-Fi 网卡没有驱动
>
> **实际遇到过（2026-09-30）：** Windows 11 的首次设置要求联网才能继续，
> 而这台的 Wi-Fi 网卡（Realtek RTL8852CE）安装器里不认，驱动又是 EXE 格式，
> 在这个阶段没法点击运行。
>
> **解决办法（实测可用）：跳过联网要求，用本地账户先进桌面。**
>
> 1. 在联网界面按 `Shift + F10`（华硕笔记本可能要 `Fn + Shift + F10`），
>    打开命令提示符。
> 2. 输入 `oobe\bypassnro`，电脑会自动重启，回来后出现
>    「我没有 Internet 连接」，点它，再点「继续执行受限设置」，创建本地账户。
> 3. 如果这条命令不存在（新版 Windows 11 把它删了），改用
>    `start ms-cxh:localonly`，会直接弹出创建本地账户的窗口。
> 4. 到桌面之后再运行 U 盘里的 Wi-Fi 驱动 EXE，装完连网。
>
> 这两条命令**随 Windows 版本而变**。用本地账户还有个好处：
> Windows 11 登录微软账户后会自动开启设备加密，本地账户不会（见 7.3 节）。
>
> 备选办法：手机 USB 共享网络（安卓，插线即通）或 USB 有线网卡（大多免驱）；
> 或者把驱动 EXE 用 7-zip 解开，在联网界面用
> `pnputil /add-driver <路径>\*.inf /subdirs /install` 装上（这条没验证过）。
>
> **所以装机前最好先把 Wi-Fi 驱动 EXE 放进 Windows 安装 U 盘或另一个 U 盘。**
> 驱动从华硕官网这个机型的下载页取。

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

> **本章的命令靠 shell 变量（`$DISK`、`$OPTS` 等）串起来，而变量只在当前终端里有。**
> 换一个终端窗口、`sudo -i`、进 `nixos-enter` 都会让它们消失，
> 而消失之后的症状不直观：`readlink: missing operand`、命令报设备不存在。
> **每次开新终端，先 `sudo -i`，再照下面重设一次 `DISK`，并 `lsblk $DISK` 核对是 KIOXIA。**
> 9.9 节的建启动项那一步就是因为这个，改成了不依赖 `$DISK` 的写法。

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL
```

你应该看到：

```
NAME        SIZE  MODEL                   FSTYPE  LABEL
nvme0n1     1.8T  Samsung SSD 990 PRO ..
├─nvme0n1p1 1G                            vfat    SYSTEM
├─nvme0n1p2 16M
├─nvme0n1p3 859.5G                        ntfs    Windows
├─nvme0n1p4 892M                          ntfs            ← Windows 自己建的恢复分区，无卷标
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
OPTS=compress=zstd:3,noatime

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

- [ ] 四个 btrfs 子卷都在，`/mnt/boot` 是 vfat，选项里有 `compress=zstd:3`

> 这里挂载用的选项**只影响安装过程本身**。装好之后持久生效的那份写在
> `hosts/asus/tuning.nix`（`nixos-generate-config` 不记 `compress` 和 `noatime`）。
> 背景见 [MIGRATION.md 决策点 C](MIGRATION.md)。
>
> **这台用 `zstd:3`，不是 thinkpad 的 `zstd:1`。** 决策点 C 的判据是「CPU 有富余就用 3」，
> Ryzen AI 7 H 350 够强。**装机时这里的 `OPTS` 和 `tuning.nix` 里的必须是同一个等级**，
> 两处不一致的话，装机期间写进去的数据按一个等级压，装好之后的新数据按另一个等级压，
> 不会坏，但不整齐。
>
> 只有这块 Btrfs 能压缩：ESP 是 FAT32，Windows 共享盘是 NTFS，都压缩不了，也不需要。
> 想在装好之后确认压缩真的生效：`sudo compsize /`（`nix shell nixpkgs#compsize`）。

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

**不要依赖前面设的 `$DISK` 变量。** 换过终端窗口、`sudo -i` 过、进过 `nixos-enter`，
变量都会丢，丢了之后下面的命令会报 `readlink: missing operand`。
所以这里直接从**已经挂载的 ESP** 推出磁盘和分区号：

```bash
# 1. /mnt/boot 必须还挂着，是 KIOXIA 的 ESP
findmnt /mnt/boot

ESP_DEV=$(findmnt -no SOURCE /mnt/boot)                       # 如 /dev/nvme1n1p1
DISK_DEV=/dev/$(lsblk -no PKNAME "$ESP_DEV")                  # 如 /dev/nvme1n1
PART=$(cat /sys/class/block/$(basename "$ESP_DEV")/partition) # 应该是 1

# 2. 写之前核对：必须是 3.7T 的 KIOXIA，不是 Samsung
lsblk -o NAME,SIZE,MODEL "$DISK_DEV"
echo "disk=$DISK_DEV part=$PART"
```

**`lsblk` 输出里型号必须是 KIOXIA、大小约 3.7T。** 是 Samsung 就停下来，
说明挂载错了盘。

```bash
# 3. 确认现在是 UEFI 模式启动，而且不在 nixos-enter 里面
ls /sys/firmware/efi/efivars | head -3

# 4. 建启动项
nix-shell -p efibootmgr --run "efibootmgr --create --disk $DISK_DEV --part $PART --loader '\\EFI\\systemd\\systemd-bootx64.efi' --label 'Linux Boot Manager'"
```

如果 `findmnt /mnt/boot` 没有输出，说明 ESP 已经被卸载了，
回 9.4 把 `/mnt/boot` 挂回去（`mount -o umask=0077 ${DISK}-part1 /mnt/boot`，
`DISK` 要先按 9.1 重新设）。

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

> **先在当前终端里跑一次这条：** `setopt interactive_comments`
>
> 下面的命令块里有很多 `命令   # 说明`。zsh 默认不把交互式输入里的 `#` 当注释，
> 整块粘贴会报 `Unknown command verb '#'`、`sysctl: cannot stat /proc/sys/#`
> 这类看起来像命令坏了的错误（2026-09-30 实测踩到）。这条命令让当前终端认 `#` 为注释。
> 仓库里 `home/toru.nix` 已经把它写成了 zsh 的默认选项，**这台机器 `git pull`
> 并 `nrb` 之后就不用再敲**；在此之前每开一个新终端都要敲一次，
> 或者粘贴时把 `#` 后面的部分去掉。

```bash
hostnamectl                                   # Static hostname: asus
nixos-rebuild list-generations | head -3      # 有 generation
findmnt -t btrfs -o TARGET,OPTIONS            # 4 个子卷，选项含 compress=zstd:3
swapon --show                                 # 只有 zram，没有磁盘 swap
sysctl vm.swappiness                          # 180
findmnt /mnt/winesp                           # Windows 的 ESP，vfat
findmnt /mnt/share                            # 共享盘，ntfs3
```

> **`findmnt` 一次只认一个挂载点。** 写成 `findmnt /mnt/winesp /mnt/share`
> 不会报错，只是**什么都不输出**，返回码是 1，看起来就像两个都没挂上。
> 2026-09-30 在 asus 上就被这个骗过：那条命令没输出，实际两个分区都挂得好好的。
> 所以要一条一条查，或者按类型查：`findmnt -t vfat,ntfs3`。

**`findmnt /mnt/winesp` 或 `findmnt /mnt/share` 没输出**：`nofail` 让它静默失败了。
看 `tuning.nix` 里的 UUID 对不对，`sudo blkid` 对照一遍。
再看 `systemctl status mnt-winesp.mount mnt-share.mount`。

**`/mnt/share` 是只读或挂不上**：Windows 那侧的快速启动或休眠没关干净，
NTFS 是脏的。回 Windows 里做 7.1 和 7.2，**然后关机（不是重启）**，再回 NixOS。

```bash
touch /mnt/share/nixos-test && rm /mnt/share/nixos-test && echo "共享盘可写"
```

### 10.4 验证显卡

```bash
nvidia-smi                                    # 应该看到 RTX 5060 Laptop，驱动版本
lspci -D -k | grep -EA3 'VGA|3D|Display'         # 核显用 amdgpu，独显用 nvidia
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
lspci -D | grep -E 'VGA|3D|Display'
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

> **新机器上输入法要手动启用一次。** 刚装好时，fcitx5 里 Rime 和 Mozc 的程序都在，
> 但「启用了哪几个输入法」那份设置（`~/.config/fcitx5/profile`，B 类状态）是空的，
> 所以配置窗口的当前输入法里一个都没有。2026-09-30 实测就是这样。
>
> 手动加的办法：fcitx5 配置 → Input Method → 左下角 `+` →
> **取消勾选底部的「Only Show Current Language」**（默认勾着，系统语言是英文，
> 所以 Mozc 和 Rime 被藏起来，这是「看不见」的真正原因）→ 搜 `Mozc`、`Rime` 各加一个 → Apply。
> 第一次切到 Rime 会自动部署（白霜词库要编译，一两分钟，不需要执行任何命令）。
>
> **不要用 `state-sync restore` 把 thinkpad 的 profile 整份铺过来：** thinkpad 的是
> JIS 日语键盘，profile 里是 `Default Layout=jp` 和 `keyboard-jp`，而 asus 是 US 键盘，
> 铺过来键位会错。要还原的话，之后把这两处改成 `us` 和 `keyboard-us`。
>
> **默认就是英文输入，不用另外设置。** 新窗口默认用哪个输入法，由两件事决定：
> `~/.config/fcitx5/profile` 里排第一的那一项（手动加的时候保持键盘布局那一项排第一），
> 以及 `~/.config/fcitx5/config` 里的 `ActiveByDefault=False`（默认值）。
> **不要手工改 `profile` 里的 `DefaultIM`**：它不是「启动时用哪个」，fcitx5 会自己随你最近用过的
> 输入法改写它（`Ctrl+Space` 在英文键盘和最近用过的输入法之间切换）。见附录 E 第 26 条。

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

应该是 AMD Ryzen AI 7 H 350、Radeon / RTX 5060、内存约 30G（会显示 32768M）、
根所在盘（KIOXIA）的那几行。**探测错了可以直接改这个文件**，它不在开机路径上，
错了只是启动画面上一行字不对。

**特别看两行 GPU 有没有标反：** `igpu` 应该是 AMD Radeon 860M（标 SHARED），
`dgpu` 应该是 NVIDIA RTX 5060。2026-09-30 用旧版探测判据时，这两行在 asus 上
标反了（见附录 E 第 13 条）。判据已经修过，但**在 asus 真机上重跑修好的版本还没做**，
所以这里仍然要目视检查一遍。标反了就直接手改，改法见附录 E 第 13 条。

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

**asus 上实际走通的更短做法（2026-09-30，一次成功）：**

1. 先看面板原生分辨率，内核报的首选模式在第一行：
   `cat /sys/class/drm/card*-eDP-*/modes | head -3`（连着内置屏的那个 `card` 编号
   会随重启变，别写死；这台是 `2560x1600`，16:10）。
2. 直接把 `hosts/asus/default.nix` 里 `custom.refind.resolution` 改成这个值，
   `nixfmt`（排除 hardware-configuration.nix）、用户态 `nix build`、
   `sudo nixos-rebuild switch ...`、`sudo refind-sync`，重启。
3. **固件有这个模式**：画面清晰、填满屏幕，完成。asus 就是这样，
   固件的 GOP 里有面板原生的 2560x1600。
4. **固件没有**：rEFInd 启动时会报模式不存在并**列出固件支持的全部模式**，
   拍照或抄下来，从里面挑最接近原生的，再走一遍第 2 步。这条路在 thinkpad 上走过。
   想主动让它列出来，把 `resolution` 临时设成一个明显无效的值（`width = 1; height = 1;`）。

内核报的模式不是固件 GOP 的列表，两者不一定相同，所以第 1 步只是给出一个
**值得先试的候选**，不是保证。这台碰巧一致，thinkpad 也一致（原生 2560x1440 就是 Mode 0）。

**验证实际分辨率：** 在 rEFInd 界面按 `F10` 截图，会写一张未压缩的 BMP，
`文件大小 = 宽 × 高 × 3 + 54`，反推就知道实际分辨率。
2560x1600 对应 12,288,054 字节，asus 上实测就是这个数，说明没有被回退到别的模式。

**这张 BMP 不一定在 rEFInd 启动所在的 ESP 上。** asus 上 rEFInd 是从 KIOXIA 的 ESP
（`/boot`）启动的，截图却写到了 Windows 的 ESP（`/mnt/winesp/screenshot_001.bmp`）。
原因没有查过，可能是 rEFInd 挑了它遇到的第一个可写的 FAT 卷，**这一条是推测**。
所以找它要两个 ESP 都看：

```bash
sudo find /boot /mnt/winesp -maxdepth 1 -iname 'screenshot_*.bmp' -exec ls -l {} \;
```

每张 12 MB，rEFInd 自己从不清理。想留着当记录，先转成 PNG（约 290 KB）再删：

```bash
nix shell nixpkgs#imagemagick -c magick /tmp/shot.bmp "$HOME/Pictures/library/2026/09/2026-09-30 asus rEFInd 2560x1600.png"
```

**删的时候写具体文件名，不要用通配符**，尤其是在 Windows 的 ESP 上：
`sudo rm -f /mnt/winesp/screenshot_001.bmp`。

详细背景见 [MIGRATION.md 6.4](MIGRATION.md)。

- [ ] 画面填满屏幕，没有被拉伸或平铺

### 11.5 Windows 侧的兜底

**这一步在 Windows 里做。** 从 rEFInd 选 Windows 进去。

> **别在 PowerShell 里直接敲 `{bootmgr}`。** PowerShell 会把花括号当成脚本块，
> 命令不会按你想的执行。要么开**管理员命令提示符**（`cmd`，命令原样有效），
> 要么在 PowerShell 里给花括号加单引号：`'{bootmgr}'`。
> （2026-09-30 做这一步之前发现的，教程原来写的是不带引号的 PowerShell 写法。）

先看基线，`path` 一行现在应该是 `\EFI\Microsoft\Boot\bootmgfw.efi`：

```
bcdedit /enum {bootmgr}
```

然后改（管理员命令提示符）：

```
bcdedit /set {bootmgr} path \EFI\refind\refind_x64.efi
```

同一条在管理员 PowerShell 里要写成：

```powershell
bcdedit /set '{bootmgr}' path \EFI\refind\refind_x64.efi
```

改完再跑一次 `bcdedit /enum {bootmgr}`，`path` 应该变成 `\EFI\refind\refind_x64.efi`。

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
findmnt /mnt/winesp
findmnt /mnt/share

# 显卡
nvidia-smi
nix shell nixpkgs#mesa-demos -c nvidia-offload glxinfo -B | grep -i renderer

# 字体与 shell
fc-match "Sarasa Mono J"
echo $SHELL

# 服务
systemctl is-active fwupd
systemctl --failed                           # 只应有 nvidia_wmi_ec_backlight 那一条，见附录 E 第 12 条

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
- [x] asus 真机双 ESP 跑通之后，已经删掉虚拟机相关内容（2026-10-02）：`hosts/vm/`、`flake.nix` 里的 `vm` 条目、
  `REHEARSAL.md`，以及 README 和 MIGRATION 里指向它们的引用。演练记录在 git 历史里，
  需要时 `git log -- REHEARSAL.md` 找
- [ ] thinkpad 上 `git pull`，再 `nrb`，让它认得 asus 的签名

---

## 附录 A：分区表精确数字

Samsung 990 PRO 2TB：`last-lba 3907029134`，共 3907029168 个 512 字节扇区
（1862.9 GiB）。

| # | 内容 | 大小 | 备注 |
|---|------|------|------|
| 1 | ESP | 1024 MiB | FAT32，`SYSTEM` |
| 2 | MSR | 16 MiB | |
| 3 | C: | 881000 MiB（≈860.3 GiB） | NTFS，`Windows` |
| 4 | 共享盘 | 1024000 MiB（=1000 GiB） | NTFS，`share` |

没有 Windows 恢复分区（WinRE），是有意的，理由见 6.3 节。

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
powercfg /a
manage-bde -status C:
reagentc /info
bcdedit /enum '{bootmgr}'
bcdedit /set '{bootmgr}' path \EFI\refind\refind_x64.efi
# 上面 bcdedit 的花括号在 PowerShell 里必须加单引号；在 cmd 里不加也行
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
systemctl --failed                             # 只应有 nvidia_wmi_ec_backlight 那一条（附录 E 第 12 条）
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

## 附录 E：真机实测记录

装机过程中和文档不一致、或者第一次在真机上碰到的事。每条写明**发生了什么、怎么解决、
文档哪里因此改了**。这是第 15 节要求的回头更新的原始素材。

### 2026-09-30

**1. Windows 11 首次设置卡在联网界面。**
Wi-Fi 网卡（RTL8852CE）装机器里不认，驱动是 EXE，这个阶段没法运行。
用 `Shift+F10` 打开命令提示符，`oobe\bypassnro` 重启后选「我没有 Internet 连接」，
用本地账户进桌面，再装驱动。**实测可用。**
改了：6.5 节加了整段说明，并提醒装机前把驱动 EXE 放进 U 盘。

**2. 决定不要 Windows 恢复分区。**
这是设计上的调整，不是踩坑：恢复分区只服务于「重置此电脑」和系统起不来时的自动修复，
这台的 Windows 是第二系统，不需要。
改了：diskpart 脚本、分区表、各处示意图，共享盘从 5 号分区变成 4 号。

**3. Btrfs 压缩等级从 zstd:1 改成 zstd:3。**
走完 9.4 才想起来。因为还没往里写过任何数据，卸载后用新选项重新挂载就够，
不用重做 9.2 到 9.4。**实测可用。**
顺带发现 `hosts/asus/tuning.nix` 原来漏了 `/nix` 和 `/.snapshots` 两个子卷的
压缩选项，已补上，四个子卷共用同一个 `btrfsOptions`。
改了：9.4 节的 `OPTS`、验证清单、`tuning.nix`。

**4. 建 `Linux Boot Manager` 启动项时，`$DISK` 变量丢了。**
换过终端窗口之后，`readlink -f $DISK` 报 `missing operand`，`efibootmgr` 报
`Could not prepare Boot variable: No such file or directory`。
改用从已挂载的 ESP 推出磁盘和分区号（`findmnt` + `lsblk -no PKNAME` +
`/sys/class/block/.../partition`），写之前先核对型号是 KIOXIA。**实测可用，
重启后直接进了 systemd-boot → NixOS。**
改了：9.9 节第三步整段重写；9.1 节开头加了变量会丢的提醒。

**5. 第一次进入 NixOS 成功。**
从 systemd-boot 进的，这时还没有 rEFInd，是预期的。第 10 章之后的验证还没有记录。

**6. 整块粘贴带 `# 注释` 的命令，在 zsh 里报错。**
第一次做 10.3 的验证，把命令块整个粘进终端，得到
`Unknown command verb '#'`、`head: cannot open '#' for reading`、
`sysctl: cannot stat /proc/sys/#: No such file or directory`。
**不是系统有问题：** zsh 默认不把交互式输入里的 `#` 当注释，bash 默认当。
文档命令块大量写着 `命令   # 说明`，整块复制就撞上了。
同一次输出里真正有信息量的两条是对的：`swapon --show` 只有 zram0（15.2G）、
`vm.swappiness = 180`。
**修法：** `home/toru.nix` 的 `programs.zsh` 加了
`setOptions = [ "INTERACTIVE_COMMENTS" ]`，两台机器的 zsh 都生效，
和 bash 的行为一致。在 asus 拿到这个配置之前，用 `setopt interactive_comments`
临时打开。改了：10.3 节开头加了提示。

**7. `findmnt /mnt/winesp /mnt/share` 没输出，被它骗了。**
第一次做 10.3 的验证，这条命令什么都没输出，我据此判断两个分区没挂上，
让排查 UUID、脏状态。**判断错了：** `findmnt` 一次只认一个挂载点，
传两个参数不会报错，只是无输出、返回码 1（在 thinkpad 上用 `findmnt /boot /home` 复现了）。
实际两个都挂好了：`systemctl status` 显示 `/mnt/winesp` 是 `/dev/nvme0n1p1`（vfat）、
`/mnt/share` 是 `/dev/nvme0n1p5`（ntfs），开机时就 mounted；
`tuning.nix` 里的 `winEspUuid`（6E1C-D1AE）和 `shareUuid`（4C0C4C710C4C585A）
都和 `blkid` 对得上，9.7 节的填法是对的。
改了：10.3 节和第 13 节的检查命令拆成两条，10.3 加了说明。
教训：**验证命令本身也要验证。** 一条「没输出」的命令，先想是不是命令写错了，
再去怀疑系统。

**8. diskpart 预建的分区被 Windows 安装器直接接受了。**
从 NixOS 里看：Samsung 盘上 `nvme0n1p1` 是 1G 的 vfat、卷标 `SYSTEM`（我们 diskpart
建的，安装器自己建的 ESP 只有一百多 MB），`nvme0n1p5` 是 1000G、卷标 `share`。
所以 6.3 的脚本走通了，6.4 节的退路没有用上。**这一条是从分区结果反推的，
没有记录安装器当时的界面。**

**9. Windows 装完后自己多建了一个约 892 MB 的恢复分区。**
`lsblk` 里 `nvme0n1p4`，892M，NTFS，没有卷标；C: 是 859.5 GiB，比脚本预期的
860.3 GiB 少了差不多同样大小，说明是从 C: 里缩出来的。所以「脚本里不预建」
只是省了四行 diskpart，并不能阻止 Windows 自己建一个。没有害处，不要删。
从大小反推的，没有在 Windows 里用 `reagentc /info` 确认。
改了：6.3 节的说明改成了实际情况，9.1 节的 `lsblk` 示意加了这一行。

**10. 装机后的首轮验证结果（10.3 和 10.4 节的部分）。**
全部符合预期：`hostnamectl` 是 asus、内核 6.18.52；generation 1 存在
（`Configuration Revision` 是 Unknown，因为装机时仓库是脏的，正常）；
四个 Btrfs 子卷都是 `compress=zstd:3,noatime`，另有默认的 `ssd,discard=async,space_cache=v2`；
`swapon --show` 只有 `zram0`（15.2G）；`vm.swappiness = 180`；
`nvidia-smi` 看到 RTX 5060 Laptop、8GB、驱动 595.71.05、空闲 P8 约 3W。
另外 `hostnamectl` 的 `OS Support End: 2026-12-31` 证实了附录 D.7 说的
26.05 大约年底到期。

**11. 10.4 显卡验证通过，PRIME offload 实测生效。**
由 asus 上的 Claude（通过 Remote Control）跑命令并回报，输出原样：
- `lspci -D -k`：`0000:64:00.0` 是 NVIDIA GB206M，`Kernel driver in use: nvidia`；
  `0000:66:00.0` 是 AMD Krackan，`Kernel driver in use: amdgpu`。
- `/sys/class/drm/card1` 指向 `0000:64:00.0`（nvidia），`card2` 指向 `0000:66:00.0`（amdgpu）。
- 默认渲染：`AMD Radeon 860M Graphics (radeonsi, krackan1, ACO, DRM 3.64, 6.18.52)`。
- `nvidia-offload` 下：`NVIDIA GeForce RTX 5060 Laptop GPU/PCIe/SSE2`。
- `tuning.nix` 里 `amdgpuBusId = "PCI:102:0:0"`、`nvidiaBusId = "PCI:100:0:0"` 和实际总线号对得上。
两个小发现：
- **AMD 核显在 `lspci` 里是 `Display controller`（class 0380），不是 `VGA compatible controller`。**
  原来文档里 `grep -E 'VGA|3D'` 会漏掉它，只看到 NVIDIA 一块。已改成 `VGA|3D|Display`。
- 非 root 跑 `lspci -k` 会打一行 `pcilib: Error reading .../label: Operation not permitted`，
  无害，忽略即可。
另外确认了 `lspci` 在 asus 的 PATH 上（`modules/common.nix` 里有 `pciutils`），
不需要 `nix shell`。

**12. `systemctl --failed` 里有一个失败的服务，无害，不处理。**
`systemd-backlight@backlight:nvidia_wmi_ec_backlight.service` 失败，
`Result: start-limit-hit`，日志每次都是同一句：
`Failed to write system 'brightness' attribute: Input/output error`。
内核侧同时打着 `nvidia-wmi-ec-backlight ...: EC backlight control failed: AE_NOT_FOUND`。
本次启动内出现了 13 轮，每轮 5 次尝试后撞上启动频率限制。
**这不是「只在开机时失败」**（asus 上的 Claude 核对日志后指出的）：13 轮里只有 1 轮在开机
（22:11:14），另外 12 轮发生在 22:25:39 到 22:45:13 之间、会话运行期间，
每一轮内核侧都伴随 6 行 `AE_NOT_FOUND`。
**触发原因没有查清。** 时间点大致和 toru 那段时间跑 `nvidia-smi`、`nvidia-offload`、
试亮度的时间重合，所以曾推测是独显被唤醒、或亮度被调节时会重发这个背光设备的
udev 事件，但这只是猜测，没有拿证据验证过。

关键的一点：**屏幕亮度本身是正常的。** toru 亲自试过，亮度键和 GNOME 设置里的滑块
都能明显调亮调暗。这台机器上 `/sys/class/backlight/` 里只有这一个设备
（`nvidia_wmi_ec_backlight`，type=firmware，brightness=35，max=100），
内核日志里 `amdgpu ... Skipping amdgpu DM backlight registration`，
`nvidia-modeset` 报 `ACPI reported no NVIDIA native backlight available;
attempting to use ACPI backlight`。也就是说**真正管这块面板亮度的就是这个设备**，
失败的是 `systemd-backlight` 的 load 操作，也就是把保存的亮度值写回这个设备，
写的时候设备返回 EIO。它在运行期间也会反复触发，不限于开机。
**已观察到的后果**只有 `systemctl --failed` 多一行，亮度键和滑块都仍然有效。
**没有观察到但不能排除的：** 重启后亮度是否被恢复到上次的值，没有专门试过。
**不要为了让它不报错就去屏蔽模块**（`boot.blacklistedKernelModules`）：
那会连唯一的背光设备一起拿掉，亮度控制就没了。
决定：不处理，只记录。13 节和 D.5 的检查里，`systemctl --failed` 的预期改成
「只应有这一条」。如果将来出现别的失败服务，才需要查。

**13. `refind-hwinfo` 把 asus 的两块显卡标反了。**
`sudo refind-hwinfo` 生成的 hwinfo.nix 里：`igpu` 是 NVIDIA RTX 5060（标 SHARED），
`dgpu` 是 AMD Radeon 840M/860M（标 512M）。原因是 `modules/refind.nix` 里的判据
只在单核显的 thinkpad 上验证过：NVIDIA 没有 sysfs 显存节点，被当成核显；
AMD APU 不在 bus 00 上、又报了 512M 的划分显存，被当成独显。
`modules/refind.nix` 注释里早就写过这个风险，这次是第一次在真机上碰到。
CPU、内存（32768M LPDDR5）、磁盘（根在 KIOXIA 上，之前的占位写的是 Samsung）三行是对的。
处理：
- 本次装机：按脚本注释的建议，直接手改 `hosts/asus/hwinfo.nix` 的两行
  （igpu 改成 AMD RADEON 860M GRAPHICS / SHARED，dgpu 改成
  NVIDIA GEFORCE RTX 5060 LAPTOP / 8151M）。
- 工具本身：`modules/refind.nix` 的判据改成 bus 00 算核显、NVIDIA 算独显、
  显存 >= 2048M 算独显、其余算核显；AMD 厂商名也从 "Advanced" 改成 AMD。
  用三种形态的样例验证了逻辑，thinkpad 上重跑结果不变。
  asus 真机上重跑还没做。
改了：11.1 节加了提醒。

**14. rEFInd 第一次上真机：菜单、图标、进系统都正常。**
`refind-hwinfo` → 手改 GPU 两行 → `nixos-rebuild switch` → `refind-sync` 一路走通，
两个 ESP 都写进了 rEFInd（`refind_x64.efi`、`refind.conf`、`themes/`），
NVRAM 里 rEFInd 排 `BootOrder` 第一位，`Linux Boot Manager` 安全网还在。
重启后菜单出现，NixOS 和 Windows 11 两个图标都是正常图标（不是黄黑方块），
选 NixOS 进了系统。**启动菜单键是 `Esc`**（之前一直写「通常是」，这次实际用过）。
两处小现象：
- `refind-sync` 每次先删自己上次建的那条 NVRAM 项再重建，所以编号会变
  （`Boot0004` → `Boot0001`），无害。
- 装机时插过的 U 盘留下的那条 `UEFI OS`（MBR 磁盘上的 `\EFI\BOOT\BOOTX64.EFI`）
  拔掉 U 盘后固件自己清掉了，11.6 节的「清死启动项」在这台上基本用不上。这一条是推测。

**15. rEFInd 分辨率：直接试面板原生值，一次成功。**
面板原生（内核 `modes` 第一行）是 `2560x1600`（16:10），直接填进 `resolution`，
固件 GOP 里有这个模式。F10 截图 12,288,054 字节 = 2560×1600×3+54，证明实际就是这个分辨率，
没有被回退。比文档原来写的「先填无效值逼它列模式」少一轮重启。
改了：11.4 节改写，加了「更短的做法」，保留原来的做法作为固件没有该模式时的退路。
两个发现：
- 连着内置屏的 `card` 编号会随重启变（`card1`/`card2` 重启后成了 `card0`/`card1`），
  不要按编号找，按连接器名（`eDP-1`）或总线号。
- **F10 截图写到了 Windows 的 ESP，不是 rEFInd 启动所在的 ESP。** 原因没查，
  推测是它挑了遇到的第一个可写 FAT 卷。找和删的时候两个 ESP 都要看，
  删用具体文件名不用通配符。截图转成 PNG（294 KB）存在
  `~/Pictures/library/2026/09/`，原 BMP 删除。
  改了：11.4 节和 MIGRATION.md 6.4 节。

### 2026-10-01

**16. Windows 一侧的第 7 章设置全部核实通过（在 Windows 里跑命令）。**
- `powercfg /a`：`Hibernate: Hibernation has not been enabled`，
  `Fast Startup: Hibernation is not available`。休眠没开，快速启动因此不可用，
  这正是 7.1 和 7.2 要的结果。
- `manage-bde -status C:`：`BitLocker Version: None`，`Fully Decrypted`，
  `Protection Off`。设备加密没开（用了本地账户），7.3 担心的事没有发生。C: 是 859.48 GB。
- `reagentc /info`：`Windows RE status: Enabled`，位置在 `harddisk0\partition4`，
  即第 4 个分区。**这证实了附录 E 第 9 条的推断：892 MB 的恢复分区是 Windows 自己建的。**
- `reg query ... RealTimeIsUniversal`：`REG_DWORD 0x1`，UTC 时间已设置（7.5）。
另外 `powercfg /a` 显示这台是 `Standby (S0 Low Power Idle)`，即 Modern Standby，
S1/S2/S3 都不可用。这会影响 Linux 侧的睡眠方式，第 10 章的合盖睡眠验证要留意。

**17. 教程里 `bcdedit` 的 PowerShell 写法有问题（做之前发现的）。**
`bcdedit /set {bootmgr} ...` 在 PowerShell 里花括号会被当成脚本块，不会按预期执行。
要么用管理员 cmd，要么给花括号加单引号。教程原来写的是「管理员 PowerShell」加不带引号的写法。
**这是从 PowerShell 的已知行为推断的，没有实际在这台上试过错误写法。**
改了：11.5 节、附录 C、MIGRATION.md 6.5 节。

**18. 第 11 章双系统验证完成：bcdedit 兜底、从 rEFInd 进 Windows、共享盘、时间都正常。**
- Windows 里 `bcdedit /enum '{bootmgr}'`：`device partition=\Device\HarddiskVolume1`
  （Windows 自己的 ESP），`path \EFI\refind\refind_x64.efi`。
  改之前的基线输出没有保留，所以「原来是 bootmgfw.efi」这一点没有实测记录。
- 重启后先出 rEFInd，从菜单选 Windows 11 能正常启动。
- 回到 NixOS：`touch` 再 `rm` `/mnt/share` 里的文件成功，共享盘在进过 Windows
  之后仍然可写。这是「快速启动和休眠已关」的真正检验，比之前没进过 Windows
  时的可写更有说服力。
- `date` 是 `2026年 10月 1日 00:12:34 JST`，和前面的日志时间线（截图 PNG 在
  23:50 生成）对得上，没有差 9 小时，UTC 设置生效。这一条是对照日志时间线判断的，
  没有拿外部时间源核对。

**19. SSH 密钥和提交签名链打通，asus 的装机改动已提交并推送。**
顺序和实测：
- toru 在 asus 上亲手 `ssh-keygen -t ed25519 -C "asus"`，私钥没有被任何 Claude 会话读过，
  只读了公钥。`~/.ssh` 是 0700，私钥 0600。
- toru 在 GitHub 网页上把同一把公钥登记了两次：Authentication key 和 Signing key。
- `ssh -T git@github.com` 返回 `Hi SenorToru! You've successfully authenticated`。
  第一次连接的主机指纹 `SHA256:+DiY3wvv...` 和 GitHub 公布的 ED25519 指纹核对一致后才输入 yes。
- remote 从 https 换成 `git@github.com:SenorToru/nixos-config.git`。
- 合并 thinkpad 上推的提交之前，先 `fetch` 加 `diff --stat HEAD origin/master` 做只读的重叠检查：
  上游只改了三个文件，和 asus 本地改的五个文件没有重叠，才 `git pull --ff-only`，快进成功，
  本地改动原样保留。装机的真实结果就是靠这道检查没有被冲掉。
- `home/toru.nix` 的 `signingKeys` 加了 `asus` 一行。提交前用户态构建了系统层和 home 层，
  确认 `allowed_signers` 里 asus、bluefin、thinkpad、vm 四个键名都在（输出是字母序，
  因为 `lib.mapAttrsToList` 按属性名排序，不按书写顺序，无害）。
- toru 提交并推送，**GitHub 上显示 Verified**，说明 Signing key 登记正确。
还没做的：asus 本地的 `git log --show-signature` 要等 asus `nrb` 一次，
`allowed_signers` 才带上新公钥；thinkpad 要 `git pull` 再 `nrb`，才认得 asus 签的提交
（MIGRATION.md 7.3 节说的那个不对称）。
一个教训：**两台机器各有一份仓库工作区、又各改不同文件时，先 fetch 看重叠再 pull，
不要盲目 pull。** 这次靠它保住了 asus 上没提交的装机结果。

### 2026-10-01（续）

**20. 第二天：两台 nrb、修好的 refind-hwinfo 实测、合盖睡眠、固件更新。**
asus 上的 Claude 汇报，输出原样：
- **提交签名本地验证通过。** asus 提交 `61c86f7` 的 `git log -1 --format='%G?'` 是 `G`
  （Good signature），已推送，`origin/master` 与本地一致。两台都 `nrb` 之后，`allowed_signers`
  生效（asus 的是 generation 5）。
- **修好的 `refind-hwinfo` 在 asus 真机上重跑，igpu 和 dgpu 两行不再标反。** 生成结果：
  igpu `AMD RADEON 840M / 860M GRAPHICS / SHARED`，dgpu `NVIDIA GEFORCE RTX 5060 MAX-Q / MOBILE`
  （NVIDIA 没有显存节点，所以没有显存后缀，这是判据的设计，不是遗漏）。
  内存行从 `32768M LPDDR5` 变成 `32768M`，原因是内存代数要 `dmidecode`，而它要 root，
  **不加 sudo 跑就没有这一段**（脚本注释里本来就说过）。要保留 LPDDR5 就必须 `sudo refind-hwinfo`。
  这也意味着 hwinfo.nix 变了，要 `nrb` 加 `sudo refind-sync` 才会更新 ESP 上那张背景图。
- **合盖睡眠再唤醒：两台机器都正常，屏幕没有花屏。** 之前担心的 Modern Standby、独显电源管理、
  背光服务失败，在这个测试里没有表现出问题。这一条只测了一轮合盖，不等于长期稳定。
- **固件更新：** GNOME Software（经 fwupd/LVFS）提供了一个 Secure Boot dbx 更新，
  `UEFI dbx 20250902 → 20260707`，状态 Success，已重启。这台 Secure Boot 是关着的
  （`bootctl` 显示 disabled），所以这个更新不影响当前任何引导。
- **固件启动项：** `Boot0000`（标签 Windows Boot Manager）现在指向
  `\EFI\refind\refind_x64.efi`，也就是说 Windows 按 `{bootmgr}` 的 `path` 重写了自己的启动项，
  **这正是 11.5 节 `bcdedit` 兜底设计的效果，是一次间接的实测**。另外多出一条
  `Boot0004`（同样标签 Windows Boot Manager，指向 `bootmgfw.efi`），排在 `BootOrder` 末尾。
  谁建的没有查清（Windows、固件或 dbx 更新都有可能），无害。

**21. NVMe 设备名在两次启动之间对调了，所以 `/dev/nvmeXn1` 不能写死。**
asus 上第一天启动时 KIOXIA 是 `nvme1n1`、Samsung 是 `nvme0n1`；第二天一次启动后反过来，
KIOXIA 成了 `nvme0n1`、Samsung 成了 `nvme1n1`。`refind-sync` 的日志也跟着变：
前两次是 `disk=/dev/nvme1n1 part=1`，这次是 `disk=/dev/nvme0n1 part=1`。
**`refind-sync` 没受影响**，因为它是从 `/boot` 的挂载点反推磁盘和分区号的，
新建的 `Boot0001` 指向的分区 PARTUUID 仍是 `bded4d87-...`（KIOXIA 的 ESP）。
挂载用的是 UUID，也不受影响。
这印证了教程一开始就强调的做法：**认盘靠型号、容量、卷标、PARTUUID，不靠 `nvme0n1`/`nvme1n1`
这种编号**（9.1 节用 by-id，9.9 节从挂载点推磁盘）。教程里凡是用 `lsblk` 示意的地方，
编号都只是示例，可能和你机器上实际的对调。同理，连着内置屏的 `card` 编号
也会在重启之间变（附录 E 第 15 条）。

### 2026-10-02

**22. 主题改成每台机器声明，不再跨机器同步。**
`~/.local/state/theme/current` 以前在 `state-sync` 的 B 类清单里，asus 一还原就会被 thinkpad 的
主题盖掉，而且这个文件在 `$HOME` 里，重装系统就丢。改成每台机器在
`hosts/<主机>/default.nix` 里用 `custom.defaultTheme` 声明（thinkpad 是 everforest，asus 是 kanagawa），
状态文件没有内容时 `restoreTheme` 回落到它；`theme` 命令切到和声明不同的主题时会提醒。
两台机器 `nrb` 之后主题没有变化，符合预期。

**23. `state-sync restore` 是全量覆盖，不能整份还原到不同硬件的机器上。**
读 `home/migration.nix` 时发现它对每个路径先 `rm -rf` 再 `cp -a`，没有只还原几项的参数；
清单里 `fcitx5/profile`（键盘布局）、`monitors.xml`、目标机器已有的 `~/.claude/settings.json`
都是跟着机器走的。asus 上实际是手工选择性还原的，核对过的做法写在 MIGRATION.md 7.1 节。
**走到这一步才发现，说明这一类问题要在设计 B 类清单时就想：一项状态是跟着人走还是跟着机器走。**
计划但还没做：给 `restore` 加路径参数。

**24. 选择性还原的实际结果。**
- Mozc：asus 上原来没有 `.history.db` 和 `.encrypt_key.db`，复制六个数据库文件、`chmod 600`、
  `fcitx5-remote -r`，toru 亲自打日文验证学习记录带过来了。
  **停 `mozc_server` 要用 `pkill -x`，不要用 `pkill -f`**：`-f` 匹配整条命令行，
  写在含 `mozc_server` 字样的 `bash -c` 里会把执行它的 shell 自己杀掉（实际踩到，退出码 144，
  后面的步骤没有跑、文件没被动过）。
- `~/.claude/settings.json`：asus 上原来只有 55 字节（两个键），还原成和 thinkpad 逐字节一致，
  包括 `autoMode`。thinkpad 后来给 Sonnet 5.5 单独设了 effort medium，再同步一次，三条
  `modelSettings` 一致。`autoMode` 只在用户级设置里被读取（文档明确说项目里的 `.claude/settings.json`
  和 `.claude/settings.local.json` 被故意忽略），所以必须放 `dotfiles-state`，不能放进 public 的仓库；
  它由 Claude Code 的 `/auto-mode-setup` 生成，内容是你生产环境的描述（文件名、域名、服务名，
  没有密钥），仓库 `dotfiles-state` 是 private，`nixos-config` 是 public，两者我都用 `gh` 核对过。
- Grok：asus 上第一次运行之后自己生成了一份只有 7 行的 `config.toml`，把 thinkpad 的 `[ui]`、`[cli]`、
  `[models]` 三段追加过去，包括 `permission_mode = "always-approve"`（toru 在动手前亲口确认）；
  **不带 `[privacy]`**（那是在 thinkpad 上确认隐私提示的记录，asus 上要自己看一眼再确认）和
  **`[plugins]`**（asus 上没装 cloudflare 插件）。TOML 用 Python 的 `tomllib` 校验合法，和 thinkpad 的
  diff 正好只差那两段。

**25. 会话历史和记忆一次性迁移（Claude Code 四个项目 + Grok），走外接 U 盘。**
范围：Claude 的 nixos-config、amemusubi、craft-crm、shukuba 四个项目目录，Grok 的 `sessions`、`memory-v2`、
`memtrace`。凭据（`auth.json`、`mcp_credentials.json`）、`agent_id`、`trusted_folders.toml` 不搬。
要点和教训：
- 里面是完整对话内容，**只走外接硬盘，用完删**，不进 git、不上云。U 盘上单独建一个目录，和原有的
  备份分开。
- 生成 `MANIFEST.sha256`，在目标机器上先校验 U 盘没读坏，复制完逐个文件和 U 盘比对
  （171 + 385 = 556，和清单行数一致）。
- **正在被写入的会话文件不要复制**：thinkpad 上当时在写的那一个单独留到会话结束之后。
- **exFAT 存不了符号链接，也没有 Unix 权限位**：Grok 的 `poster-gen → post-gen` 别名要在目标机器上手工
  补；复制过去的文件要把目录收紧成 700、文件收紧成 600。
- Claude 用 `cp -rn` 不覆盖已有文件（目标机器上自己正在写的会话文件因此没被动）；
  Grok 的三个目录因为里面有搜索索引 `session_search.sqlite` 和不按会话分的 `memory-v2/global`，
  不能合并，用「先整体挪到备份、再整体替换」。
- 迁移前先备份目标机器的现状，toru 亲自用 `claude --resume` 和 Grok 验证之后才删备份和 U 盘副本，
  删之前 `ls` 一遍、路径写完整、不用通配符。
- 搬完之后两台机器上同一个项目的会话和记忆各自继续长，**不会自动合并**。

**26. 默认输入法：不用手工改 `DefaultIM`，我原来的理解是错的。**
toru 的要求是两台机器默认都用英文输入（thinkpad 用日语键盘布局输入英文，asus 用英文键盘布局），
Rime 和 Mozc 都保留、需要时手动切。我最初以为 `profile` 里的 `DefaultIM` 是「启动时用哪个」，
就把 thinkpad 改成 `keyboard-jp`、asus 改成 `keyboard-us`，`fcitx5-remote -r` 之后没被改回，
asus 上 toru 看到新窗口是英文，就当作做成了。
**这个判断站不住：**
- `~/.config/fcitx5/config` 里 `ActiveByDefault=False`、`ShareInputState=No`，意思是每个新的输入上下文
  一开始处于「未激活」状态，也就是 `profile` 里**排第一的那一项**（这两台都是键盘布局那一项）。
  所以两台机器原来就是默认英文输入，和 `DefaultIM` 无关；asus 上「新窗口默认是英文」的验证
  在我改之前大概也是成立的，没有区分度。
- 之后看到 thinkpad 的 `profile` 在 14:59:34 被写回了 `DefaultIM=rime`。我没有证据证明是谁写的，
  合理的推测是 fcitx5 自己：`DefaultIM` 更像「`Ctrl+Space` 激活时用哪个」，会随最近用过的输入法更新。
  这一条是推测，没有查 fcitx5 的源码或文档。
结论：**默认英文已经满足，不要手工管 `DefaultIM`。** asus 上我改的那处很可能同样会被 fcitx5 写回，无害，
不用再改回来。这个文件仍是 B 类、跟着机器走（里面有键盘布局），不要整份还原到另一台机器上。

**27. Syncthing 在两台机器之间配对完成，保险箱在 asus 上配好。**
两边都是 Syncthing v2.1.3，只有用户服务在跑（asus 上系统级的 `syncthing.service` 是 inactive，不会抢数据库）。
设备 ID 用 `syncthing device-id` 取（只读证书，不碰 `config.xml` 里的 API 密钥），在两边的网页界面里互相添加，
再对六个文件夹各自在「共享」里勾上对方，**两边都要点**，因为文件夹两边都已经由 `home/syncthing.nix` 声明好了。
配对前的摸底发现一个我记错的点：asus 的 `~/Pictures/library` 里不是空的，有我们 9 月 30 日存的 rEFInd 截图
PNG；它是从 asus 同步到 thinkpad 的，方向和其他五个相反，无害。保险箱（`secrets`）先保持两边都可写，
「只让 asus 能改保险箱」等 asus 成为主力之后再做。

**28. Bluefin 的备份按「事业分开」归位到 asus（外接 U 盘，复制类批次）。**
Toru 同时运作几个事业，所以 `~/Documents/library` 的编号表在个人事务（10–59）之外加了
`70–79 事业`（71 TORU-LEATHERS 网店、72 BELLATECH 化妆品且正在退出）和 `80–89 软件开发项目`
（81 CRAFT-CRM、82 poster-gen），事业编号下面每件东西自己一个文件夹。这份规矩文件
`00 怎么放文件.md` 本身在 Syncthing 的 library 里，改完自动同步。
分五批复制：A（library 里的个人和事业文件）、B（Obsidian 库进 `~/Documents/notes`、图片按修改日期进
`Pictures/library/年/月`、bruno 进 `~/Documents/bruno` 且不同步）、C（私人媒体，不同步、中性编号名、
不留对照表）、D（三个恢复码和生产密钥进 Cryptomator 保险箱 `~/Secrets`）、E（Downloads 里的 BELLATECH 和 Logo）。
要点和教训：
- **复制前先摸底**：名字、数量、大小，不打开内容，需要判断归属的才列名字。
- **保险箱必须先解锁再复制，复制前用 `findmnt ~/Secrets` 确认是挂载点**；锁着时往里放会让明文落在磁盘上，
  下次解锁还会失败。三个凭据文件复制时不打开、不回显，只报名字和大小。
- **Obsidian 库自带旧机器的 `.stfolder`**：目的地本身已是 Syncthing 文件夹，用 `tar --exclude=./.stfolder`
  复制，别把旧标记混进来。
- **U 盘被 macOS 用过，里面有隐藏的 AppleDouble 元数据文件（`._名字`，4096 字节）**，`ls` 看不到，
  `find` 会带上。批 C 的脚本没排除它们，它们排在最前面，占了 6 个视频和 46 个音频里的编号位置（5 个）。
  用文件头魔数 `00 05 16 07` 确认是元数据后，删掉这两个副本目录、在 `find` 里加 `! -name '._*'`
  重做，得到干净的编号。**以后在 macOS 用过的外接盘上复制，`find` 一律排除 `._*` 和 `.DS_Store`。**
  源里被我误判成「有子目录」的数量差，其实就是这些隐藏文件。
- exFAT 会把文件名规范成预组合的 Unicode 形式（NFC），一个日文文件名「ズ」在源里是 NFD 的两个字符、
  到目的地变成一个字符，`diff -rq` 因此报不同而内容 `cmp` 一致。核对用内容和数量，别只靠 `diff`。
- exFAT 没有 Unix 权限位，复制后文件都是 755，要手工收紧：身份证件和私人媒体 700/600，其余 755/644。
- 删除（含重做时删掉自己复制出来的副本）一律要明确批准，且删之前先 `ls` 要删的东西、路径写完整。
- 完成后 U 盘上的 `bluefin-backup` 里仍有原件（含恢复码明文、身份证件、私人媒体的原名），
  是否清掉由 Toru 决定，我们不替他删。

**29. 第 13 节整体验证在 asus 上全部通过，并清理虚拟机相关内容。**
由 asus 上的 Claude 跑只读命令，toru 亲手跑 `sudo ls`，应用由 toru 亲自逐项试过：
主机名、内核 6.18.52、四个子卷 `zstd:3`、只有 zram、两个 Windows 分区挂载、NVIDIA 驱动和 offload、
字体、zsh、`fwupd`、DNS（`192.0.2.1` 超时）、固件启动项（rEFInd 第一、`Linux Boot Manager` 在、
`Boot0000` 指向 rEFInd）、两个 ESP 里都有 `refind.conf`、`refind_x64.efi`、`themes`、仓库没有 root 属主文件。
`migration-check` 只多报了 `~/.nv`（NVIDIA 驱动的着色器缓存，能自动重建，已加进忽略清单）和 4 个手工装的
VS Code 扩展（清单里本来就有，是提醒）。`state-sync status` 的 5 处差异都在预期内：`profile`、`conf`、
`monitors.xml` 是每台机器各自的，`.grok/config.toml` 差 `[privacy]` 和 `[plugins]`，`mozc` 是还原之后又学了新词。
**asus 真机双 ESP 跑通之后，删除了虚拟机相关内容**：`hosts/vm/`、`flake.nix` 里的 `vm` 条目、`REHEARSAL.md`，
以及 README、MIGRATION 里指向它们的引用，`home/syncthing.nix` 里「vm 不参与文件同步」的特例也一并拿掉。
保留：`signingKeys` 里 vm 的公钥（它签过的提交要能验）、`Lesson-Learn` 里的历史记录。
演练记录在 git 历史里，需要时 `git log -- REHEARSAL.md`。
一个小教训：我一直往同一个 `GIT_COMMIT_MESSAGE.txt` 里追加，toru 每次提交都用它，
结果最近三个提交标题完全一样但内容不同。**每次提交前重写这个文件，只描述这一次的改动。**

### 待补

- 华硕的 BIOS 键具体是哪个（启动菜单键已确认是 Esc）
- 保险箱 secrets 现在两边都可写；asus 成为主力之后，把 thinkpad 和 Mac 上的「保险箱」文件夹改成「仅接收」
- Grok 在 asus 上还要 toru 亲手做两件事：确认隐私提示、装 cloudflare 插件
- 计划但还没做：给 `state-sync restore` 加路径参数；把 autoMode 拆成通用条目

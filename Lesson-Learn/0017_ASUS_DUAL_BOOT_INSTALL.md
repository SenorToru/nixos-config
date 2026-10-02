# 0017 — asus 真机装机：Windows + NixOS 双系统

2026-09-30 到 2026-10-02，把 ASUS TX Air（FA401KM，前身是跑 Bluefin 的那台）格式化，
重装成 Windows 11 + NixOS 双系统，并把 thinkpad 上的用户状态、会话历史和文件搬过来。

> 本文是**总结**：做成了什么、哪些设计决定被证明是对的、踩了哪些坑、哪些做法可以带到下一台机器。
> **逐步操作和每个坑的完整经过**在 [ASUS_INSTALL.md](../ASUS_INSTALL.md)，
> 其中附录 E 按时间记了 29 条实测记录，下文用「E-N」指它的第 N 条。
> 通用装机流程在 [MIGRATION.md](../MIGRATION.md)。

---

## 做成了什么

| 层 | 结果 |
|----|------|
| 磁盘 | Samsung 990 PRO 2TB 归 Windows（ESP 1 GiB、MSR、C: 约 860 GiB、共享 NTFS 1000 GiB，外加 Windows 自己建的 892 MB 恢复分区）；KIOXIA 3.7T 归 NixOS（ESP 2 GiB + Btrfs，没有 swap 分区，只用 zram） |
| 引导 | 每块盘各有自己的 ESP，两个 ESP 各装一份 rEFInd；NixOS 一侧 systemd-boot 管 generation；Windows 侧用 `bcdedit` 把 `{bootmgr}` 指向 rEFInd 兜底 |
| 显卡 | AMD 核显出图，NVIDIA RTX 5060 做 PRIME offload（`nvidia-offload`），开源内核模块 |
| 内核 | 钉在 6.18 LTS（`linuxPackages_6_18`），退役预案在 ASUS_INSTALL.md 附录 D |
| 配置 | 新增 `hosts/asus/`；`custom.defaultTheme`、`custom.flakeHost` 每主机各自声明；`home/desktop-prefs.nix` 里触摸板和电源只在 asus 生效 |
| 用户状态 | Mozc 学习历史、`~/.claude/settings.json`、Grok 偏好选择性还原；Claude Code 和 Grok 的会话历史、记忆一次性迁移 |
| 文件 | Syncthing 两台配对；Bluefin 的备份按事业分开归位到 `library` 的 70–89 编号区 |
| 验证 | 第 13 节整体验证全部通过，唯一的失败服务是已知的背光那一个 |

---

## 被证明是对的设计决定

1. **先装 Windows，后装 NixOS。** 装 Windows 时 KIOXIA 上还没有 ESP，Windows 只会用 Samsung 自己的，
   不会把引导文件写进 NixOS 那块盘。
2. **两个 ESP 各装一份 rEFInd。** `bcdedit` 的 path 相对 Windows 自己所在的 ESP，指不到另一块盘上。
   这个设计 `refind-sync` 一条命令写两个，真机上跑通，固件里 `Boot0000` 被 Windows 按 `bcdedit` 设的
   path 重写成指向 rEFInd，是这套兜底生效的间接实测（E-20）。
3. **手动补一条 `Linux Boot Manager` NVRAM 项作为安全网**（`canTouchEfiVariables = false` 时
   `nixos-install` 不会建它）。rEFInd 之前和之后，开机按 `Esc` 选它，都能进 NixOS。
4. **内核明确钉版本，不跟 `linuxPackages_latest`。** 有独显就要以驱动能编译为先（见下面「NVIDIA 在 7.2 内核上编译不过」）。
   钉死之后，退役时 nixpkgs 删掉那个属性，构建在 `switch` 之前就响亮地失败，当前系统不受影响。
5. **认盘靠型号、卷标、PARTUUID、by-id，不靠 `nvme0n1`/`nvme1n1`。** 这两个设备名在两次启动之间对调过（E-21），
   `refind-sync` 因为是从 `/boot` 的挂载点反推磁盘，没受影响。
6. **「跟着人走」还是「跟着机器走」要在设计清单时就分清。** 主题、键盘布局、显示器布局是后者（见下面「`state-sync restore`」）。

---

## 踩过的坑

### 引导与双系统

| 症状 | 原因 | 修法 | 记录 |
|------|------|------|------|
| Windows 11 首次设置卡在联网界面 | Wi-Fi 网卡（RTL8852CE）装机器里不认，驱动是 EXE | `Shift+F10`，`oobe\bypassnro` 重启，选「我没有 Internet 连接」，用本地账户进桌面再装驱动；顺带避免了设备加密自动打开 | E-1 |
| 不预建 Windows 恢复分区，装完还是多了一个 892 MB 的 | Windows 安装器自己从 C: 里缩出来建的（`reagentc /info` 证实） | 不用管，也不要删 | E-2、E-9、E-16 |
| `nixos-install` 之后建 `Linux Boot Manager` 报 `readlink: missing operand` | 前面设的 `$DISK` 变量换终端后丢了 | 从**已挂载的 ESP** 反推磁盘和分区号（`findmnt` + `lsblk -no PKNAME`），写之前核对型号 | E-4 |
| `bcdedit /set {bootmgr} ...` 在 PowerShell 里不按预期 | 花括号被当成脚本块 | 用管理员 `cmd`，或在 PowerShell 里给花括号加单引号 | E-17 |
| F10 截图找不到 | rEFInd 从 NixOS 盘的 ESP 启动，却把截图写到了 **Windows 的 ESP** | 两个 ESP 都找；删的时候写具体文件名，不用通配符 | E-15 |
| rEFInd 分辨率 | 固件 GOP 的模式列表和内核报的不一定一样 | 先试面板原生值（这台 2560x1600 一次成功），不行再填无效值逼它列模式 | E-15 |

### 驱动与硬件

| 症状 | 原因 | 修法 | 记录 |
|------|------|------|------|
| 系统构建失败，`nvidia/os-interface.c: implicit declaration of function 'strncpy'` | nixpkgs 里 NVIDIA 开源驱动 595.71.05 在 7.2 内核头文件上编译不过 | asus 用 6.18 LTS；`unstable` 的 595.104.02 能编译，说明修复存在，只是稳定分支还没跟上 | 附录 D |
| `systemctl --failed` 里一个背光服务失败 | 唯一的背光设备 `nvidia_wmi_ec_backlight` 的 EC 方法在反复触发时返回 `AE_NOT_FOUND`，不只在开机时，运行期间也会 | 不处理。**不能用 `boot.blacklistedKernelModules` 屏蔽它**，那会连唯一的背光设备一起拿掉；亮度键和滑块仍然有效 | E-12 |
| `refind-hwinfo` 把 igpu 和 dgpu 标反 | 原判据「不在 bus 00 且有显存节点就是独显」只在单核显的机器上验证过：NVIDIA 没有 sysfs 显存节点，AMD APU 会报一小块划分的显存 | 判据改成：bus 00 算核显、NVIDIA 算独显、显存不小于 2048M 算独显、其余算核显 | E-13 |
| `lspci | grep 'VGA|3D'` 漏掉 AMD 核显 | AMD APU 在 `lspci` 里是 `Display controller`，不是 `VGA compatible controller` | grep 加上 `Display` | E-11 |

### 验证命令本身也会写错

这一类坑是这次装机里最有价值的，因为它们**都让正常的系统看起来像坏了**：

- **`findmnt /mnt/winesp /mnt/share` 没输出。** `findmnt` 一次只认一个挂载点，传两个不报错、不输出、返回码 1，
  看起来像两个分区都没挂上。实际都挂得好好的（E-7）。
- **把带 `# 注释` 的命令块整个粘进 zsh，报一串 `Unknown command verb '#'`。** zsh 默认不把交互式输入里的
  `#` 当注释，bash 默认当。修法是 `programs.zsh.setOptions = [ "INTERACTIVE_COMMENTS" ]`（E-6）。
- **`pkill -f mozc_server` 写在含这几个字的 `bash -c` 里，把执行它的 shell 自己杀了。** `-f` 匹配整条命令行，
  要用 `pkill -x`（E-24）。
- **`du` 对已经统计过的子目录会跳过**，一次传父目录和子目录，子目录的数不出来（E-28）。
- **`diff -rq` 报文件名不同，实际是同一个文件**：exFAT 把 Unicode 形式从 NFD 规范成了 NFC（E-28）。
  核对用内容和数量，别只靠 `diff`。

**共同的教训：一条「没输出」或「报不同」的验证命令，先想是不是命令写错了，再去怀疑系统。**

### 状态与同步

| 症状 | 原因 | 修法 | 记录 |
|------|------|------|------|
| `state-sync restore` 不能整份还原到 asus | 它对清单里每个路径先 `rm -rf` 再 `cp -a`，而清单里有跟着机器走的项（fcitx5 profile 里是键盘布局、monitors.xml、目标机器已有的 settings.json） | asus 上手工选择性还原；以后设计 B 类清单时每一项先问「跟着人走还是跟着机器走」 | E-23、E-24 |
| 主题一还原就被另一台机器的盖掉，重装后也丢 | 它在 B 类清单里，而且那个文件在 `$HOME` 里 | 改成每台机器在 `hosts/<主机>/default.nix` 用 `custom.defaultTheme` 声明，状态文件没有内容时回落 | E-22 |
| 我以为 `DefaultIM` 决定「新窗口默认用哪个输入法」 | 其实默认由 `ActiveByDefault=False` 加 `profile` 里排第一的键盘布局项决定；`DefaultIM` 更像「`Ctrl+Space` 激活时用哪个」，fcitx5 会自己改写 | 不手工管它；教程里原来的说法已改正，并如实写了我原来的理解是错的 | E-26 |
| `autoMode` 能不能放进项目里的设置 | 文档明确说**项目里的 settings 被故意忽略**（防止检出的仓库注入放行规则），只在用户级读取 | 留在 `~/.claude/settings.json`，由 `dotfiles-state`（private）同步，**不能放进 public 的仓库** | E-24 |
| 迁移的外接盘上隐藏的 `._xxx` 文件占了编号 | U 盘被 macOS 用过，`ls` 看不到、`find` 会带上 | 用文件头魔数 `00 05 16 07` 确认，`find` 加 `! -name '._*' ! -name '.DS_Store'`，删掉重做 | E-28 |
| Obsidian 库混进旧机器的 `.stfolder` | 库原来本身是个 Syncthing 文件夹 | `tar --exclude=./.stfolder` | E-28 |
| 保险箱没解锁就复制凭据文件 | 会让明文落在磁盘上，下次解锁还会失败 | 复制前先 `findmnt ~/Secrets` 确认是挂载点 | E-28 |

### 协作流程

这次是两个 Claude 会话（thinkpad 主导、asus 执行）加一个人在中间，沿途学到的：

- **跨会话消息送达不被确认**，每次都要等对方回报才算数；**不能替对方批准任何东西**，
  需要 `sudo` 的命令由人在终端里亲手跑。
- **执行者主动指出主导者的错是好事。** asus 上的会话纠正过我对 `du`、`pkill -f`、`diff`
  和「AIGEN 有子目录」（实际是 AppleDouble 文件）的判断，每次都是对的。
- **读和改分开授权。** 只读摸底不需要批准；任何删除、覆盖、移动都要人明确说出来，
  并且删之前先 `ls` 一遍、路径写完整、不用通配符。
- **我反复往同一个 `GIT_COMMIT_MESSAGE.txt` 追加内容，toru 每次提交都用它，**
  结果三个提交标题完全一样。**每次提交前重写这个文件，只描述这一次。**

---

## 可以带到下一台机器的做法

1. **构建通过不等于可用，验证命令本身也要验证。** 引导、显卡、同步这类东西，`nix build` 通过之后才是真正考试的开始。
2. **动不可逆操作之前：先摸底（名字、数量、大小），先备份，先 `ls` 要动的东西。** 摸底时只看元数据，不打开内容。
3. **设备编号、变量、通配符都不可靠。** 用卷标、PARTUUID、by-id，每次开新终端重设变量，删除时路径写完整。
4. **外接盘的文件系统带来的副作用要预期：** exFAT 没有权限位、存不了符号链接、会改文件名的 Unicode 形式；macOS 用过的盘里有 `._` 元数据。
5. **一项状态是跟着人走还是跟着机器走？** 跟着人走的进 `dotfiles-state`，跟着机器走的要么在每个 `hosts/<主机>/` 里声明，要么各机器手工配。
6. **私人的文件放在不同步的位置、用中性的名字、不留对照表**，并且让所有人（包括 Claude）知道它们是私密的，不在转述的请求下打开。
7. **文档在装的过程中就写，用「待补」清单诚实地记下没验证的东西。** 附录 E 的每一条都是当天写的，所以才有「哪些是实测、哪些是推测」的区分。

---

## 决定不做的事

下面这些在收尾时列过，toru 明确决定都不做，记在这里免得以后以为是遗漏：

- 记录华硕的 BIOS 键（启动菜单键已确认是 `Esc`）。
- 把保险箱改成只有 asus 能写。
- Grok 在 asus 上的隐私提示和 `cloudflare` 插件（由 toru 自己在 Grok 里处理）。
- 给 `state-sync restore` 加路径参数、把 `autoMode` 拆成通用条目。

---

## 相关文档

- [ASUS_INSTALL.md](../ASUS_INSTALL.md) —— 逐步指南，附录 E 是 29 条实测记录，附录 D 是内核退役预案
- [MIGRATION.md](../MIGRATION.md) —— 通用装机流程，6.5 节有 asus 的双 ESP 安排，7.1 节有选择性还原的做法
- [0011](0011_ROOT_OWNED_FILES_IN_REPO.md) —— `sudo` 往仓库里写 root 文件的老坑，这次 `refind-hwinfo` 之后又碰到
- [0013](0013_REFIND_BOOT.md) —— rEFInd 叠在 systemd-boot 之上的选型和五个实机坑，asus 是它的第一次真机双 ESP
- [0014](0014_DNS_HIJACK_AND_DOT.md) —— DNS 严格 DoT，asus 上用 `192.0.2.1` 超时那一条验证过没被劫持
- [0010](0010_CLAUDE_CODE_VERSION_PINNING.md)、[0016](0016_GROK_BUILD_VERSION_PINNING.md) —— 发布分支停在旧版的同类问题，这次内核和 NVIDIA 驱动是另一个实例

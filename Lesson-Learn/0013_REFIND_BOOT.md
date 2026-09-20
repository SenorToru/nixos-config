# 0013 — rEFInd 做顶层引导入口

把 rEFInd 叠在 systemd-boot 之上，作为多系统选单和好看的开机画面。
主题按本机分辨率与硬件参数生成。

> 本文记录的是**选型推理**和**五个实机才暴露的坑**。
> 操作步骤（装新机器、把已有机器导入 rEFInd）在
> [MIGRATION.md](../MIGRATION.md) 第 6 和第 9 节。

---

## 想要什么

- 开机有个能选系统的顶层入口，将来加 Windows 双启动时不用改 NixOS 的引导
- 高分屏下不糊（GRUB 在 HiDPI 下缩放拉伸、字体模糊）
- **NixOS 的 generation 回滚安全网一点都不能丢**

最后一条是硬约束。generation 菜单是这个系统最重要的救命机制，
任何让它变弱的方案都不考虑。

---

## 为什么没用官方的 `boot.loader.refind`

`nixos-26.05` 里**确实有**这个官方模块
（`nixos/modules/system/boot/loader/refind/refind.nix`）。读完源码之后放弃了：

### 1. 它和 systemd-boot 互斥

```nix
# Common attribute for boot loaders so only one of them can be
# set at once.
system.boot.loader.id = "refind";
```

注释是上游自己写的。`boot.loader.systemd-boot.enable` 也设这个 attribute，
两个一起开会直接报选项冲突。

也就是说**「rEFInd → systemd-boot → generations」这种两层结构，官方模块不提供**。
用它就意味着 rEFInd 取代 systemd-boot 去管 generation。

### 2. 它把每个 generation 摊成一条顶层菜单项

`refind-install.py` 的 `install_bootloader()` 遍历所有 generation，
对每一个调 `generate_config_entry()`，生成的是**平铺的 `menuentry`**：

```python
for (profile, gens) in profiles:
    for gen in sorted(gens, key=lambda x: x, reverse=True):
        config_file += generate_config_entry(profile, gen, isFirst, group_name)
```

只有当某个 generation 带 NixOS 级 `specialisation` 时才会用 `submenuentry`
折叠。本仓库的 20 套主题是 **home-manager 的 specialisation**，
不进 `boot.json`，所以不触发折叠。

结果就是菜单里排着一长串 NixOS 图标 —— 正好毁掉选 rEFInd 的理由。

### 3. 它每次 rebuild 整个重写 `refind.conf`

只有 `extraConfig` 会被前置保留，其余全部覆盖。

### 4. 成熟度存疑

模块是从 limine 模块复制来的，**没改干净**：

```python
print('warning: boot.loader.efi.canTouchEfiVariables is set to false while boot.loader.limine.efiInstallAsRemovable.')
...
# If there's already a Limine entry, replace it
```

功能大概率没问题，但这说明用的人不多。引导是坏了就开不了机的东西，
不想当第一批踩雷的人。

---

## 采用的架构

```
UEFI 固件
   │
   ▼
rEFInd                      顶层入口，只负责好看和选系统
   ├──> Windows Boot Manager     （将来双启动时）
   └──> systemd-boot             \EFI\systemd\systemd-bootx64.efi
           └──> NixOS 全部 generation（回滚安全网完整保留在这一层）
```

rEFInd **不由 `boot.loader` 管**。仓库用 Nix 把素材声明式地备好
（rEFInd 二进制、按本机参数生成的主题、`refind.conf`），
再由 `refind-sync` 这条**手动跑**的命令写进 ESP。

配置在 [`modules/refind.nix`](../modules/refind.nix)，
本机参数在 `hosts/thinkpad/default.nix` 和 `hosts/thinkpad/hwinfo.nix`。

**为什么让它手动而不是挂到 activation 上：**
引导坏掉等于开不了机，是全仓库风险最高的一处。
`nixos-rebuild` 每天要跑好几次，让它每次都有机会写引导分区，
收益（省一条命令）远小于风险。现在 `nrb` 永远不碰 ESP 的 rEFInd 目录。

---

## 必须关掉 `canTouchEfiVariables`

```nix
boot.loader.efi.canTouchEfiVariables = false;
```

保持 `true` 的话，systemd-boot 每次 `switch` 都会把自己设回 UEFI 启动顺序
第一位，rEFInd 永远轮不到 —— 正好抵消装它的意义。
`modules/refind.nix` 里有一条 assertion 守着这个。

**关掉它不会删除已有的 NVRAM 项**，只是不再更新。
这一点是整个安全网的基础，下一节详述。

---

## 意外发现：这台机器原本不是从 `Linux Boot Manager` 启动的

装之前查 NVRAM，本以为会看到 systemd-boot 排第一。实际是：

```
BootCurrent: 0019
BootOrder:   001B, 0002, 0001, 0000, 0017, 0018, 0019, 001A, 001C, 0021, 0003
             USB   Limine Bazzite Win  USBCD USBFDD NVMe0 ...        ... Linux Boot Manager
                                                    ↑ 实际从这里启动      ↑ 排最后
```

`Boot0019 NVMe0` 是**固件的通用设备项**，不指向任何具体的 `.efi`，
启动时走 UEFI 的可移动回退路径 `\EFI\BOOT\BOOTX64.EFI`。
systemd-boot 装了两份（`\EFI\systemd\` 和 `\EFI\BOOT\`），实际生效的是回退那份。

前面那几条 `Limine` / `Bazzite` / `Windows Boot Manager` 指向**不存在的分区**
（以前装别的系统留下的），固件挨个试失败后才轮到 NVMe0 —— 这就是开机时那几秒空白。

### 这意味着安全网有两条独立的路

| 路径 | 怎么触发 | `refind-sync` 碰吗 |
|------|----------|-------------------|
| `Boot0003` → `\EFI\systemd\systemd-bootx64.efi` | F12 手动选 `Linux Boot Manager` | 不碰 |
| `Boot0019 NVMe0` → `\EFI\BOOT\BOOTX64.EFI` | rEFInd 的 NVRAM 项失效时固件**自动**落下来 | 不碰 |

`refind-sync` 只写 `\EFI\refind\`。**即使 rEFInd 完全失败，机器也会自己退回
systemd-boot 正常开机**，连 F12 都不用敲。

### 动手前把退路实际走一遍

这次是先重启、敲 F12、**选 `Linux Boot Manager` 真的进了一次系统**，
才开始改引导的。`BootCurrent` 从 `0019` 变成 `0003` 是这件事的证据。

> **这应该是固定环节，不是可选项。**
> 「理论上有退路」和「亲手走过一遍退路」是两回事。
> 动引导之前那 3 分钟，换来的是出事时不用慌。

那三条死项后来清掉了：

```bash
sudo efibootmgr -b 0000 -B   # Windows（\EFI\Microsoft\ 已不存在）
sudo efibootmgr -b 0001 -B   # Bazzite（分区不存在）
sudo efibootmgr -b 0002 -B   # Limine（分区不存在）
```

`-B` 会同时把该项从 `BootOrder` 里摘掉。

> 顺带一个小坑：`sudo efibootmgr -b A -B && sudo efibootmgr -b B -B` 这种
> 用 `&&` 串起来的写法，实测只有第一条生效。分开跑。

---

## 五个实机才暴露的坑

这五个的共同特征：**`nix build` 全部通过，全部只在实机上炸**。

### 坑 1 — `icon` 的路径基准和 `banner` 不一样

**症状**：菜单里本该是 256×256 NixOS 图标的位置，显示一个约 32×32 的
黄黑斜条小方块（rEFInd 内置的「图片加载失败」占位符）。
而**同一个目录下**经 `icons_dir` 加载的功能图标（关机、重启等）一切正常。
背景图也正常。不报任何错。

**原因**：rEFInd 自身的路径基准不一致。

| 指令 | 位置 | 路径相对于 |
|------|------|-----------|
| `banner` | theme.conf | **rEFInd 目录** |
| `icons_dir` | theme.conf | **rEFInd 目录** |
| `icon` | menuentry 内 | **ESP 卷根** |

按前两个的规则写成 `icon themes/finn-term/icons/os_nixos.png`，
rEFInd 会去找 `<ESP>/themes/finn-term/icons/os_nixos.png` —— 那里什么都没有。

上游 `refind.conf-sample` 里 6 处 `icon` 示例全是绝对路径：

```
icon EFI/refind/icons/os_linux.png
icon /EFI/refind/icons/os_arch.png
icon \EFI\refind\icons\os_win.png
```

**修复**：写成从卷根算起的绝对路径，且路径和 `refind-sync` 的写入目录
**共用同一个 nix 变量**，不在两处各写一份：

```nix
refindDir = "/EFI/refind";
themeDir = "${refindDir}/themes/finn-term";
```

**排查心得**：占位图的**尺寸**是关键线索。它约 32×32，
比 `big_icon_size 256` 小一个数量级 —— 说明渲染的不是主题里的任何图标
（那些都是 256×256），而是 rEFInd 内置的东西。
如果只看「图标不对」而不看尺寸，很容易误判成图标文件损坏。

### 坑 2 — 固件 GOP 不一定提供 1920×1080

**症状**：rEFInd 启动时报所指定的分辨率模式不存在。

**原因**：`resolution` 只能从 UEFI GOP **实际提供**的模式里挑，
不是常见分辨率就一定有。这台 ThinkPad X1 Yoga 给的是：

```
Mode 0: 2560x1440   面板原生
Mode 5: 1600x1200   4:3
Mode 6: 1920x1440   4:3
```

**压根没有 1080p。** 当初填 1920×1080 的理由是「1080p 哪个固件都支持吧」——
这个直觉是错的，而且错得很彻底。

**修复**：填 2560×1440（面板原生，正好是 Mode 0）。

**流程上的结论**：**每台新机器都必须先装上去看固件报什么，再回来填。**
没有能提前探测的办法 —— GOP 模式列表只有在固件环境里才拿得到。
想主动列出全部模式，把 `resolution` 临时设成一个无效值（如 `1 1`），
rEFInd 启动时会把支持的模式全列出来。

### 坑 3 — vfat 上 `chmod` 返回 EPERM

**症状**：`refind-sync` 在第一个文件上就中止。

**原因**：ESP 是 vfat，挂载参数 `fmask=0077,dmask=0077`，
权限位由挂载强制，文件一律 0700。内核的 vfat 驱动在 chmod 请求的模式
和挂载参数算出来的模式不一致时直接返回 EPERM。

于是 `install -Dm0644` 会在 chmod 那一步失败，配合 `set -euo pipefail`
整个脚本停住。`cp` 不加 `--no-preserve=mode` 也一样 ——
store 里的源文件是 0444，它会试图把这个模式套过去。

**修复**：

```bash
cp --no-preserve=mode <src> "$dest/..."
cp -r --no-preserve=mode <theme>/. "$esp$themeDir/"
```

让 cp 根本不发 chmod，权限交给挂载参数决定。

**为什么容易漏**：换成任何非 vfat 的目标目录都复现不了。
在 `/tmp` 里测一百遍都是通过的。

### 坑 4 — `sed` 没考虑 `efibootmgr` 输出里的制表符

**症状**：第一次跑完全正常。**第二次跑开始**，NVRAM 里堆出重复的 rEFInd 项。

**原因**：`refind-sync` 要先删掉已有的 rEFInd 项再建新的，用的是

```sed
s/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} rEFInd$/\1/p
```

但 `efibootmgr` 的输出是

```
Boot0003* Linux Boot Manager<TAB>HD(1,GPT,...)/\EFI\systemd\...
```

标签后面还跟着**制表符和设备路径**，所以 `rEFInd$` 永远匹配不上。

**修复**：先按制表符截掉设备路径再匹配。

```bash
"$efibootmgr" | cut -f1 | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} rEFInd$/\1/p'
```

**验证办法**：造一条假的 `efibootmgr` 输出喂给管道，确认新模式匹配 2 条、
旧模式匹配 0 条。不要靠肉眼读正则。

**为什么容易漏**：这是个**只在第二次运行时才发作**的 bug。
而校正分辨率必然要跑第二次 —— 如果没提前修，正好会踩上。

### 坑 5 — `$(hostname)` 不等于 `hosts/` 下的目录名

**症状**：`refind-hwinfo` 把文件写到了 `hosts/thinkpad-nixos/`，
而仓库里的目录是 `hosts/thinkpad/`。

**原因**：本仓库里这两个名字**本来就不一致**：

```
hosts/thinkpad/            目录名，也是 flake.nix 里 nixosConfigurations 的属性名
networking.hostName        = "thinkpad-nixos"
```

**修复**：加一个 `custom.refind.flakeHost` 选项显式声明仓库里的名字，
默认值是 `config.networking.hostName`（多数机器上两者相同），
本机设成 `"thinkpad"`。

**一般化的教训**：脚本里凡是要拼 `hosts/<名字>/` 或 `--flake .#<名字>` 的地方，
都不能用 `$(hostname)`。那是**运行时的主机名**，和**仓库里的标识**是两件事。

---

## 主题：按本机参数生成

用的是 [FaeArtz/refind-finn-term](https://github.com/FaeArtz/refind-finn-term)，
终端风格，黑底紫粉、CRT 扫描线、角落一段假启动日志。

它**不是一套现成的 PNG** —— `background.png`、`selection_*.png`、字体位图
都要跑 `src/gen.py` 现生成，参数是分辨率、主机名和那段启动日志的内容。

所以做成了参数化的 derivation：主题源作 `flake = false` 的 input 被
`flake.lock` 钉死，`python3 + pillow + nerd-fonts.jetbrains-mono` 全从
nixpkgs 取，每台机器在自己的 `hosts/<主机>/` 里填参数。

### 为什么用包装脚本而不是 `substituteInPlace`

`gen.py` 的配置是文件顶部一个硬编码块。直觉做法是 `substituteInPlace` 改它，
但 `BOOT_ROWS` 是**多行列表** —— 多行 `--replace-fail` 写在 nix 缩进字符串里
会被 `nixfmt` 重排缩进，缩进一变就匹配不上，构建失败且报错看不出原因。
（这个坑在 rime-frost 的 lua 补丁那里已经踩过一次，见 `CLAUDE.md`。）

改成 `import gen` 之后覆盖模块全局变量：

```python
import gen
gen.W, gen.H = 2560, 1440
gen.HOSTNAME = "thinkpad-nixos"
gen.BOOT_ROWS = [...]
gen.make_background()
```

`gen.py` 里的函数体是在**调用时**查全局的，所以覆盖完再调就够了，
上游源码一个字不用动。上游改排版、改注释、改配色都影响不到我们；
而上游要是把这些变量改名，构建会当场 `AttributeError` 失败 ——
**响亮地坏掉，比静默地拿默认值生成一张别人的壁纸好。**

`BOOT_ROWS` 的内容经 `builtins.toJSON` 落地 —— JSON 数组同时就是合法的
Python 字面量，省掉手工拼引号转义。

---

## 硬件信息：`refind-hwinfo` 生成，提交进版本库

启动画面上那几行硬件是**探测出来的**，但探测不发生在构建时 ——
Nix 构建跑在沙箱里，读不到宿主机的 PCI 设备和 sysfs。

选的是 `nixos-generate-config` 的路子：

```
refind-hwinfo                      探测并写出 hosts/<主机>/hwinfo.nix
git add hosts/<主机>/hwinfo.nix    新文件，flake 看不见未跟踪文件
nrb                                Nix 读它 -> 跑 gen.py -> 新 PNG 进 store
sudo refind-sync                   把新 store 路径拷进 ESP
```

**中间那次 `nrb` 不能省。** `refind-sync` 里的主题路径是**构建时烤死的
store 路径**，不重新构建的话新 PNG 根本不存在，sync 拷的还是旧那份。

这样成品仍然是声明式的、被 `flake.lock` 钉死的、可复现的 ——
而不是每次 `refind-sync` 现场探测、同一份配置在不同机器上出不同结果。

附带的好处：**探测判断错了不用回来调脚本，直接改 `hwinfo.nix` 就行。**
它是提交进版本库的纯文本，而且不在开机路径上，错了只是画面上一行字不对。

### 显存探测的实际情况

```
AMD 独显      /sys/class/drm/card*/device/mem_info_vram_total
Intel Arc     /sys/class/drm/card*/lmem_total_bytes
Intel 核显    两个都没有 —— 它动态共享系统内存，没有「显存容量」这个数
```

`lspci` 里 Intel 核显那个 256M 的 prefetchable BAR 是 **CPU 访问 GTT 的
地址窗口**，不是显存容量，拿它当显存写上去是误导。
核显一律显示 `SHARED`。

独显判据是「PCI 地址不在 bus `0000:00` 上，且有显存节点」。
**这条只在单核显机器上实测过** —— AMD 的 APU 不在 bus 00 上且也报显存，
有可能被误判成独显。真遇到了直接改生成出来的 `hwinfo.nix`。

### 内核版本刻意不走这条路

它跟着 nixpkgs 滚，写死进生成文件必然过期。
`modules/refind.nix` 在求值时从 `config.boot.kernelPackages.kernel.version` 取，
所以升级内核之后那一行会自己跟着变，不用重跑探测。

---

## `refind.conf` 的启动项来源

```
scanfor manual,external,optical
```

**刻意不扫内置盘**（没有 `internal`）：NixOS 会往 ESP 的 `EFI/nixos/` 里
散一堆内核 `.efi`，自动扫描会把它们每一个都变成一条菜单项，菜单瞬间变垃圾场。
手写 `menuentry` 则是每台机器一模一样、完全可预测的。

保留 `external` 和 `optical`，是为了插上 U 盘救援介质时**不用改配置**
就能直接启动 —— 真出事的时候没人想先去编辑 `refind.conf`。

---

## 后续注意事项

1. **每台新机器都要先看固件给哪些 GOP 模式，再填分辨率**（坑 2）。
   没有能提前探测的办法。
2. **动引导之前先实际走一遍退路**：敲启动菜单键，选 `Linux Boot Manager`，
   真的进一次系统。理论上的退路不算数。
3. **`refind-sync` 改完要跑第二次验证**（坑 4）。只跑一次测不出重复项问题。
4. **`icon` 用从 ESP 卷根算起的绝对路径**（坑 1）。写错不报错。
5. **双盘双启动时两个 ESP 各装一份 rEFInd。**
   Windows 的 `bcdedit /set {bootmgr} path` 只能指向它自己所在 ESP 内的路径，
   指不到另一块盘上去。见 [MIGRATION.md](../MIGRATION.md) 第 6.5 节。
6. **F10 截图写到 ESP 根目录，rEFInd 自己从不清理。**
   每张 11 MB（2560×1440 未压缩 24 位），攒几张就吃掉 ESP 可观一块。
   手动删：`sudo rm -f /boot/screenshot_*.bmp`
7. **升级 rEFInd 或换主题之后要重跑 `sudo refind-sync`。**
   `nrb` 只把新素材放进 store，不碰 ESP —— 这是刻意设计的，别指望它自动生效。

---

## 相关文档

- [MIGRATION.md](../MIGRATION.md) —— 操作步骤：第 6 节（新机器装 rEFInd）、
  第 9 节（把已有机器导入 rEFInd）
- [`modules/refind.nix`](../modules/refind.nix) —— 实现，注释里记着每个坑的位置
- [`0011`](0011_ROOT_OWNED_FILES_IN_REPO.md) —— 同样是「sudo 跑 nix 把东西写坏」那一类
- [`000F`](000F_LAPTOP_TUNING_AND_AI_FRIENDLY_SHELL.md) —— `modules/` 与 `hosts/` 的分界判据
- [`0012`](0012_AGENT_SKILLS.md) —— `flake = false` 的 input + `writeShellScriptBin`
  这套模式的先例

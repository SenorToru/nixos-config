# Toru 的 NixOS 配置

基于 flake 的多机 NixOS 配置，home-manager 作为 NixOS 模块接入。

| 项目 | 当前状态 |
|------|----------|
| 主机 | `thinkpad`（ThinkPad X1 Yoga 1st Gen，Skylake i7-6500U / 7.6 GiB） |
| 频道 | `nixos-26.05`（home-manager `release-26.05`） |
| 桌面 | GNOME on Wayland |
| 登录 shell | zsh（starship / atuin / direnv / fzf / zoxide） |
| 输入法 | fcitx5（rime 白霜拼音 + mozc UT 词典版） |
| 引导 | rEFInd（顶层入口）→ systemd-boot（管 generation） |

> 本文件是**给人看的操作手册**。
> 给 AI 协作用的约定在 [CLAUDE.md](CLAUDE.md)，
> **装新机器和搬用户状态**在 [MIGRATION.md](MIGRATION.md)（演练清单见 [REHEARSAL.md](REHEARSAL.md)），
> 踩过的坑和排查过程在 [Lesson-Learn/](Lesson-Learn/README.md)。

---

## 目录结构

```
.
├── flake.nix                 入口：inputs 与 nixosConfigurations
├── flake.lock                input 版本锁（必须提交）
├── hosts/
│   └── thinkpad/
│       ├── default.nix       本机身份 + 模块拼装
│       ├── hardware-configuration.nix   nixos-generate-config 生成，别手改
│       ├── hwinfo.nix        refind-hwinfo 生成，别手改（引导画面的硬件行）
│       └── tuning.nix        本机硬件调优
├── modules/                  共用模块（任何机器都能 import）
├── home/
│   ├── toru.nix              home-manager 用户配置
│   ├── agent-skills.nix      Agent Skills：一份 skill 喂给所有 AI 工具
│   ├── skills-tests.sh       skills 命令的回归测试（构建期执行）
│   ├── migration.nix         state-sync + migration-check
│   └── migration-tests.sh    state-sync 的回归测试（构建期执行）
├── Lesson-Learn/             知识库（按时间顺序编号）
├── MIGRATION.md              装新机器 + 搬 Nix 管不到的用户状态
├── REHEARSAL.md              在虚拟机里演练装机流程的检查清单
└── CLAUDE.md                 AI 协作约定
```

### 为什么这样分

这是个**多机**仓库，将来还要加更强的笔记本和台式机。
所有分层都围绕一个判据：

> **换一台机器，这条配置还成立吗？**

| 位置 | 放什么 | 判据 |
|------|--------|------|
| `modules/*.nix` | 任何机器直接 `import` 就能用的 | 换台机器还成立 |
| `hosts/<主机>/tuning.nix` | 绑死在这台硬件上的调优 | 只对这台成立 |
| `hosts/<主机>/default.nix` | 主机名、引导、键盘、用户账户、模块拼装 | 本机身份 |
| `hosts/<主机>/hardware-configuration.nix` | `nixos-generate-config` 生成 | 别手改 |
| `hosts/<主机>/hwinfo.nix` | `refind-hwinfo` 生成：引导画面上那几行硬件 | 工具生成，改了硬件重跑 |
| `home/toru.nix` | 用户级配置（shell、编辑器、浏览器策略） | 跟人走，不跟机器走 |

**必须**放 `hosts/` 的典型例子：

- **显卡驱动**（`hardware.graphics.extraPackages`）—— Intel 的
  `intel-media-driver` 装到 AMD / NVIDIA 机器上是纯浪费，还可能选错驱动
- **内存相关 sysctl**（`vm.swappiness`）—— 数值是按这台机器的内存大小和
  swap 布局算出来的
- **CPU 厂商专属服务**（`services.thermald` 是 Intel 专用）
- **用户名** —— 共用模块里不要出现 `users.users.toru.xxx`

反过来，`services.fwupd.enable` 这种「任何带 UEFI 的机器都该开」的，
就放 `modules/common.nix`，别让下一台机器再抄一遍。

### `modules/` 各模块职责

| 文件 | 负责 |
|------|------|
| `common.nix` | Nix 设置与自动 GC、`allowUnfree`、时区与 locale、`nix-ld`、NetworkManager、基础 CLI 工具、fwupd、sudo 密码回显 |
| `desktop.nix` | GDM + GNOME、蓝牙、PipeWire、打印、默认终端（`xdg.terminal-exec` → Ghostty）、`nautilus-python`（让 Ghostty 自带的右键扩展能加载） |
| `desktop-gnome.nix` | GNOME 扩展包；**只开 `programs.dconf`，不声明任何设置** —— dconf 的单一真相在 `home/toru.nix` |
| `localization.nix` | 字体（全系统唯一的 `fonts` 声明处，含 `stylix.fonts`）与 fcitx5 输入法 |
| `shell.nix` | 系统层 zsh、`PAGER`（**不含**用户名指派） |
| `dns.nix` | 加密 DNS：systemd-resolved + DNS-over-TLS（严格模式）、`dns-plain` / `dns-dot` 逃生舱（见下面「DNS」一节） |
| `development.nix` | 编辑器与工具链、claude-code 与 grok-build 的版本覆写 overlay |
| `browsers.nix` | Zen / Brave 与 chromium 扩展策略 |
| `apps.nix` | 桌面应用 |
| `flatpak.nix` | Flatpak 与 Flathub 自动安装 |
| `stylix.nix` | 全局配色的单一真相：base16 方案、polarity、壁纸、NixOS 级 target |
| `refind.nix` | rEFInd 顶层引导入口：主题 derivation、`refind.conf`、`refind-sync`、`refind-hwinfo`（见下面「引导」一节） |
| `claude-code-manifest.json` | 数据文件，供 `development.nix` 的 overlay 读取 |
| `grok-build-version.json` | 数据文件：grok-build 的版本号与哈希，供同一个 overlay 读取 |

### `home/` 各文件职责

| 文件 | 负责 |
|------|------|
| `toru.nix` | home-manager 主配置：别名、程序、主题 specialisation |
| `agent-skills.nix` | Agent Skills 的安装、开关命令和使用指南生成（见下面「Agent Skills」一节） |
| `skills-tests.sh` | `skills` 命令的回归测试，由 `agent-skills.nix` 在构建期执行 |
| `migration.nix` | `state-sync`（搬 B 类用户状态）和 `migration-check`（查漂移）；B 类清单的单一真相 |
| `migration-tests.sh` | `state-sync` 的回归测试，由 `migration.nix` 在构建期执行 |

`hosts/thinkpad/default.nix` 的 `imports` 按
**「本机专属在前、共用模块在后」**分两组写，加新机器时照抄这个骨架即可。

---

## 改完配置后怎么重建

**顺序本身就是内容**，别跳步 —— 每一步都在防一个具体的坑。

### 1. 新增的文件先让 git 看见（只有新文件需要）

```bash
git add modules/新文件.nix
```

flake **看不见未跟踪的文件**，不 add 会直接报
`Path 'modules/xxx.nix' ... is not tracked by Git`，构建失败。

精确规则：**每个新文件只需 add 一次**。之后再改它，dirty 工作区的内容
会被直接读取，不用反复 `git add`。

### 2. 格式化

```bash
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
```

`hardware-configuration.nix` 是自动生成的，例外。

### 3. 用户态构建两层 —— 不用 sudo，不改系统状态

```bash
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res
nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage \
  --out-link /tmp/hm
```

交互 shell 里有别名：`ncheck`（系统层）、`nhm`（home 层）。
脚本和 AI 用完整命令 —— 别名只存在于交互 shell。

> ### ⚠️ 这一步是防止 git 被 root 锁死的关键，不能跳
>
> 除了让求值错误提前暴露，它还会**以 toru 的身份把 `flake.lock` 写好**。
> 等轮到 root 阶段时那个文件已经是最新的，root 就没东西可写。
>
> 跳过这一步直接 `sudo nixos-rebuild`，当 `flake.lock` 需要更新时
> nix 会**以 root 身份重写它**，读 dirty 工作树时还可能往 `.git/objects`
> 里写对象。这些文件的属主就永久变成 root 了，后果是：
>
> ```
> error: insufficient permission for adding an object to repository database
> error: modules/common.nix: failed to insert into database
> ```
>
> 而且**只对某些文件失败** —— 取决于该文件的 blob 哈希前两位撞上了哪个
> `.git/objects/XX/` 目录。完整排查记录见
> [Lesson-Learn/0011](Lesson-Learn/0011_ROOT_OWNED_FILES_IN_REPO.md)。
>
> 另外：**`nix flake update` 永远不要加 sudo。**

只改了 `home/toru.nix` 也要走完整流程。home-manager 是**作为 NixOS 模块**
接入的，机器上没有独立的 `home-manager` CLI。

### 4. 切换

```bash
sudo nixos-rebuild switch --flake /home/toru/nixos-config#thinkpad    # 别名 nrb
```

| 动作 | 行为 | 用在 |
|------|------|------|
| `switch`（`nrb`） | 激活 + 写引导菜单 | 日常 |
| `test`（`nrt`） | 激活但**不写引导**，重启即回到旧的 | 改内核参数、显卡驱动、引导 —— 万一开不了机，重启就救回来 |
| `boot` | 写引导但**不激活**，下次重启生效 | 改内核本身 |

**注意「半成功」**：系统层和 home 层是两个阶段，home 层失败时系统层
**已经切过去了**。`nrb` 的输出要看到底，别只看有没有报错就走。

### 5. 实机验证 —— 构建通过 ≠ 可用

按改动内容挑：

```bash
fc-match "Sarasa Mono J"                   # 改了字体：族名写错会静默回退
echo $SHELL                                # 改了登录 shell
swapon --show                              # 改了 zram
vainfo                                     # 改了显卡驱动：配错只会静默软解
claude --version                           # 改了 claude-code
grok --version                             # 改了 grok-build
systemctl is-active thermald fwupd         # 改了服务
skills status                              # 改了 Agent Skills
nixos-rebuild list-generations | head -3   # 确认真的生成了新 generation（别名 ngen）
```

**改了 `custom.refind.*` 的话 `nrb` 不够** —— 它只把新素材放进 store，
不碰 ESP。要 `sudo refind-sync` 再重启才看得到。见「引导」一节。

### 6. 提交

```bash
git add -A && git commit -F GIT_COMMIT_MESSAGE.txt
git push origin master
```

提交注释固定写在 `GIT_COMMIT_MESSAGE.txt`（已 gitignore），
格式要求见 [CLAUDE.md](CLAUDE.md)。

---

## 什么时候需要重启

`nixos-rebuild switch` 会自动重启受影响的 systemd 服务，
所以**绝大多数改动不需要重启，也不需要手动 `systemctl restart`**。

### 判断命令（不用猜）

```bash
for p in kernel initrd kernel-modules systemd; do
  [ "$(readlink -f /run/booted-system/$p)" != "$(readlink -f /run/current-system/$p)" ] \
    && echo "需要重启：$p 变了"
done
```

**没有输出就是不用重启。** 原理是比较「启动时用的系统」和「当前激活的系统」
这两个 store path 里的关键组件。

### 三档速查

| 改了什么 | 需要做什么 |
|----------|------------|
| `environment.systemPackages`、`home.packages` 增删 | **什么都不用**，switch 后立即可用 |
| 绝大多数 `services.*` | **什么都不用**，switch 时已重启对应 unit |
| home-manager 管的配置文件 | **什么都不用**，符号链接已更新 |
| shell 的 rc 内容（别名、提示符、插件） | **新开一个终端** |
| `users.users.*.shell`（登录 shell） | **重新登录** |
| `environment.sessionVariables`（写进 `/etc/pam/environment`） | **重新登录** |
| GNOME 扩展、dconf | **注销重登**（Wayland 下不能 `Alt+F2` → `r`） |
| 显卡驱动 / VAAPI | 至少**重启用到它的应用**，稳妥是注销重登 |
| `boot.kernelPackages`、内核参数、initrd、内核模块 | **重启** |
| systemd 本体升级 | **重启** |
| CPU 微码（`hardware.cpu.*.updateMicrocode`） | **重启** |
| 引导配置（`boot.loader.*`） | 写入立即，**下次启动生效** |
| `custom.refind.*`（rEFInd 主题、分辨率、菜单项） | **`nrb` 不生效**，必须再跑 `sudo refind-sync`，然后重启才看得到 |

改内核时推荐先 `sudo nixos-rebuild boot --flake .#thinkpad`，
把新配置排进引导菜单但不激活，方便下次重启时一起生效。

---

## 出问题了

```bash
sudo nixos-rebuild switch --rollback   # 回到上一个 generation
nixos-rebuild list-generations         # 看所有 generation 和当前是哪个（别名 ngen）
```

`--rollback` 和 `--flake` **互斥** —— 回滚走已有 generation，不需要 flake。

**开不了机**：开机先过 rEFInd，选 NixOS 进**systemd-boot 的菜单**，
在那里直接选上一个 generation 条目。
这是 NixOS 最大的安全网 —— 每次 `switch` 都会留下一个可回退的条目。
菜单里保留**最近 20 个**（见
[引导菜单条目数上限](#引导菜单条目数上限)）；更早的 generation 仍然存在，
只是要在能开机的情况下用 `--rollback` 回退。

**rEFInd 本身出问题**（黑屏 / 菜单不出来 / 选了没反应）：
开机敲 **F12** 选 `Linux Boot Manager`，绕过 rEFInd 直接进 systemd-boot。
**这条路实测验证过。** 详见下面「引导」一节。

### 权限自查

跑过任何 `sudo` 之后，偶尔查一下：

```bash
find . ! -user toru -printf '%u  %p\n'
```

**应该没有任何输出。** 有输出说明又被 root 写过了：

```bash
sudo chown -R toru:users .
```

（`toru` 的主组是 `users`，不是 `toru`。）

---

## 引导

两层：**rEFInd 做顶层入口，systemd-boot 继续管 generation。**

```
UEFI 固件
   │
   ▼
rEFInd                      好看的开机画面 + 将来的多系统选单
   └──> systemd-boot        \EFI\systemd\systemd-bootx64.efi
           └──> NixOS 的全部 generation（回滚安全网在这一层）
```

配置在 [`modules/refind.nix`](modules/refind.nix)，本机参数在
`hosts/thinkpad/default.nix` 的 `custom.refind` 和 `hosts/thinkpad/hwinfo.nix`。
选型推理和踩过的五个坑见
[Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。

### 关键：rEFInd 不由 `nixos-rebuild` 管

`nrb` **永远不会碰 ESP 上的 rEFInd 目录**。仓库只负责把素材声明式地备好
（二进制、按本机参数生成的主题、`refind.conf`），真正写进 ESP 的动作
由你手动跑 `refind-sync` 触发。

这是刻意的：引导坏掉等于开不了机，是全仓库风险最高的一处，
而 `nrb` 每天要跑好几次。

**推论：改了 `custom.refind.*` 之后，`nrb` 不会让它生效，必须再跑一次
`sudo refind-sync`。**

### 命令

| 命令 | 作用 | 要 root |
|------|------|---------|
| `sudo refind-sync` | 把 rEFInd 本体、主题、`refind.conf` 写进 ESP，并建 NVRAM 项提到第一位 | 是 |
| `refind-hwinfo` | 探测硬件，写出 `hosts/<主机>/hwinfo.nix` | 建议加（读内存代数要） |
| `efibootmgr` | 查 / 改 UEFI 启动项与顺序 | 读不用，改要 |

### 改了硬件之后

三步，**少一步图片不会更新**：

```bash
cd ~/nixos-config
sudo refind-hwinfo                    # 重新探测，覆盖 hwinfo.nix
sudo nixos-rebuild switch --flake .#thinkpad
sudo refind-sync
```

中间那次 switch 不能省 —— `refind-sync` 里的主题路径是**构建时烤死的
store 路径**，不重新构建的话新图根本不存在。

内核版本那一行不用管，它由模块从 `config.boot.kernelPackages` 求值时取，
升级内核会自己跟着变。

### 分辨率

`custom.refind.resolution` **只能填 UEFI GOP 实际提供的模式**。
本机是 `2560x1440`（面板原生，固件的 Mode 0）—— 注意它**没有 1080p**，
别想当然。

换机器时先随便填一个装上去，固件不支持会在启动时把支持的模式全列出来，
再回来改。想主动列出来就把分辨率临时设成 `1 1`。

### 验证

```bash
efibootmgr | grep -E '^(BootOrder|Boot[0-9A-F]{4}\* (rEFInd|Linux))'
sudo ls /boot/EFI/refind/                  # /boot 是 dmask=0077，必须 sudo
```

然后**重启实际看一眼**：菜单出来没有、背景是不是 finn-term、
NixOS 图标在不在（如果是个约 32×32 的黄黑斜条小方块，那是 rEFInd 的
「图片加载失败」占位符，说明 `icon` 路径不对）。

在 rEFInd 界面按 **`F10`** 会截图到 ESP 根目录。
**它自己从不清理**，每张 11 MB，看完记得删：

```bash
sudo rm -f /boot/screenshot_*.bmp
```

### 安全网

有两条独立的路，`refind-sync` 都不碰（它只往 `\EFI\refind\` 这个新目录写）：

| 路径 | 怎么触发 |
|------|----------|
| `Boot0003` → `\EFI\systemd\systemd-bootx64.efi` | 开机敲 **F12** 选 `Linux Boot Manager`。**已实测** |
| 通用设备项 `NVMe0` → `\EFI\BOOT\BOOTX64.EFI` | rEFInd 的 NVRAM 项失效时固件**自动**落下来 |

> **动引导之前先把退路实际走一遍** —— 敲 F12、选 `Linux Boot Manager`、
> 真的进一次系统。「理论上有退路」和「亲手走过一遍」是两回事。

---

---

## DNS

解析走 **systemd-resolved + DNS-over-TLS**，配置在
[`modules/dns.nix`](modules/dns.nix)。所有机器共用，不绑硬件。

为什么不用明文 DNS：**中间设备可以伪造应答，而伪造得不规范时症状极难定位。**
这个仓库为此付过一整天 —— 路由器上一个「禁止 AAAA 记录」的勾选框，
表现成「虚拟机里 Claude Code 连不上」。全过程见
[Lesson-Learn/0014](Lesson-Learn/0014_DNS_HIJACK_AND_DOT.md)。

日常什么都不用做。要知道的只有三件事：

**一、严格模式，没有静默降级。**
`DNSOverTLS=true` 且 `FallbackDNS=` 是空的。连不上加密服务器时**不解析**，
而不是偷偷退回明文。宁可立刻报错，也不要「以为开着其实没开」。

**二、DHCP 下发的 DNS 一律不用。**
NetworkManager 那边要关**两个独立的开关**：`dns=none`（不写 `resolv.conf`）
和 `systemd-resolved=false`（不通过 D-Bus 推给 resolved）。只关一个不够。
代价是**内网域名解析不了** —— 公司内网、某些 VPN 靠 DHCP 下发的 DNS
解析主机名，那些名字会失败。

**三、captive portal 要手动降级。**
酒店 / 机场 / 咖啡馆的认证页面会拦掉 853 端口，这时候 DNS 全挂、
连认证页都打不开。两条命令：

```bash
sudo dns-plain    # 临时切回网关的明文 DNS，去过认证
sudo dns-dot      # 认证完切回加密
```

只改运行时状态，不动配置文件 —— 忘了切回来的话，重连网络或重启就自动回到 DoT。

### 验证

```bash
resolvectl status                             # Global 段是那四个带 # 主机名的；
                                              # **每个 Link 段的 Current Scopes 不含 DNS、
                                              # 且没有 DNS Servers: 那一行**
resolvectl statistics                         # Cache Hits 在涨
resolvectl query --type=AAAA lwn.net          # 拿到地址，不是 SERVFAIL
ss -tn 'dport = :853'                         # 有到 1.1.1.1:853 的 ESTAB 连接
```

两条容易误判的：

- **`ss` 那条空了不算失败。** resolved 会关掉空闲的 DoT 连接。
  想坐实就先 `sudo resolvectl flush-caches` 再查一个新域名，然后立刻看。
  不需要 `sudo`——不带 `-p` 时它读的是 `/proc/net/tcp`，只是少了进程名。
- **不要拿 `resolvectl query` 末尾的 `-- link: <网卡>` 当判据。**
  那标的是这次查询的**出口网卡**，走全局 DNS 时照样出现，
  只有答案来自缓存才没有。判据只有 Link 段那一条。

判断有没有被劫持，最快的一条是**问一个不存在的 DNS 服务器**：

```bash
nix shell nixpkgs#dnsutils -c dig +time=3 +tries=1 A example.org @192.0.2.1
```

`192.0.2.1` 是 RFC 5737 的 TEST-NET-1，全球不可路由。
**正常必须超时**；能拿到应答就说明有中间设备在截 UDP/53。

## 清理旧的编译版本

每次 `switch` 都会留下一个 generation。它们是 NixOS 的安全网，
但攒多了会占硬盘，内核变动频繁时还会塞爆 `/boot`。

### 先看现状

```bash
nixos-rebuild list-generations        # 有多少个，分别是什么时候
du -sh /nix/store                     # store 总大小
df -h / /boot                         # 根分区和引导分区
nix path-info -Sh /run/current-system  # 当前系统闭包多大
sudo ls /boot/loader/entries/          # 引导菜单条目（/boot 是 dmask=0077，必须 sudo）
```

### 自动清理已经开着

`modules/common.nix` 里已经配了：

```nix
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 7d";
};
nix.settings.auto-optimise-store = true;
```

查定时器状态：

```bash
systemctl list-timers nix-gc.timer
```

> **为什么开了自动 GC 还剩几十个 generation？**
> 因为 `weekly` 的周期加上 `--delete-older-than 7d` 的阈值，
> 天然会攒下**约两周**的量：定时器每周才跑一次，跑的时候只删 7 天前的，
> 于是 7 到 14 天之间的全都留着。这是正常的，不是 GC 坏了。

### 手动清理：三步，第 2 步最容易漏

#### 1. 删旧 generation 并回收 store

```bash
# 先看会删什么，不实际删除
sudo nix-collect-garbage --delete-older-than 7d --dry-run

# 保守：只删 7 天前的
sudo nix-collect-garbage --delete-older-than 7d

# 激进：删掉所有旧 generation，只保留当前
sudo nix-collect-garbage -d
```

用户自己的 profile 单独清一次，**这条不要加 sudo**：

```bash
nix-collect-garbage --delete-older-than 7d
```

> 加了 sudo 会以 root 身份去动本该属于 toru 的东西，
> 是「仓库被 root 锁住」那类问题的同款成因。见
> [Lesson-Learn/0011](Lesson-Learn/0011_ROOT_OWNED_FILES_IN_REPO.md)。

#### 2. 同步引导菜单

```bash
sudo /run/current-system/bin/switch-to-configuration boot
```

或者等价地：

```bash
sudo nixos-rebuild boot --flake /home/toru/nixos-config#thinkpad
```

> **这一步不能省。** `nix-collect-garbage` 删的是
> `/nix/var/nix/profiles/` 下的 generation 符号链接和 store 里的路径，
> 它**不碰** `/boot/loader/entries/`。不重新跑一次引导安装器的话，
> 菜单里会留下一堆指向已删除系统的**死条目** ——
> 平时看不出问题，真到要救机的时候选中一个死条目，启动直接失败。

#### 3. 去重（可选）

```bash
sudo nix store optimise
```

把 store 里内容相同的文件改成硬链接。`auto-optimise-store` 已经开着，
新写入的路径会自动去重，所以平时不需要手动跑，
只在关掉过该选项、或想确认一下的时候用。

### 引导菜单条目数上限

`hosts/thinkpad/default.nix` 里已经设了：

```nix
boot.loader.systemd-boot.configurationLimit = 20;
```

**当前值是 20**（NixOS 默认是 `null`，即不限制）。
超出 20 个之后，最旧的条目会在下次 `switch` 时从引导菜单里移除，
`/boot` 就不会被历代内核塞满。

> 注意它**只限制引导菜单**，不删 store 里的东西。
> 控制磁盘占用靠 `nix.gc`，控制 `/boot` 靠 `configurationLimit`，
> 是两件独立的事，互不替代。

> **被移出菜单 ≠ 被删除。** 那些 generation 本身还在
> （只有 GC 才会真正删掉它们），`nixos-rebuild switch --rollback`
> 和 `nixos-rebuild list-generations` 照常能看到和用到，
> 只是**没法再从开机菜单里直接选中**。
> 也就是说：系统还能开机时回退不受影响，
> 真开不了机时可选的救援点只剩最近 20 个。

### `/boot` 什么时候才会紧张

当前 36 个 generation，`/boot` 只用了 109 MiB / 1022 MiB。
原因是这 36 个里有 35 个跑在同一个 nixpkgs revision 上，
**共用同一份 kernel + initrd**，`/boot` 里只存了两套。

所以 `/boot` 的压力来源不是「rebuild 得频繁」，而是
**「`nix flake update` 得频繁」** —— 每换一次内核才多一套约 50–60 MiB 的
kernel + initrd。如果哪天 `df -h /boot` 逼近满，先看
`nixos-rebuild list-generations` 里有多少个不同的内核版本。

### 清理时的注意事项

- **删掉的 generation 无法恢复。** 回滚只能回到还存在的那些，
  所以至少留一个**已知能正常开机**的 generation，别无脑 `-d`。
- **GC 不会删当前系统**，也不会删任何还被引用的路径，
  所以正常使用下不存在「清着清着把系统清坏」的风险。
- `nix-collect-garbage` 之后**一定要做第 2 步**，否则引导菜单和实际状态不符。
- `/boot` 挂载参数是 `dmask=0077`，普通用户 `ls /boot` 会得到**空结果而不是报错**，
  容易误判成「里面什么都没有」。要看内容得 `sudo ls`。

---

## 迁移到新机器

**完整流程在 [MIGRATION.md](MIGRATION.md)** —— 从插 U 盘装 NixOS 写起，
一直到新机器和这台用起来一样为止。含两种 ISO 的安装步骤、Btrfs 分区、
rEFInd、以及所有 Nix 管不到的用户状态怎么搬。

一句话版本：

```bash
git clone https://github.com/SenorToru/nixos-config ~/nixos-config
# 建 hosts/<新主机>/，hardware-configuration.nix 用 nixos-generate-config 生成，
# tuning.nix 按新硬件重写（别照抄 thinkpad 的）
sudo nixos-rebuild switch --flake ~/nixos-config#<新主机>
```

但**仓库能复现的和不能复现的是两回事**。`MIGRATION.md` 把所有东西分成三类：

| 类 | 是什么 | 怎么办 |
|----|--------|--------|
| A | 仓库负责，字节级复现 | 跑一遍构建就有，**不用做任何事** |
| B | `$HOME` 里的用户状态 | 独立的私有仓库 `dotfiles-state` |
| C | 秘密（SSH 私钥、token、keyring、WiFi） | **不搬**，新机器重新签发 |

还有三样**既不搬也不进仓库**的：rime 的 `build/`（固化着旧机器的 store 路径）、
`installation.yaml`（里面的 UUID 是 Rime 同步的分机标识）、
`*.userdb/`（LevelDB，手工拷没法合并词频，得用 Rime 内建同步）。

> **加了新的开发工具之后要回去更新那份文档** ——
> 判据是「它有没有留下 Nix 管不到的状态」。
> `MIGRATION.md` 第 10 节有一张「加了什么 → 要检查什么」的表。

## 搬用户状态：state-sync 与 migration-check

`$HOME` 里有一批 Nix 管不到的东西。[MIGRATION.md](MIGRATION.md) 第 0 节
把它们分成三类，这两个命令负责其中的 B 类和「有没有漏」的检查。

### `state-sync` —— 搬 B 类状态

```bash
state-sync status     # 看哪些路径有差异
state-sync push       # 把 $HOME 里的状态收进仓库（不自动 commit）
state-sync pull       # git pull
state-sync restore    # 把仓库里的状态铺回 $HOME
```

仓库默认 `~/dotfiles-state`，可用 `STATE_REPO` 覆盖。
**这个仓库要建成 private** —— 里面有输入法的学习数据。

收哪些路径由 [`home/migration.nix`](home/migration.nix) 的 `stateFiles`
决定，两个命令共用同一份清单。目前是 fcitx5 配置、mozc 学习历史、
当前主题、Agent Skill 的禁用状态、多显示器布局、XDG 目录指向。

> **push 不自动提交。** 和 nixos-config 一个道理：人工看过再提交，
> 不让一个刚改坏的配置覆盖掉好的。

push 时会剔掉日志、锁文件和 `.session.ipc` —— 最后那个记的是**本机的
套接字路径**，搬到新机器上是错的。

### `migration-check` —— 查漂移

```bash
migration-check
```

只读。扫五处，报出「实际存在但没人认领」的东西：

| 查什么 | 抓什么 |
|--------|--------|
| Flatpak | 装了但 `modules/flatpak.nix` 里没声明 |
| GNOME 扩展 | 启用了但没声明；**以及声明了但根本没装的死 UUID** |
| VS Code 扩展 | 和手工清单对不上 |
| home-manager 的接管备份 | `*.hm-bak` 文件，并告诉你内容和现役是否一致 |
| B 类状态 | 在 `$HOME` 里但还没 `state-sync push` |
| `~/`、`~/.config`、`~/.local/share`、`~/.claude` | 既不是 home-manager 管的，也不在白名单里 |

最后一项的判据是：**home-manager 管的东西都是指向 `/nix/store` 的符号链接**
（目录的话，是目录里每个文件都是这样的链接），按这一点自动跳过，
所以白名单只需要列「真实存在、但确实不用搬」的。

它抓到过的真东西：没声明的 HandBrake、`enabled-extensions` 里一个
根本没装的死 UUID（GNOME 对不认识的 UUID 静默忽略，平时完全看不出来）、
还有一条只存在于 `~/.config/git/ignore` 里的全局 gitignore 规则。

**加了新的开发工具之后跑一下**，就知道 `MIGRATION.md` 缺了什么。

### 回归测试

[`home/migration-tests.sh`](home/migration-tests.sh) 在**构建期**跑，
测试不过 `nhm` / `nrb` 直接失败。

守的是 `state-sync`：`push` 会把 `$HOME` 的东西复制进一个将来要推上
GitHub 的仓库（**收多了就是泄密**），`restore` 会 `rm -rf` 后覆盖 `$HOME`
里的文件（写错不可逆）。`migration-check` 是只读的，误报顶多浪费几分钟，
所以不测它 —— 测试力度按后果分配。

```bash
STATE_SYNC_BIN=$(command -v state-sync) bash home/migration-tests.sh   # 手动跑
```

改清单之前先确认测试**能变红**：把 `.config/gh` 加进 `stateFiles`，
构建必须失败并报 `push 把清单外的 .config/gh 收进去了（那里面是 token！）`。

---

## Agent Skills

装了 [mattpocock/skills](https://github.com/mattpocock/skills) 的 20 个 skill（源里另有 5 个用不上，
在 `home/agent-skills.nix` 的 `exclude` 里排除），
**全局**安装 —— Claude Code、GitHub Copilot、Zed、Gemini CLI 共用同一份。
配置在 [`home/agent-skills.nix`](home/agent-skills.nix)。

完整使用指南（每个 skill 的调用方式和 token 消耗）见
[Lesson-Learn/0012_AGENT_SKILLS.md](Lesson-Learn/0012_AGENT_SKILLS.md)。

### 装在哪

```
第一层（声明式，home-manager 管，版本由 flake.lock 钉死）
  ~/.local/share/agent-skills -> /nix/store/…-agent-skills/

第二层（可变状态，skills 命令管，状态存 ~/.local/state/agent-skills/disabled）
  ~/.claude/skills/<名>   -> ~/.local/share/agent-skills/<名>
  ~/.agents/skills/<名>   -> 同上
  ~/.copilot/skills/<名>  -> 同上
```

三个目录覆盖所有工具：Claude Code 只读 `~/.claude/skills/`，
Zed 和 Gemini CLI 读 `~/.agents/skills/`，Copilot 三个都读。

**为什么分两层：** 如果让 home-manager 直接管第二层那些链接，
`skills off tdd` 之后下一次 `nrb` 会把它悄悄装回来。拆开之后，
禁用状态活得过 rebuild，而新机器第一次 build 完是全开的。

### 命令

| 命令 | 作用 |
|------|------|
| `skills list` | 全部 skill：调用方式、token 估算、开关状态 |
| `skills status` | pool 指向哪个 store 路径、三个目录的链接健不健康 |
| `skills off <名>` / `skills off --all` | **临时**禁用，立刻对所有工具生效。长期不要的写进 `exclude`，别靠它 |
| `skills on <名>` / `skills on --all` | 启用 |
| `skills sync` | 按开关状态重建链接（`nrb` 时自动跑，平时用不到） |
| `skills doc` | 重新生成指南里的表（`nrb` 时自动跑） |
| `skills-update` | 升级 skill |

这些都是 `$PATH` 上的真二进制，不是别名，脚本和非交互 shell 里能直接调。

### 升级

```bash
skills-update                                          # 更新 lock + 用户态构建两层
sudo nixos-rebuild switch --flake /home/toru/nixos-config#thinkpad   # 别名 nrb
git add -A && git commit -F GIT_COMMIT_MESSAGE.txt     # flake.lock 和指南一起提交
```

`skills-update` 内部跑的是 `nix flake update`，**不带 sudo**（见坑 5）。
它不替你 switch，也不替你 commit。没有新版本时会直接说「已是最新」并退出。

`nrb` 的时候 home-manager 会自动 `skills sync` + `skills doc`，
所以升级之后 `Lesson-Learn/0012_AGENT_SKILLS.md` 会跟着变 —— 那是生成物，
连同 `flake.lock` 一起提交就行。

### 和工具内建 skill 撞名

`code-review` 装进来时会被改名成 `matt-code-review` —— Claude Code 自带一个
内建的 `/code-review`，同名时内建赢，Matt 那个会静悄悄地够不着。
改名配在 `skillSources.<源>.rename`，目录名和 frontmatter 的 `name:` 一起改。

**构建期的撞名检查只管源与源之间，查不到和工具内建撞。**
装完新 skill 集合之后，`skills list` 的数量要和每个工具里实际能看见的数量对一遍。
详见 [Lesson-Learn/0012](Lesson-Learn/0012_AGENT_SKILLS.md) 第四节。

### 回归测试

`home/skills-tests.sh` 测 `skills` 命令，**在构建期跑** ——
测试不过 `nhm` / `nrb` 就直接失败。目前守着「pool 之外的符号链接不会被
`sync` 删掉」这一条（误删 `~/.claude/skills/` 里的东西不可逆）。

```bash
SKILLS_BIN=$(command -v skills) bash home/skills-tests.sh   # 手动跑
```

改剪枝逻辑之前请先看 [Lesson-Learn/0012](Lesson-Learn/0012_AGENT_SKILLS.md) 第八节。

### 加一个新的 skill 源

两处都要改：

1. `flake.nix` 加一个 `flake = false` 的 input；
2. `home/agent-skills.nix` 的 `skillSources` 表加一条，写明装哪些类别。

`skills-update` 会自动把表里所有源一起更新。skill 名字撞车时构建会直接失败
并报出是哪两个源撞了 —— 四家工具都只按目录名认 skill，悄悄覆盖比构建失败难查。

### 实机验证

```bash
skills status                             # 三个目录各能看见多少个
readlink -f ~/.local/share/agent-skills   # 应落在 /nix/store 里
```

然后在 Claude Code 里打一次 `/tdd`，在 VS Code 的 Copilot 里问一个该触发
`diagnosing-bugs` 的问题 —— 构建通过不等于工具真的认这些符号链接。

**再数一遍数量。** `skills list` 说 20 个，就去每个工具的 skill 列表里数，
少了就是撞了那个工具的内建 skill（见上面「和工具内建 skill 撞名」）。

---

## 其他注意事项

1. **字体族名写错，fontconfig 完全静默回退。** 写完必须 `fc-match "族名"` 验证。
   `sarasa-gothic` 只有 `Sarasa Mono J` 这类带地区后缀的族名，没有 `Sarasa Mono`。
2. **不要直接编辑 `~/.config/nvim/`。** 那是 home-manager 管的符号链接，
   必须改 `home/toru.nix` 再 rebuild。
3. **不要在系统层和 home 层各声明一次同一个程序。** Nix 不报冲突，
   但会装出两份（`nvim` 和 `vim` 曾指向两个不同的 neovim 派生）。
4. **加服务前先 `nix eval` 查当前值。** GNOME 之类的高层模块已经替你开了
   不少东西（`power-profiles-daemon`、`systemd.oomd`、`fstrim`），
   重复声明不报错，只留下看不出真假的噪音。
5. **`nix flake update` 没让某个包动，不等于它已是最新。**
   `nixos-26.05` 是发布分支，不跟上游滚。
6. **从 GitHub clone 很慢**（实测 ~80 KiB/s），但这**不是全局网速** ——
   `downloads.claude.ai` 实测 6.4 MB/s。别拿 GitHub 的数字去否决其它下载。

完整清单和每条的排查过程见 [Lesson-Learn/README.md](Lesson-Learn/README.md)。

### shell 环境约定

`ls` / `cat` / `grep` / `find` **没有被 alias 遮蔽**，输出就是 coreutils 的
原始格式。要彩色分栏请显式写 `eza` / `bat`。
这是硬约定 —— 人看到的输出和 AI 看到的输出必须是同一个东西。
详见 [CLAUDE.md](CLAUDE.md) 的「Shell 环境」一节。

---

## 维护约定

> **改动目录结构或重建方法时，必须同步更新本文件。**
>
> 具体包括：
>
> - 新增、删除、重命名 `modules/` 下的模块
> - 新增主机（`hosts/<新主机>/`）或调整 `hosts/` 的文件划分
> - 改变 `modules/` 与 `hosts/` 的分界判据
> - 改变重建命令、别名，或六步流程中的任何一步
> - 改变清理 generation 的流程，或 `nix.gc` / `configurationLimit` 的设置
> - 改变「什么时候需要重启」的结论
> - 新增、删除 `home/` 下的文件，或改变 Agent Skills 的装法、命令、更新流程
> - 改变引导架构、`custom.refind.*` 的选项，或 `refind-sync` /
>   `refind-hwinfo` 的用法
> - 改变 `state-sync` / `migration-check` 的用法，或 B 类状态清单
>
> 本文件与 [CLAUDE.md](CLAUDE.md) 有意重叠：
> README 是给人看的操作手册，CLAUDE.md 是给 AI 的协作约定。
> **两边描述同一件事时，改了一边就要改另一边**，不要让它们漂移。

### 还要同步 MIGRATION.md

[MIGRATION.md](MIGRATION.md) 管的是**一次性的事**（装新机器、搬用户状态），
和本文件管的**日常操作**不重叠，但有一个硬要求：

> **加了任何新的开发工具（虚拟机、语言工具链、库、需要登录的服务）之后，
> 要回去更新 MIGRATION.md。** 判据是「它有没有留下 Nix 管不到的状态」——
> 用户级的缓存、凭据、registry 配置都算。
>
> 那份文档第 10 节有一张「加了什么 → 要检查什么」的表。

新增 Lesson-Learn 文档时的编号规则和索引维护要求，见
[Lesson-Learn/README.md](Lesson-Learn/README.md)。

---

## 许可

[MIT](LICENSE)

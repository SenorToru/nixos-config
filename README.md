# Toru 的 NixOS 配置

基于 flake 的多机 NixOS 配置，home-manager 作为 NixOS 模块接入。

| 项目 | 当前状态 |
|------|----------|
| 主机 | `thinkpad`（ThinkPad X1 Yoga 1st Gen，Skylake i7-6500U / 7.6 GiB） |
| 频道 | `nixos-26.05`（home-manager `release-26.05`） |
| 桌面 | GNOME on Wayland |
| 登录 shell | zsh（starship / atuin / direnv / fzf / zoxide） |
| 输入法 | fcitx5（rime + mozc） |

> 本文件是**给人看的操作手册**。
> 给 AI 协作用的约定在 [CLAUDE.md](CLAUDE.md)，
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
│       ├── hardware-configuration.nix   自动生成，别手改
│       └── tuning.nix        本机硬件调优
├── modules/                  共用模块（任何机器都能 import）
├── home/
│   └── toru.nix              home-manager 用户配置
├── Lesson-Learn/             知识库（按时间顺序编号）
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
| `common.nix` | Nix 设置与自动 GC、`allowUnfree`、时区与 locale、`nix-ld`、NetworkManager、基础 CLI 工具、fwupd |
| `desktop.nix` | GDM + GNOME、蓝牙、PipeWire、打印 |
| `desktop-gnome.nix` | dconf 设置与 GNOME 扩展 |
| `localization.nix` | 字体（全系统唯一的 `fonts` 声明处）与 fcitx5 输入法 |
| `shell.nix` | 系统层 zsh、`PAGER`（**不含**用户名指派） |
| `development.nix` | 编辑器与工具链、claude-code 版本覆写 overlay |
| `browsers.nix` | Zen / Brave 与 chromium 扩展策略 |
| `apps.nix` | 桌面应用 |
| `flatpak.nix` | Flatpak 与 Flathub 自动安装 |
| `claude-code-manifest.json` | 数据文件，供 `development.nix` 的 overlay 读取 |

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
systemctl is-active thermald fwupd         # 改了服务
nixos-rebuild list-generations | head -3   # 确认真的生成了新 generation（别名 ngen）
```

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

改内核时推荐先 `sudo nixos-rebuild boot --flake .#thinkpad`，
把新配置排进引导菜单但不激活，方便下次重启时一起生效。

---

## 出问题了

```bash
sudo nixos-rebuild switch --rollback   # 回到上一个 generation
nixos-rebuild list-generations         # 看所有 generation 和当前是哪个（别名 ngen）
```

`--rollback` 和 `--flake` **互斥** —— 回滚走已有 generation，不需要 flake。

**开不了机**：在 systemd-boot 菜单里直接选上一个 generation 条目。
这是 NixOS 最大的安全网 —— 每次 `switch` 都会留下一个可回退的条目。

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
> - 改变重建命令、别名、或六步流程中的任何一步
> - 改变「什么时候需要重启」的结论
>
> 本文件与 [CLAUDE.md](CLAUDE.md) 有意重叠：
> README 是给人看的操作手册，CLAUDE.md 是给 AI 的协作约定。
> **两边描述同一件事时，改了一边就要改另一边**，不要让它们漂移。

新增 Lesson-Learn 文档时的编号规则和索引维护要求，见
[Lesson-Learn/README.md](Lesson-Learn/README.md)。

---

## 许可

[MIT](LICENSE)

# 本仓库协作约定

Toru 的 NixOS 多机配置仓库（flake，home-manager 作为 NixOS 模块）。

## 仓库结构：什么放 `modules/`，什么放 `hosts/`

这是个**多机**仓库，将来还要加更强的笔记本和台式机。
所以新增配置前先问一句：**换一台机器，这条还成立吗？**

| 位置 | 放什么 | 判据 |
|------|--------|------|
| `modules/*.nix` | 任何机器都能直接 `import` 的共用配置 | 换台机器还成立 |
| `hosts/<主机>/tuning.nix` | 绑死在这台硬件上的调优 | 只对这台成立 |
| `hosts/<主机>/default.nix` | 主机名、引导、键盘布局、用户账户、模块拼装 | 本机身份 |
| `hosts/<主机>/hardware-configuration.nix` | `nixos-generate-config` 自动生成，别手改 | — |

典型的**必须**放 `hosts/` 的东西：

- **显卡驱动**（`hardware.graphics.extraPackages`）—— Intel 的 `intel-media-driver`
  装到 AMD / NVIDIA 机器上是纯浪费，还可能选错驱动。
- **内存相关的 sysctl**（`vm.swappiness` 等）—— 数值是按这台机器的内存大小和
  swap 布局算出来的，换台内存大得多的机器就是错的。
- **CPU 厂商专属服务**（`services.thermald` 是 Intel 专用）。
- **用户名**。共用模块里不要出现 `users.users.toru.xxx` ——
  那会把模块钉死在一个具体用户上。`programs.zsh.enable` 放 `modules/shell.nix`
  （通用），`users.users.toru.shell = pkgs.zsh` 放 `hosts/thinkpad/default.nix`
  （本机的事）。

反过来，像 `services.fwupd.enable` 这种「任何带 UEFI 的机器都该开」的，
就该放 `modules/common.nix`，别让下一台机器再抄一遍。

`hosts/thinkpad/default.nix` 的 `imports` 按「本机专属在前、共用模块在后」
分两组写，加新机器时照抄这个骨架即可。

## Git 提交注释

**固定写在仓库根目录的 `GIT_COMMIT_MESSAGE.txt`**，然后用：

```bash
git commit -F GIT_COMMIT_MESSAGE.txt
```

该文件已在 `.gitignore` 中，是本地草稿，不进版本库。

硬性要求：

- **纯文本。不写 Markdown**（不用 `#`、`##`、`|` 表格、` ``` ` 代码围栏、`**粗体**`）。
  `git commit -F` 默认不剥离 `#` 开头的行，写成 Markdown 标题会让提交标题
  直接带上 `#`（提交 `8fef4d0` 就是这么坏掉的）。
- **不使用任何表情符号 / emoji**，包括 ✅ ⚠️ ⛔ 📌 这类。
- 结构靠缩进和空行表达，第一行是不超过 72 字的标题，空一行再写正文。
- **不写 `Co-Authored-By:` 尾注**，也不写任何其它署名或生成工具标记。
  提交信息里只放这次改动本身的内容。

## Lesson-Learn 知识库

`Lesson-Learn/` 收录配置过程中的问题、原因分析和解决方案。

- **文件名格式：`XXXX_TOPIC_IN_CAPS.md`**，`XXXX` 是 **4 位大写十六进制**编号。
- **编号序列：** `0000` → `0009` → `000A` → `000F` → `0010` → … → `FFFF`。
  注意 `0009` 的下一个是 `000A`，不是 `0010`。
- **新增文档取「当前最大编号 + 1」。** 当前最大编号写在
  [Lesson-Learn/README.md](Lesson-Learn/README.md) 的组织规则里，加完要同步更新。
- **编号按配置发生的先后顺序分配**，不按主题分类。
- **编号一经分配不再变动。** 文档作废时加废弃横幅并指向新文档，
  不删除、不重排 —— 重排会让已有的交叉引用全部失效。
- `0000` 是长期维护的使用指南，不属于时间线，固定排最前。
- 新增或重命名后，**必须更新 `Lesson-Learn/README.md` 索引表**，
  并校验所有交叉引用的链接目标存在。

文档风格参照现有文件：中文，章节为「问题症状 / 根本原因分析 / 已实施的修复 /
为什么这样解决 / 后续注意事项 / 相关文档」。知识库文档里可以用 Markdown 和表情符号，
**这条限制只针对提交注释**。

## 验证流程

改完配置后用 `nix build` 自证，**不需要 sudo，不改系统状态**：

```bash
# 系统层
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res
ls /tmp/res/sw/bin/

# home 层
nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage \
  --out-link /tmp/hm
cat /tmp/hm/home-files/.config/mimeapps.list
```

nix 文件保持 `nixfmt` 干净（`hardware-configuration.nix` 是自动生成的，例外）：

```bash
nixfmt --check $(git ls-files '*.nix' | grep -v hardware-config)
```

## Shell 环境

登录 shell 是 **zsh**（`modules/shell.nix` 定系统层，`home/toru.nix` 定交互体验）。
bash 保持完全可用，两者配的是同一套基线。

**在这台机器上跑命令（人或 AI）都按下面几条来：**

- **只用 PATH 上的真二进制，不要依赖 alias。**
  `ll`、`gs`、`nrb`、`ncheck` 这些只存在于交互 shell，
  `zsh -c 'll'` / `bash -c 'll'` 一律 command not found。
  `eza` `bat` `fzf` `zoxide` `atuin` `btop` `lazygit` `tmux` `dua` `duf` `direnv` `starship`
  都是真二进制（在 `/etc/profiles/per-user/toru/bin`），可以直接调用。
- **`ls` / `cat` / `grep` / `find` 没有被 alias 遮蔽**，输出就是 coreutils 的
  原始格式，可以放心解析。要彩色分栏请显式写 `eza` / `bat`。
  这是硬约定：人看到的输出和 AI 看到的输出必须是同一个东西。
- **`bat` 默认会分页**，脚本里请用 `bat -pp`，或者直接用 `cat`。
- **`PAGER` 已经是 `less -FRX`**（写在 `/etc/pam/environment`，任何进程都继承），
  不足一屏不会进分页器，所以不会卡住等输入。
- **direnv 的 hook 只在交互 shell 里生效。**
  在有 `.envrc` 的项目目录里跑命令，非交互场景要显式写
  `direnv exec . <命令>`，否则拿不到 devShell 的环境。
- **命令历史由 atuin 接管**（sqlite 库，带目录/退出码/耗时）。`Ctrl+R` 和 `↑` 都归它，
  `Ctrl+T` / `Alt+C` 仍归 fzf。`~/.zsh_history` 照常在写，作为导入源和兜底。
  非交互场景查历史用 `atuin search --cmd-only <关键词>`，不要去 grep `~/.zsh_history`。
- zsh 这边 `/etc/zshenv` 对**所有** zsh（含 `zsh -c`）都会 source 一次
  `set-environment`，所以非交互 zsh 也有完整的系统 PATH。

## 不要自动提交

**改完不要 `git commit`。** Toru 会先自己
`sudo nixos-rebuild switch --flake .#thinkpad` 实机验证，通过后由他决定提交。

构建通过不等于可用 —— 例如字体族名写错时 `nix build` 完全成功，
但 fontconfig 会静默回退；home-manager 激活失败时系统层已经切过去了，
只有实机才能发现。

可以准备好 `GIT_COMMIT_MESSAGE.txt`，但执行提交由 Toru 决定。

## 本仓库反复出现的坑

1. **字体族名写错，fontconfig 完全静默回退。** 写完必须 `fc-match "族名"` 验证。
   `sarasa-gothic` 只有 `Sarasa Mono J` 这类带地区后缀的族名，没有 `Sarasa Mono`。
2. **不要直接编辑 `~/.config/nvim/`。** 那是 home-manager 管的符号链接，
   必须改 `home/toru.nix` 再 rebuild。
3. **不要在系统层和 home 层各声明一次同一个程序。** Nix 不报冲突，
   但会装出两份（`nvim` 和 `vim` 曾指向两个不同的 neovim 派生）。
4. **`nixos-rebuild switch` 报错不等于没生效。** 系统层和 home 层是两个阶段，
   可能出现半成功状态。

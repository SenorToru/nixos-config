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
| `hosts/<主机>/hwinfo.nix` | `refind-hwinfo` 生成：引导画面上那几行硬件 | 工具生成，换硬件重跑 |
| `home/migration.nix` | `state-sync` / `migration-check`，以及 B 类状态清单 | 跟着用户走 |
| `home/<用户>.nix` 及同目录文件 | home-manager 用户配置。按主题拆文件，由 `home/toru.nix` 的 `imports` 拼装 | 跟着用户走 |

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

## 三份文档的分工

| 文件 | 管什么 |
|------|--------|
| [README.md](README.md) | **给人看的操作手册**：日常重建、清理、引导、Agent Skills |
| 本文件 | **给 AI 的协作约定**：分层判据、提交格式、踩过的坑 |
| [MIGRATION.md](MIGRATION.md) | **一次性的事**：装新机器、搬 Nix 管不到的用户状态 |

README 和本文件有意重叠。

**改动下列任何一项时，必须同步更新 README.md：**

- 新增、删除、重命名 `modules/` 下的模块
- 新增、删除 `home/` 下的文件
- 新增主机（`hosts/<新主机>/`）或调整 `hosts/` 的文件划分
- 改变 `modules/` 与 `hosts/` 的分界判据
- 改变重建命令、别名，或六步流程中的任何一步
- 改变清理 generation 的流程，或 `nix.gc` / `configurationLimit` 的设置
- 改变「什么时候需要重启」的结论
- 改变 Agent Skills 的装法、`skills` / `skills-update` 命令，或升级流程
- 改变引导架构、`custom.refind.*` 的选项，或 `refind-sync` / `refind-hwinfo` 的用法

**改动下列任何一项时，必须同步更新 MIGRATION.md：**

- **新增任何开发工具**（虚拟机、语言工具链、库、需要登录的服务）——
  判据是「它有没有在 `$HOME` 里留下 Nix 管不到的状态」，
  用户级的缓存、凭据、registry 配置都算。那份文档第 10 节有对照表。
- 改变装机流程：分区方案、文件系统、ISO 选择、引导
- 改变 A / B / C 三类的划分，或 `dotfiles-state` 收哪些路径
- 改变 `refind-sync` / `refind-hwinfo` / `state-sync` / `migration-check` 的用法

**两边描述同一件事时，改了一边就要改另一边**，不要让它们漂移。
漂移之后最糟的情况不是信息缺失，而是两份文档给出互相矛盾的指示 ——
人照 README 做、AI 照 CLAUDE.md 做，结果对不上。

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

## 改完 nix 文件后的重建顺序

**顺序本身就是内容**，别跳步——每一步都在防一个具体的坑。

### 1. 新增的文件先让 git 看见（只有新文件需要）

```bash
git add modules/新文件.nix
```

**flake 看不见未跟踪的文件**，不 add 就会
`Path 'modules/xxx.nix' ... is not tracked by Git`，构建直接失败。

精确规则：**每个新文件只需 add 一次**。之后再怎么改它，dirty 工作区的内容
都会被直接读取，不用反复 `git add`。

### 2. 格式化

```bash
nixfmt $(git ls-files '*.nix' | grep -v hardware-config)
nixfmt --check $(git ls-files '*.nix' | grep -v hardware-config)
```

`hardware-configuration.nix` 是自动生成的，例外。

### 3. 用户态构建两层——**不用 sudo，不改系统状态**

```bash
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res
nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage \
  --out-link /tmp/hm
```

交互 shell 里有别名：`ncheck`（系统层）、`nhm`（home 层）。
**非交互 / 脚本 / AI 用完整命令**——别名只存在于交互 shell。

**这一步不能跳，两个理由：**

1. 求值错误、选项名写错、缺依赖在这里就暴露，不用等到 root 阶段。
2. **它顺带把 `flake.lock` 以 toru 的身份写好。** 轮到 root 时它没东西可写——
   这是 `flake.lock` 被写成 root 所有的根本预防，见坑 5。

改完之后可以顺手查产物，比如
`ls /tmp/res/sw/bin/`、`cat /tmp/hm/home-files/.config/mimeapps.list`。

> 只改了 `home/toru.nix` 也要走完整流程。home-manager 是**作为 NixOS 模块**
> 接入的，机器上没有独立的 `home-manager` CLI，只能靠 `nixos-rebuild`。

### 4. 切换

```bash
sudo nixos-rebuild switch --flake /home/toru/nixos-config#thinkpad   # 别名 nrb
```

| 动作 | 行为 | 用在 |
|------|------|------|
| `switch`（`nrb`） | 激活 + 写引导菜单 | 日常 |
| `test`（`nrt`） | 激活但**不写引导**，重启即回到旧的 | 改内核参数、显卡驱动、引导——万一开不了机，重启就救回来 |
| `boot` | 写引导但**不激活**，下次重启生效 | 改内核本身 |

**注意「半成功」**：系统层和 home 层是两个阶段，home 层失败时系统层已经切过去了。
`nrb` 的输出要看到底，别只看有没有报错就走（见坑 4）。

### 5. 实机验证——构建通过 ≠ 可用

按改动内容挑：

```bash
fc-match "Sarasa Mono J"                   # 改了字体：族名写错会静默回退（坑 1）
echo $SHELL                                # 改了登录 shell（需重新登录）
swapon --show                              # 改了 zram
vainfo                                     # 改了显卡驱动：配错只会静默软解
claude --version                           # 改了 claude-code
systemctl is-active thermald fwupd         # 改了服务
nixos-rebuild list-generations | head -3   # 确认真的生成了新 generation（别名 ngen）
```

### 6. 提交（Toru 验证通过之后）

```bash
git add -A && git commit -F GIT_COMMIT_MESSAGE.txt
```

`.gitignore` 已挡掉 `result` / `build.log` / `GIT_COMMIT_MESSAGE.txt`，
所以 `git add -A` 是安全的。

### 出问题了

```bash
sudo nixos-rebuild switch --rollback   # 回到上一个 generation
nixos-rebuild list-generations         # 看所有 generation 和当前是哪个
```

`--rollback` 和 `--flake` **互斥**——回滚走已有 generation，不需要 flake。
开不了机就在 systemd-boot 菜单里直接选上一个 generation。

### 权限自查（跑过 sudo 之后偶尔查一下）

```bash
find . ! -user toru -printf '%u  %p\n'
```

**应该没有任何输出。** 有输出说明又被 root 写过，
`sudo chown -R toru:users .` 修掉。见坑 5。

## Agent Skills

`home/agent-skills.nix` 把 [mattpocock/skills](https://github.com/mattpocock/skills)
的 25 个 skill 装成**全局**的，Claude Code / Copilot / Zed / Gemini 共用一份。
完整说明见 [Lesson-Learn/0012_AGENT_SKILLS.md](Lesson-Learn/0012_AGENT_SKILLS.md)
和 [README.md](README.md) 的「Agent Skills」一节。

改这块之前必须知道的五件事：

1. **分两层，别把它们合并回去。**
   `~/.local/share/agent-skills` 由 home-manager 管（声明式，flake.lock 钉版本）；
   `~/.claude/skills/` `~/.agents/skills/` `~/.copilot/skills/` 里的链接由
   `skills sync` 管（可变状态）。合并的话 `skills off` 会在下次 `nrb` 时被悄悄撤销。
2. **`Lesson-Learn/0012_AGENT_SKILLS.md` 里 `<!-- BEGIN GENERATED -->` 到
   `<!-- END GENERATED -->` 之间是生成物**，由 `skills doc` 写，`nrb` 时自动刷新。
   别手改那一段，改动会被覆盖；要改就改 `home/agent-skills.nix` 里的 `cmd_doc`。
   标记之外的手写部分不会被动。
3. **那两个脚本用 `writeShellScriptBin` 而不是 `writeShellApplication`。**
   后者会在构建时跑 shellcheck，而 shellcheck 在沙箱的 C locale 下打印不出中文，
   一有 warning 就崩在 `commitBuffer: invalid argument` 上，报错完全看不出原因。
   改完脚本请实机跑 `skills list` / `skills status` 验证。

4. **`home/skills-tests.sh` 在构建期执行，测试不过 `nhm` / `nrb` 就失败。**
   它测的是 `skills` 的 CLI 边界（临时 HOME + pool 夹具 + 断言最终的链接状态），
   不测内部函数。改 `cmd_sync` 的剪枝逻辑时，先确认测试**能变红**再提交 ——
   把剪枝条件临时改成无条件 `rm -f`，构建必须失败。
5. **撞名分两种，构建期只拦得住一种。**
   源与源之间撞名构建会直接失败；和**工具内建 skill** 撞名查不出来 ——
   `code-review` 就是被 Claude Code 的内建盖掉的，已改名成 `matt-code-review`
   （配在 `skillSources.<源>.rename`，目录名和 frontmatter 的 `name:` 一起改）。
   装新 skill 集合之后要数一遍：`skills list` 的数量和每个工具里能看见的对得上吗。

加新 skill 源要同时改 `flake.nix`（加 `flake = false` 的 input）和
`skillSources` 表，两处缺一不可。

## 引导：rEFInd 叠在 systemd-boot 之上

两层。rEFInd 只做顶层入口，**generation 菜单和回滚仍归 systemd-boot** ——
那是这个系统最重要的救命机制，不能动。

配置在 `modules/refind.nix`，本机参数在 `hosts/<主机>/default.nix` 的
`custom.refind` 和 `hosts/<主机>/hwinfo.nix`。
完整记录见 [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。

改这块之前必须知道的四件事：

1. **`nixos-rebuild` 不碰 ESP 上的 rEFInd 目录。**
   仓库只声明式地备好素材（二进制、生成的主题、`refind.conf`），
   写进 ESP 由手动跑 `sudo refind-sync` 触发。这是刻意的 ——
   引导坏掉等于开不了机，而 `nrb` 每天跑好几次。
   **推论：改了 `custom.refind.*` 之后 `nrb` 不会生效，必须再 `refind-sync`。**

2. **不要改用官方的 `boot.loader.refind`。**
   它设 `system.boot.loader.id = "refind"`，和 `systemd-boot.enable` 互斥，
   两层结构搭不起来；而且会把每个 generation 摊成一条顶层菜单项。

3. **`boot.loader.efi.canTouchEfiVariables` 必须保持 `false`。**
   改回 `true` 的话 systemd-boot 每次 switch 都抢 NVRAM 第一位，
   rEFInd 白装。模块里有 assertion 守着，但别去绕过它。

4. **`refind.conf` 里 `icon` 的路径基准和 `banner` / `icons_dir` 不一样。**
   前者相对 **ESP 卷根**，后两者相对 **rEFInd 目录**。
   写错不报错，只显示一个约 32×32 的内置占位方块，而同目录下的功能图标
   一切正常。路径统一走模块里的 `refindDir` / `themeDir` 变量，别手写。

`hosts/<主机>/hwinfo.nix` 由 `refind-hwinfo` 生成，**别手写** ——
但探测判断错了可以直接改它（它不在开机路径上）。
换了硬件三步：`sudo refind-hwinfo` → `nrb` → `sudo refind-sync`，**少一步不生效**。

---

## 用户状态：state-sync 与 migration-check

`$HOME` 里 Nix 管不到的东西按 [MIGRATION.md](MIGRATION.md) 第 0 节分三类：
**A 能进 Nix 就进 Nix，B 进不了但可版本化的进 `dotfiles-state`，
C 是秘密的一律不搬**（新机器重新签发）。

实现在 `home/migration.nix`，两个命令共用同一份清单。

改这块之前必须知道的四件事：

1. **B 类清单（`stateFiles`）是单一真相，别在脚本里另写一份。**
   两份清单必然漂移，而漂移的表现是「换机器之后某个设置莫名其妙没了」，
   极难联想回这里。

2. **`state-sync push` 会把内容复制进一个将来要推上 GitHub 的仓库。**
   往 `stateFiles` 里加东西之前先问：这是不是 C 类？
   `home/migration-tests.sh` 有一条用例专门守这个（把 `.config/gh`
   加进清单，构建必须失败）。改清单前先确认测试**能变红**。

3. **`migration-check` 靠「home-manager 管的都是指向 `/nix/store` 的
   符号链接」来自动跳过。** 两个容易写错的地方：

   - 目录要看「非空且里面**每个文件**都是这样的链接」。只查顶层符号链接
     会把 `~/.config/bat`、`btop`、`ghostty` 这一大批全部误报（实测 14 个）。
   - 必须用 **`readlink -f` 逐个解析**，不能用 `find -lname '/nix/store/*'`。
     后者匹配的是链接里存的**原始字符串**、不跟着解析，而
     `~/.claude/skills/<名>` 指向的是 `~/.local/share/agent-skills/<名>`，
     那个才是指向 store 的链接 —— **两跳**。用 `-lname` 会把
     `skills sync` 管得好好的目录报成「没人认领」。

   扫四处：`~/`、`~/.config`、`~/.local/share`、`~/.claude`。
   **`~/.claude` 单独扫而不是整个加白名单**，是因为整个忽略的话，
   以后 Claude Code 在那里新增一个该管的配置文件就发现不了了。

5. **同一个目录里的文件可以分属不同类，判据是「谁在写这个文件」。**
   `~/.claude/` 就是例子：`keybindings.json` 手写、工具不碰 → A 类，
   声明进 `home.file`；`settings.json` 被 `/model`、`/effort`、`/config`
   在运行时写 → B 类，进 `dotfiles-state`。
   把后者写成只读符号链接会让那几个命令直接失效 ——
   **不要为了声明式的纯度关掉工具的功能。**

4. **加了新的开发工具之后跑一次 `migration-check`。**
   它会报出 `$HOME` 里没人认领的东西。每一处问：A、B 还是 C？
   处理完同步 `MIGRATION.md` 第 10 节的表。

## 在 nix 字符串里写 shell 脚本

两条硬规则，都是踩出来的：

1. **用 `writeShellScriptBin`，不要用 `writeShellApplication`。**
   后者构建期跑 shellcheck，而 shellcheck 在沙箱的 C locale 下打印不出
   中文，一有 warning 就崩在 `commitBuffer: invalid argument` 上，
   报错完全看不出原因。

2. **不要在 nix 缩进字符串里写 heredoc。**
   `cat <<'X' ... X` 的终止符必须顶格，而 nix 的公共缩进剥离加上 nixfmt
   的重排会让它带上缩进，bash 报 `syntax error: unexpected end of file`，
   指向的行号还离得很远。
   **清单一律用 `pkgs.writeText` 落成 store 里的文件**，脚本只管 `cat`，
   缩进怎么变都不影响。`home/migration.nix` 的 `listFile` 是现成的写法。

另外两个从 Nix 侧读配置时的坑，都会报成「类型不对」且位置离得很远
（惰性求值，实测都指到了 fontconfig）：

- `services.flatpak.packages` 被 nix-flatpak 规范化成了 attrset，
  取 `appId` 才是字符串
- `config.dconf.settings` 的值被 home-manager 包成 gvariant
  （`{ _type; type; value; }`，列表里每项再包一层），要剥两层

---

## Shell 环境

登录 shell 是 **zsh**（`modules/shell.nix` 定系统层，`home/toru.nix` 定交互体验）。
bash 保持完全可用，两者配的是同一套基线。

**在这台机器上跑命令（人或 AI）都按下面几条来：**

- **只用 PATH 上的真二进制，不要依赖 alias。**
  `ll`、`gs`、`nrb`、`ncheck` 这些只存在于交互 shell，
  `zsh -c 'll'` / `bash -c 'll'` 一律 command not found。
  `eza` `bat` `fzf` `zoxide` `atuin` `btop` `lazygit` `tmux` `dua` `duf` `direnv` `starship`
  `skills` `skills-update` `state-sync` `migration-check`
  都是真二进制（在 `/etc/profiles/per-user/toru/bin`），可以直接调用。
  `refind-sync` `refind-hwinfo` `efibootmgr` 在系统层
  （`/run/current-system/sw/bin`），同样是真二进制。
  **前两个要 root**，非交互场景直接调会以非零退出并提示用 sudo。
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
5. **仓库里出现 root 拥有的文件，git 和 nix 都会被卡住。**
   根因是 `sudo nixos-rebuild --flake .` 需要写 `flake.lock` 或读 dirty 的 git 树时，
   以 root 身份往仓库里写了东西。症状很有迷惑性：
   `git add` 报 `insufficient permission for adding an object to repository database`，
   而且**只对某些文件失败**——取决于该文件的 blob 哈希前两位落进了哪个
   `.git/objects/XX/` 目录，那个目录恰好是 root 的才会失败。
   预防：重建流程第 3 步（用户态先 `nix build`）先把 `flake.lock` 以 toru 写好；
   `nix flake update` 永远不加 sudo。
   自查：`find . ! -user toru`，修复：`sudo chown -R toru:users .`。
6. **构建通过 ≠ 实机可用，引导这块尤其严重。**
   rEFInd 那一轮五个坑**全部是 `nix build` 通过、只在实机暴露的**：
   `icon` 路径基准写错只显示一个占位小方块而不报错；固件 GOP 压根不提供
   1920×1080；vfat 上 `chmod` 返回 EPERM 让脚本停在第一个文件；
   `sed` 没考虑制表符导致**第二次**运行才堆出重复 NVRAM 项；
   `$(hostname)` 不等于 `hosts/` 下的目录名。
   详见 [Lesson-Learn/0013](Lesson-Learn/0013_REFIND_BOOT.md)。

   两条可迁移的做法：
   **配外部工具的配置格式时先去查它自带的样例文件**（`refind.conf-sample`
   就在 `${pkgs.refind}/share/refind/` 里，查一眼十秒，比实机试错便宜得多）；
   **动引导之前先把退路实际走一遍**，别信「理论上能回退」。

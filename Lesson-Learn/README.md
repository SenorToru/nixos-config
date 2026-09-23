# Lesson-Learn 知识库

这个仓库配置过程中踩过的坑、原因分析和解决方案。

## 组织规则

- **文件名带 4 位十六进制编号**，按**配置发生的先后顺序**排列，不是按主题分类。
  想知道某个配置是怎么演变成现在这样的，从小到大读一遍即可。
- **编号是 4 位大写十六进制**：`0000` → `0009` → `000A` → `000F` → `0010` → …
  一直到 `FFFF`。注意 `0009` 的下一个是 `000A` 而不是 `0010`。
- **新增文档接着当前最大编号加一**。当前最大是 `0016`，**下一个是 `0017`**。
  不要插空、不要复用编号。
- 编号一旦分配就不再变动。文档作废时**加废弃横幅并指向新文档**，不删除、不重排 ——
  历史记录本身有价值，而且重排会让已有的交叉引用全部失效。
- 命名：`XXXX_TOPIC_IN_CAPS.md`，编号后用下划线，主题用大写加下划线。
- `0000` 是长期维护的使用指南，不属于时间线，永远排在最前。

## 索引

| 编号 | 文档 | 主题 | 状态 |
|------|------|------|------|
| `0000` | [NEOVIM_GUIDE](0000_NEOVIM_GUIDE.md) | Neovim + Copilot 完整使用指南（持续更新） | 📖 常读 |
| `0001` | [NEOVIM_LSP_API_FIX](0001_NEOVIM_LSP_API_FIX.md) | `require('lspconfig')` 弃用，改用 `vim.lsp.start()` | ✅ 有效 |
| `0002` | [NEOVIM_PLUGIN_AND_FONT_FIX](0002_NEOVIM_PLUGIN_AND_FONT_FIX.md) | `plugins/init.lua` 缺 `return`；JetBrainsMono 换 CJK 字体 | ✅ 有效 |
| `0003` | [PLUGIN_AND_FONT_ISSUES](0003_PLUGIN_AND_FONT_ISSUES.md) | 同类问题续；**不要直接编辑 `~/.config/nvim/`** | ✅ 有效 |
| `0004` | [SARASA_MONO_FONT_ISSUE](0004_SARASA_MONO_FONT_ISSUE.md) | 字体名 `SarasaMono` 不存在，须写 `Sarasa Mono J` | ✅ 有效 |
| `0005` | [COPILOT_UNZIP_DEPENDENCY](0005_COPILOT_UNZIP_DEPENDENCY.md) | copilot-language-server 解压需要 `unzip` | ✅ 有效 |
| `0006` | [COPILOT_STARTUP_ISSUES](0006_COPILOT_STARTUP_ISSUES.md) | Copilot 启动问题；`checker = false` | ⚠️ 第 3 节已被 `0009` 取代 |
| `0007` | [LAZY_NVIM_DASHBOARD](0007_LAZY_NVIM_DASHBOARD.md) | Lazy.nvim 仪表板用法 | ✅ 有效 |
| `0008` | [COPILOT_OFFLINE_FIX](0008_COPILOT_OFFLINE_FIX.md) | Copilot "Offline" 排查 | ⛔ 已被 `0009` + `000A` 整体取代 |
| `0009` | [COPILOT_GHOST_TEXT_MIGRATION](0009_COPILOT_GHOST_TEXT_MIGRATION.md) | 移除 copilot-cmp 改用行内建议；E21 只读 buffer 问题 | ✅ 有效 |
| `000A` | [NIXOS_CONFIG_AUDIT](000A_NIXOS_CONFIG_AUDIT.md) | `nvim`/`vim` 双派生、5 个无效字体名、默认浏览器 | ✅ 有效 |
| `000B` | [HOME_MANAGER_ACTIVATION_CONFLICT](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md) | `Existing file would be clobbered` 与「半成功」状态 | ✅ 有效 |
| `000C` | [NIX_LD_PREBUILT_BINARIES](000C_NIX_LD_PREBUILT_BINARIES.md) | 预编译二进制的 ELF 解释器写死 `/lib64/...`，靠 nix-ld 转接 | ✅ 有效 |
| `000D` | [CLAUDE_CODE_IN_NEOVIM](000D_CLAUDE_CODE_IN_NEOVIM.md) | 用 claudecode.nvim 在 Neovide 里接入 Claude Code | ⚠️ 接入过程有效；会话操作与键位已被 `0015` 取代 |
| `000E` | [LAZY_NVIM_SLOW_NETWORK_CLONE](000E_LAZY_NVIM_SLOW_NETWORK_CLONE.md) | 慢网下部分克隆装不上插件；`.cloning` 残留标记导致反复重装 | ✅ 有效 |
| `000F` | [LAPTOP_TUNING_AND_AI_FRIENDLY_SHELL](000F_LAPTOP_TUNING_AND_AI_FRIENDLY_SHELL.md) | zram / thermald / VAAPI；zsh + atuin 环境与「不遮蔽标准命令」的 AI 友好约定；`modules/` 与 `hosts/` 的分界 | ✅ 有效 |
| `0010` | [CLAUDE_CODE_VERSION_PINNING](0010_CLAUDE_CODE_VERSION_PINNING.md) | 发布分支冻结在旧版，`nix flake update` 空操作；覆写 manifest 升级 claude-code | ✅ 有效 |
| `0011` | [ROOT_OWNED_FILES_IN_REPO](0011_ROOT_OWNED_FILES_IN_REPO.md) | `sudo nixos-rebuild` 把 `flake.lock` 和 `.git/objects` 写成 root；git 只对哈希前缀撞上的那个文件报错 | ✅ 有效 |
| `0012` | [AGENT_SKILLS](0012_AGENT_SKILLS.md) | Agent Skills 全局安装：一份 skill 喂给 Claude Code / Copilot / Zed / Gemini；开关命令与 token 成本（持续更新） | 📖 常读 |
| `0013` | [REFIND_BOOT](0013_REFIND_BOOT.md) | rEFInd 叠在 systemd-boot 之上做顶层引导入口；`icon` 路径基准、GOP 模式、vfat chmod 等五个实机坑 | ✅ 有效 |
| `0014` | [DNS_HIJACK_AND_DOT](0014_DNS_HIJACK_AND_DOT.md) | 路由器伪造 AAAA 应答导致虚拟机里 Claude Code 连不上；抓包定位 + 改用 DNS-over-TLS。含不预设网络知识的完整讲解 | ✅ 有效 |
| `0015` | [CLAUDE_CODE_NEOVIDE_WORKFLOW](0015_CLAUDE_CODE_NEOVIDE_WORKFLOW.md) | Neovide 里用 Claude Code 的完整教程：会话的新开/切换/分叉/改名/删除、三层模式、面板跳转与调宽、Enter 换行、剪贴板统一；`Space a r` 参数被静默丢弃的根因 | 📖 常读 |
| `0016` | [GROK_BUILD_VERSION_PINNING](0016_GROK_BUILD_VERSION_PINNING.md) | 装 xAI 的 Grok Build：发布分支停在 0.2.93，`overrideAttrs` 换版本号 + 哈希；用 `GROK_DISABLE_AUTOUPDATER` 挡住自更新另装一份 | ✅ 有效 |

## 按主题快速定位

- **Neovim / Copilot** —— `0000`（用法）、`0001`、`0002`、`0003`、`0005`、`0006`、`0007`、`0009`、`000E`、`0015`
- **Agent Skills（跨工具）** —— `0012`
- **其它 AI agent（Grok Build）** —— `0016`
- **Claude Code** —— `000C`、`000D`、`0010`、`0012`、`0014`、`0015`（日常用法）
- **字体** —— `0002`、`0004`、`000A`
- **NixOS / home-manager 机制** —— `0003`、`000A`、`000B`、`000C`、`000F`、`0012`
- **git 与仓库状态** —— `0011`
- **Shell / CLI 环境** —— `000F`
- **仓库分层（modules 与 hosts）** —— `000F`
- **笔电硬件（zram / 温控 / 显卡 / 指纹）** —— `000F`
- **引导（UEFI / rEFInd / systemd-boot / NVRAM）** —— `0013`
- **网络与 DNS** —— `0014`

## 反复出现的坑

几类错误在这个仓库里出现过不止一次，写新配置时值得先扫一眼：

1. **字体族名写错，fontconfig 完全静默回退**（`0004`、`000A`）——
   写完必须 `fc-match "族名"` 验证一次。
2. **直接编辑 `~/.config/nvim/` 不起作用**（`0003`）——
   那些是 home-manager 管的符号链接，必须改 `home/toru.nix` 再 rebuild。
3. **同一个东西在系统层和 home 层各声明一次**（`000A`）——
   Nix 不会报冲突，但会装出两份，行为不一致且极难排查。
4. **`nixos-rebuild switch` 报错不等于没生效**（`000B`）——
   系统层和 home 层是两个阶段，可能出现半成功。
5. **外来的预编译二进制在 NixOS 上起不来**（`000C`）——
   ELF 解释器写死了 `/lib64/ld-linux-x86-64.so.2`，靠 `programs.nix-ld.enable` 转接。
   报的错常常是误导性的 "No such file or directory"。
6. **加服务前先 `nix eval` 查当前值**（`000F`）——
   GNOME 之类的高层模块已经替你开了不少东西（`power-profiles-daemon`、
   `systemd.oomd`、`fstrim`），重复声明不报错，只留下看不出真假的噪音。
7. **绑硬件的配置写进了 `modules/`**（`000F`）—— 这是多机仓库，
   显卡驱动、内存 sysctl、CPU 厂商专属服务、用户名都只对某一台成立，
   必须放 `hosts/<主机>/`。判据：换一台机器还成立吗？
8. **`nix flake update` 没让某个包动，不等于它已是最新**（`0010`）——
   `nixos-26.05` 是发布分支，不跟上游滚。先去查该包在发布分支上的版本，
   而不是怀疑 flake 没更新成功。grok-build 是同样的处境、同样的解法（`0016`）。
9. **仓库里混进 root 拥有的文件**（`0011`）—— `sudo nixos-rebuild --flake .`
   会以 root 身份写 `flake.lock`，读 dirty 工作树时还可能写 `.git/objects`。
   症状极具迷惑性：`git add` 只对**某一个**文件报
   `insufficient permission for adding an object to repository database`，
   点名谁纯看该文件 blob 哈希的前两位撞上了哪个 `.git/objects/XX/`。
   自查 `find . ! -user toru`，修复 `sudo chown -R toru:users .`。
10. **构建通过 ≠ 实机可用，引导这块尤其严重**（`0013`）——
    rEFInd 那一轮五个坑全部是 `nix build` 通过、只在实机暴露的：
    `icon` 路径基准写错只显示一个占位小方块而不报错；固件 GOP 压根不提供
    1920×1080；vfat 上 `chmod` 返回 EPERM 让脚本停在第一个文件；
    `sed` 没考虑制表符导致**第二次**运行才堆出重复 NVRAM 项。
    **动引导之前先实际走一遍退路**，别信「理论上能回退」。
11. **「网络通」不等于「解析对」，而中间设备会伪造 DNS 应答**（`0014`）——
    路由器一个「禁止 AAAA 记录」的勾选框，表现成「虚拟机里 Claude Code 连不上」，
    中间隔了五层。排查 DNS 问题**第一条命令**应该是
    `dig +time=3 +tries=1 A example.org @192.0.2.1` ——
    那个地址全球不可路由，**正常必须超时**，能应答就是有人在截 UDP/53。
    十秒排除一整类原因，那次没先跑它，绕了四个错误假设。
    另一条教训：**对照实验要控制变量** —— 当时用两次 A 查询的结果
    论证「DNS 服务器没问题」，而坏的是 AAAA。

> 补充：**从 GitHub clone 很慢**（实测 ~80 KiB/s），涉及 git clone 的环节要先怀疑超时，
> 别急着怀疑配置写错了 —— 见 `000E`。
> 但这**不是全局网速**：`downloads.claude.ai` 实测 6.4 MB/s（见 `0010`），
> 别拿 GitHub 的数字去否决其它下载。

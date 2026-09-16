# Lesson-Learn 知识库

这个仓库配置过程中踩过的坑、原因分析和解决方案。

## 组织规则

- **文件名带 4 位十六进制编号**，按**配置发生的先后顺序**排列，不是按主题分类。
  想知道某个配置是怎么演变成现在这样的，从小到大读一遍即可。
- **编号是 4 位大写十六进制**：`0000` → `0009` → `000A` → `000F` → `0010` → …
  一直到 `FFFF`。注意 `0009` 的下一个是 `000A` 而不是 `0010`。
- **新增文档接着当前最大编号加一**。当前最大是 `000B`，**下一个是 `000C`**。
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

## 按主题快速定位

- **Neovim / Copilot** —— `0000`（用法）、`0001`、`0002`、`0003`、`0005`、`0006`、`0007`、`0009`
- **字体** —— `0002`、`0004`、`000A`
- **NixOS / home-manager 机制** —— `0003`、`000A`、`000B`

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

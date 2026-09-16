# 本仓库协作约定

Toru 的 NixOS 多机配置仓库（flake，home-manager 作为 NixOS 模块）。

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

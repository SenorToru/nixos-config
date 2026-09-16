# Sarasa Mono 字体名问题修复

## 问题描述

启动 Neovide 后出现字体加载错误：

```
Error: Font can't be updated to: FontOptions {
    normal: [
        FontDescription {
            family: "SarasaMono",
            style: None,
        },
    ],
    ...
}
No candidate fonts could be loaded: ...
```

原因：配置中使用的字体名 `SarasaMono` 在系统中不存在。

## 根本原因

Sarasa Gothic 字体包中的字体名不是 `SarasaMono`，而是包含区域代码的完整名称：
- `Sarasa Mono J` - 日文版本
- `Sarasa Mono SC` - 简体中文版本
- `Sarasa Mono CL` - 繁体中文版本（古典）
- `Sarasa Mono HC` - 繁体中文版本（香港）
- `Sarasa Mono TC` - 繁体中文版本
- `Sarasa Mono K` - 韩文版本

fontconfig 不能进行通用匹配到不存在的字体名。

## 解决方案

根据系统配置的地区设置选择对应的字体：

用户系统配置：
- 时区：`Asia/Tokyo`（日本）
- 语言：`ja_JP.UTF-8`（日文）

选择：**`Sarasa Mono J`**（日文版本）

## 配置修改

**文件：** `/home/toru/nixos-config/home/toru.nix`

**修改前：**
```lua
vim.opt.guifont = "SarasaMono:h12"
```

**修改后：**
```lua
vim.opt.guifont = "Sarasa Mono J:h12"
```

## 关键知识

1. **fontconfig 需要精确匹配**
   - 字体名必须与 `fc-list` 输出中显示的名称完全一致
   - 不支持模糊匹配或通用名称
   - 即使字体在系统中可用，错误的名称也会导致加载失败

2. **Sarasa Mono 的完整字体名格式**
   - 格式：`Sarasa Mono [REGION]`
   - 例如：`Sarasa Mono J`、`Sarasa Mono SC`
   - 不是 `SarasaMono`（没有空格）

3. **在 guifont 配置中使用正确的字体名**
   - Neovide guifont 格式：`FontName:h12`
   - 字体名中的空格是合法的（与之前的多字体逗号分隔不同）
   - 示例：`Sarasa Mono J:h12` ✅
   - 示例：`Sarasa Mono J:h12,Noto Sans:h12` ❌（Neovide 不支持逗号分隔）

4. **验证字体名的方法**
   ```bash
   # 查看系统中所有 Sarasa Mono 字体
   fc-list | grep "Sarasa Mono"
   
   # 查看特定区域的字体
   fc-list | grep "Sarasa Mono J"
   ```

## 部署流程

1. **修改配置**（已完成）
   ```bash
   cd /home/toru/nixos-config
   # 编辑 home/toru.nix
   vim home/toru.nix
   ```

2. **验证配置**（已完成）
   ```bash
   nix flake check
   # 输出：all checks passed! ✅
   ```

3. **部署到系统**（待执行）
   ```bash
   sudo nixos-rebuild switch --flake .#thinkpad
   ```

4. **验证结果**
   ```bash
   # 启动 Neovide，应该无字体错误
   neovide /home/toru/nixos-config
   ```

## 字体选择指南

根据系统区域设置选择对应的 Sarasa Mono 版本：

| 系统配置 | 推荐字体 | 命令验证 |
|--------|---------|--------|
| 日本（ja_JP.UTF-8） | `Sarasa Mono J` | `fc-list \| grep "Sarasa Mono J"` |
| 简体中文（zh_CN.UTF-8） | `Sarasa Mono SC` | `fc-list \| grep "Sarasa Mono SC"` |
| 繁体中文（zh_TW.UTF-8） | `Sarasa Mono TC` | `fc-list \| grep "Sarasa Mono TC"` |
| 韩文（ko_KR.UTF-8） | `Sarasa Mono K` | `fc-list \| grep "Sarasa Mono K"` |

## 额外字体备选

如果想要其他风格的 Sarasa Mono：

```lua
-- Sarasa Mono Slab（带衬线的等距字体）
vim.opt.guifont = "Sarasa Mono Slab J:h12"

-- Sarasa Fixed（另一种等宽字体）
vim.opt.guifont = "Sarasa Fixed J:h12"
```

## 问题排查

如果 Neovide 仍然无法加载字体：

1. **验证字体在系统中存在**
   ```bash
   fc-list | grep "Sarasa Mono J"
   # 应该返回至少一行结果
   ```

2. **验证 Neovim 配置被正确部署**
   ```bash
   # 检查生成的 init.lua
   cat ~/.config/nvim/init.lua | grep guifont
   # 应该显示：vim.opt.guifont = "Sarasa Mono J:h12"
   ```

3. **重建字体缓存（很少需要）**
   ```bash
   fc-cache -fv
   ```

4. **检查 Neovide 版本兼容性**
   ```bash
   neovide --version
   ```

## 关键学习

✅ **始终使用 `fc-list` 验证实际字体名**
❌ **不要假设字体名的格式**
✅ **区域代码很重要**（Sarasa Mono J vs Sarasa Mono SC）
✅ **配置部署需要 `sudo nixos-rebuild switch`**

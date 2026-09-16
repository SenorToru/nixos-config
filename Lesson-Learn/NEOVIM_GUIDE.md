# Neovim + Copilot 完整使用指南

## 第一步：打开项目目录

### 从命令行启动（推荐）
```bash
cd /home/toru/nixos-config
neovide
# 或直接指定目录
neovide /home/toru/nixos-config
```

### 在 Neovide 内打开目录
```vim
:edit .
# 或
:Netrw
```

你会看到文件树浏览器。

---

## 第二步：了解 Neovim 的模式

Neovim 有多种模式，理解这些对使用至关重要：

| 模式 | 如何进入 | 如何退出 | 用途 |
|------|--------|--------|------|
| **Normal** | 启动时默认或按 `Esc` | - | 浏览、删除、复制代码 |
| **Insert** | 按 `i` 或 `a` | `Esc` | 输入代码 |
| **Visual** | 按 `v` (字符) / `V` (行) / `Ctrl+v` (块) | `Esc` | 选择代码 |
| **Command** | 按 `:` | `Esc` | 执行命令 |

---

## 第三步：基本导航快捷键

在 **Normal 模式**（不输入文本时）使用这些快捷键：

### 移动光标
```
h   - 左移
j   - 下移
k   - 上移
l   - 右移

w   - 下一个单词开头
b   - 上一个单词开头
e   - 单词结尾
^   - 行首
$   - 行尾

Ctrl+u - 上翻半屏
Ctrl+d - 下翻半屏
gg  - 文件开头
G   - 文件末尾
:123 - 跳转到第 123 行
```

### 快速定位
```
/pattern    - 搜索 (向下)
?pattern    - 搜索 (向上)
n           - 下一个搜索结果
N           - 上一个搜索结果

gd          - 跳转到定义 (LSP)
gD          - 跳转到声明
Ctrl+]      - 跳转到标签
```

---

## 第四步：打开和编辑文件

### 打开文件
```vim
:e path/to/file.nix        # 打开文件
:e .                       # 打开当前目录浏览器
:e ~/nixos-config          # 打开特定目录
```

### 使用文件浏览器 (Netrw)
1. 执行 `:e .` 打开当前目录
2. 用 `j/k` 上下移动
3. 按 `Enter` 打开文件或目录
4. 按 `-` 返回上级目录
5. 按 `q` 关闭浏览器

### 快速查找文件
```vim
:find modules/development.nix   # 按名称查找
Ctrl+p                          # 模糊查找 (如果装了 fzf/telescope)
```

---

## 第五步：编辑 Nix 文件

### 基本编辑操作
```
i   - 在光标前插入
a   - 在光标后插入
I   - 在行首插入
A   - 在行尾插入
o   - 在下一行插入
O   - 在上一行插入

x   - 删除当前字符
dd  - 删除整行
dw  - 删除单词
d$  - 删除到行尾

y   - 复制 (搭配移动键)
yy  - 复制整行
yw  - 复制单词

p   - 粘贴到后面
P   - 粘贴到前面

u   - 撤销
Ctrl+r - 重做
```

### 编辑 Nix 文件的常用操作

**打开 development.nix**
```vim
:e modules/development.nix
```

**查找 nodejs**
```
/nodejs
n   # 下一个匹配
```

**修改某一行**
```
# 光标在要修改的行上
cw  # 改写单词 (然后输入新内容)
dd  # 删除行
yy  # 复制行
p   # 粘贴
```

**格式化整个文件**
```vim
:!nixfmt %
# 或使用 LSP 格式化
<leader>f
```

---

## 第六步：唤出和使用 Copilot

### 触发 Copilot 建议

**自动建议**（在 Insert 模式）
```
# 进入 Insert 模式
i

# 开始输入
let config =

# Copilot 会自动显示建议（灰色文字）
```

### 接受/拒绝 Copilot 建议

| 快捷键 | 功能 |
|--------|------|
| `Alt+l` | 接受建议 |
| `Alt+]` | 下一个建议 |
| `Alt+[` | 上一个建议 |
| `Ctrl+]` | 拒绝建议 |
| `Alt+Return` | 打开 Copilot 面板 |

### 打开 Copilot 面板（完整建议菜单）

```vim
<在 Insert 模式>
Alt+Return
```

面板打开后：
```
[[  - 上一个建议
]]  - 下一个建议
<CR> (Enter) - 接受当前建议
gr  - 刷新建议
```

### 在补全菜单中使用 Copilot

如果你打开了补全菜单（自动或 `Ctrl+Space`），Copilot 建议会出现在列表顶部：

```
Ctrl+Space  - 触发补全菜单
Ctrl+n      - 下一个选项
Ctrl+p      - 上一个选项
<CR>        - 选择当前选项
```

---

## 第七步：与 Copilot 互动的完整工作流

### 场景 1：让 Copilot 完成一行代码

```
1. 进入 Insert 模式: i
2. 输入一部分: environment.systemPackages = with pkgs; [
3. 等待 Copilot 的灰色建议出现
4. 审阅建议（不接受还继续看）
5. 按 Alt+l 接受
6. 继续编辑或按 Esc 回到 Normal 模式
```

### 场景 2：查看多个建议

```
1. 进入 Insert 模式: i
2. 输入一行: programs.neovim = {
3. 按 Alt+Return 打开 Copilot 面板
4. 用 [[ 和 ]] 浏览不同建议
5. 用 Enter 选择一个
```

### 场景 3：快速补全函数调用

```
1. 在 Insert 模式输入: let result = 
2. Copilot 会建议可能的函数
3. 按 Alt+] 查看下一个建议
4. Alt+l 接受喜欢的建议
```

### 与 Copilot 的最佳实践

1. **写清晰的注释** - Copilot 根据注释生成代码
   ```nix
   # 配置 Nix 语言服务器
   programs.neovim = {
   ```

2. **提供上下文** - 写足够的代码让 Copilot 理解
   ```nix
   environment.systemPackages = with pkgs; [
     nodejs_24
     # Copilot 现在知道应该添加什么类型的包
   ```

3. **审阅建议** - 不要盲目接受，检查是否正确

---

## 第八步：在窗口/界面间切换光标

### 分割窗口

```vim
# 新建分割窗口
:split              # 水平分割
:vsplit             # 垂直分割
:new                # 新的水平窗口
:vnew               # 新的垂直窗口

# 关闭窗口
:close              # 关闭当前窗口
:only               # 只保留当前窗口
```

### 在窗口间移动光标

```
Ctrl+w h    - 移到左边窗口
Ctrl+w j    - 移到下边窗口
Ctrl+w k    - 移到上边窗口
Ctrl+w l    - 移到右边窗口
Ctrl+w w    - 循环切换窗口
```

### 调整窗口大小

```
Ctrl+w =    - 所有窗口等宽/等高
Ctrl+w +    - 增加高度
Ctrl+w -    - 减少高度
Ctrl+w >    - 增加宽度
Ctrl+w <    - 减少宽度
```

### 使用标签页（推荐用于多文件）

```vim
:tabnew             # 新建标签页
:tabnext            # 下一个标签页 (也用 gt)
:tabprevious        # 上一个标签页 (也用 gT)
:tabc               # 关闭当前标签页

# 快捷键
gt              - 下一个标签
gT              - 上一个标签
g[number]t      - 跳转到第 N 个标签 (g1t, g2t ...)
```

---

## 第九步：LSP 和诊断相关快捷键

这些快捷键帮助你导航代码和修复问题：

```vim
gd          - 跳转到定义
gD          - 跳转到声明
K           - 显示悬停文档
<leader>rn  - 重命名符号
<leader>ca  - 代码操作
<leader>f   - 格式化代码

]d          - 下一个诊断
[d          - 上一个诊断
```

---

## 第十步：实战例子

### 完整工作流示例

**目标：在 development.nix 中添加新的 Neovim 配置**

```
1. 打开 Neovide
   $ neovide /home/toru/nixos-config

2. 打开文件浏览器
   :e .
   
3. 找到并打开 modules/development.nix
   # 用 j/k 移动，Enter 打开

4. 导航到要编辑的位置
   /programs.neovim  # 搜索
   n                 # 找到匹配处

5. 进入 Insert 模式开始编辑
   o                 # 在下一行插入

6. 让 Copilot 帮你写代码
   # 输入: environment.systemPackages = with pkgs; [
   # 等待灰色建议
   Alt+l             # 接受

7. 格式化代码
   Esc               # 回到 Normal 模式
   <leader>f         # 格式化

8. 保存文件
   :w                # 保存
   或 Ctrl+s         # 通常也管用

9. 在另一个窗口打开另一文件
   :vsplit           # 垂直分割
   :e home/toru.nix  # 打开另一文件
   
10. 在窗口间切换
    Ctrl+w l        # 移到右边窗口
    Ctrl+w h        # 移到左边窗口

11. 关闭窗口
    :close
```

---

## 快速参考卡

### 最常用快捷键

**编辑**
- `i` - 插入模式
- `Esc` - 回到 Normal 模式
- `dd` - 删除行
- `yy` - 复制行
- `p` - 粘贴
- `u` - 撤销

**Copilot**
- `Alt+l` - 接受建议
- `Alt+]` - 下一个建议
- `Alt+Return` - 打开面板

**导航**
- `/` - 搜索
- `n/N` - 下/上一个搜索结果
- `gg/G` - 文件开头/末尾
- `gd` - 跳转到定义

**窗口**
- `Ctrl+w h/j/k/l` - 切换窗口
- `:vsplit` - 垂直分割
- `:w` - 保存

### 常见命令

```vim
:help topic         # 查看帮助文档
:set number         # 显示行号
:syntax on          # 启用语法高亮
:history            # 查看历史命令
:map                # 查看按键映射
```

---

## 常见问题

### Q: 如何看懂那些菜单（HOME, INSTALL, UPDATE, SYNC）？

**A:** 这是 Lazy.nvim 的插件管理器界面，你可以：
- 按 `Home` 键查看仪表板
- 按 `q` 关闭
- 按 `i` 查看安装状态
- 按 `u` 更新插件
- 按 `s` 同步插件
- 通常你不需要手动操作，插件会自动管理

### Q: 我不小心进入了 Visual 模式怎么办？

**A:** 按 `Esc` 回到 Normal 模式

### Q: Copilot 建议没有出现？

**A:** 
1. 确认在 Insert 模式（左下角显示 `-- INSERT --`）
2. 输入足够的代码上下文
3. 等待 1-2 秒
4. 检查 `:Copilot status`

### Q: 如何保存并退出？

**A:**
```vim
:wq     # 保存并退出
:q!     # 不保存退出
ZZ      # Normal 模式中保存并退出
```

### Q: 如何在 Neovide 中使用系统剪贴板？

**A:**
```vim
"*yy    # 复制到系统剪贴板
"*p     # 从系统剪贴板粘贴
```

---

## 下一步推荐

1. 花 15 分钟学习基本 Vim 操作：`:Tutor` 或访问 vim.org
2. 编辑几个真实的 nix 文件，熟悉工作流
3. 探索 Neovim 插件功能：
   - 模糊查找文件（如果装了 fzf）
   - 文件树浏览
   - 搜索和替换
4. 自定义快捷键（编辑 `~/.config/nvim/init.lua`）

---

## 获取帮助

在 Neovim 中按 `:help` 然后输入主题：

```vim
:help normal-mode       # Normal 模式帮助
:help insert-mode       # Insert 模式帮助
:help keybindings       # 快捷键帮助
:help nvim-lspconfig    # LSP 配置帮助
:help copilot          # Copilot 帮助（如果有）
```

祝你使用愉快！

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

> **重要变更（2026-09-17）**
> Copilot 现在**只走行内建议（ghost text）**这一条路，不再出现在 `nvim-cmp` 的补全菜单里。
> 原因见根目录的 [COMMIT_NOTES.md](../COMMIT_NOTES.md)：负责把 Copilot 塞进补全菜单的
> `copilot-cmp` 插件已停止维护，且与行内建议互相冲突，已被移除。
>
> 同时，打开面板的 `Alt+Enter` 全局映射**已被禁用**（它会把光标锁进一个只读 buffer，
> 导致之后每次输入都报 `E21`）。面板改为用 `:Copilot panel open` 手动打开。

### 触发 Copilot 建议

Copilot 在 Insert 模式下自动触发（`auto_trigger = true`），无需按任何键：

```
# 1. 进入 Insert 模式
i

# 2. 开始输入
environment.systemPackages = with pkgs; [

# 3. 停顿约 1 秒，Copilot 的建议会以**灰色文字**直接显示在光标后面
```

灰色文字就是建议本身，它不是已经输入的内容——不按接受键它不会进入文件。

### 接受/拒绝 Copilot 建议

| 快捷键 | 功能 |
|--------|------|
| `Alt+l` | 接受整条建议 |
| `Alt+]` | 下一个建议 |
| `Alt+[` | 上一个建议 |
| `Ctrl+]` | 拒绝/隐藏当前建议 |

这些键只在 Insert 模式、且当前有灰色建议时才生效；没有建议时按下去就是普通按键。

### 打开 Copilot 面板（一次看多条建议）

面板会在下方开一个窗口，一次列出多条候选：

```vim
:Copilot panel open
```

面板里的按键（**仅在面板窗口内生效**）：

| 按键 | 功能 |
|------|------|
| `[[` | 上一条建议 |
| `]]` | 下一条建议 |
| `Enter` | 接受当前建议 |
| `gr` | 重新请求建议 |

关闭面板：

```vim
:Copilot panel close
```

或者在面板窗口里按 `Ctrl+w c` / `:q`。

> ⚠️ **面板 buffer 是只读的（`modifiable=false`）。**
> 如果你发现自己突然一按 `i` 就报
> `E21: Cannot make changes, 'modifiable' is off`，
> 几乎一定是光标还在面板窗口里。按 `Ctrl+w w` 切回代码窗口，或 `:q` 关掉面板即可。

### 补全菜单（nvim-cmp）里有什么

`Ctrl+Space` 唤出的补全菜单现在只包含 **LSP（nil）/ buffer / path** 三类来源，**没有 Copilot**：

```
Ctrl+Space  - 触发补全菜单
Ctrl+n      - 下一个选项
Ctrl+p      - 上一个选项
<CR>        - 选择当前选项
Ctrl+e      - 关掉菜单
```

补全菜单和 Copilot 的灰色建议**不会互相遮挡**：配置里开了
`hide_during_completion = true`，菜单一弹出，ghost text 自动隐藏；菜单关掉后又出现。

### 常用 Copilot 命令

| 命令 | 作用 |
|------|------|
| `:Copilot status` | 查看当前状态（最常用的排查入口） |
| `:Copilot auth info` | 查看已登录的 GitHub 账号 |
| `:Copilot auth signin` | 重新登录 |
| `:Copilot auth signout` | 登出 |
| `:Copilot panel open` | 打开建议面板 |
| `:Copilot toggle` | 临时开关当前 buffer 的 Copilot |
| `:Copilot version` | 查看 copilot.lua 与 LSP server 版本 |
| `:Copilot model` | 查看/切换使用的模型 |

状态正常时 `:Copilot status` 的输出形如：

```
[Copilot.lua] Authenticated as GitHub user: SenorToru (status: OK)
```

> ⚠️ 旧文档里提到的 `:CopilotStatus` / `:CopilotStart` / `:CopilotReauth` **已被删除**。
> 那三个自定义命令依赖 `copilot.command.auth_setup()` 和 `copilot.api.get_status()`，
> 这两个 API 在新版 copilot.lua 里已经不存在了，调用只会静默失败。
> 请改用上表中的官方 `:Copilot ...` 子命令。

---

## 第七步：与 Copilot 互动的完整工作流

### 场景 1：让 Copilot 补完一行代码

```
1. 进入 Insert 模式: i
2. 输入一部分:     environment.systemPackages = with pkgs; [
3. 停顿 1 秒，等灰色建议出现
4. 审阅建议内容（此时还没写进文件）
5. 满意 -> 按 Alt+l 接受
   不满意 -> 按 Alt+] 换下一个，或 Ctrl+] 直接丢掉
6. 继续输入，或按 Esc 回 Normal 模式
```

### 场景 2：一次比较多条建议

```
1. 进入 Insert 模式并输入开头: programs.neovim = {
2. 按 Esc 回 Normal 模式
3. :Copilot panel open
4. 用 ]] / [[ 在候选之间浏览
5. 在中意的那条上按 Enter 接受
6. 面板自动关闭，光标回到代码窗口
```

### 场景 3：用注释引导 Copilot

Copilot 对注释非常敏感，写清注释比写一半代码更有效：

```nix
# 添加 Python 开发环境需要的包
environment.systemPackages = with pkgs; [
```

停在这里，Copilot 通常会直接给出 `python3`、`python3Packages.pip` 之类的建议。

### 与 Copilot 的最佳实践

1. **写清晰的注释** —— 注释是最强的上下文信号
   ```nix
   # 配置 Nix 语言服务器
   programs.neovim = {
   ```

2. **提供足够上下文** —— 让 Copilot 看到周围代码的风格
   ```nix
   environment.systemPackages = with pkgs; [
     nodejs_24
     # Copilot 现在知道这里该放什么类型的包
   ```

3. **审阅后再接受** —— Copilot 会编造不存在的 nixpkgs 属性名。
   接受后建议用 `nix build` 或 `nix-instantiate --parse` 验证一次。

4. **用 `nvim` 或 `vim` 打开都可以** —— 两者现在指向同一个 neovim
   （详见下面的说明），Copilot 行为一致。

> 📌 **为什么强调这一点**
> 以前 `nvim` 和 `vim` 是两个**不同的** neovim 派生：`nvim` 来自 home-manager
> （wrapper 里带 `node` 和 `unzip`），`vim` 来自系统级 `programs.neovim`（什么都不带）。
> 结果用 `vim` 打开时 Copilot 的 language server 找不到 `node`，直接显示
> `Status: Offline`，而用 `nvim` 打开却完全正常。
> 现在系统级的那份声明已被删除，`nvim` / `vim` / `vi` / `$EDITOR` 全部统一。

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
- `Alt+]` / `Alt+[` - 下/上一个建议
- `Ctrl+]` - 拒绝建议
- `:Copilot panel open` - 打开建议面板（Alt+Enter 已禁用）
- `:Copilot status` - 查看状态

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

## 第十一步：Lazy.nvim 插件管理器仪表板

### 什么是 Lazy.nvim？

Lazy.nvim 是 Neovim 的现代插件管理器。当你启动 Neovide 时，如果启用了 Lazy.nvim，
它可能会自动打开一个管理界面，显示所有已安装的插件及其状态。

### 如何打开 Lazy.nvim 仪表板

```vim
:Lazy
```

按 Enter 或在 Normal 模式下执行上述命令，就会看到插件管理界面。

### 仪表板界面说明

**顶部导航菜单：**
```
Home (H) | Install (I) | Update (U) | Sync (S) | Clean (X) | Check (C) | Log (L) | Restore (R) | Profile (P) | Debug (D) | Help (?)
```

按括号内的快捷键可以在不同的视图间切换：
- `H` - 主界面（Home）- 显示概览和统计
- `I` - Install 视图 - 已安装的插件列表
- `U` - Update 视图 - 可用的更新
- `S` - Sync 视图 - 同步状态
- `X` - Clean 视图 - 清理未使用的插件
- `C` - Check 视图 - 检查插件完整性
- `L` - Log 视图 - 操作日志
- `P` - Profile 视图 - 性能分析
- `D` - Debug 视图 - 调试信息
- `?` - Help 视图 - 帮助文档

### 插件列表中的信息

**插件名称和状态指示：**

| 符号 | 含义 |
|------|------|
| `●` (橙色实心圆) | 插件已加载 |
| `○` (空心圆) | 插件未加载或延迟加载 |
| `⊘` | 已禁用的插件 |

**加载时间信息：**
```
copilot.lua 23.92ms ▶ start
```
- `23.92ms` - 插件加载耗时
- `▶ start` - 标记 (start = 启动时加载, 其他表示按需加载条件)

**依赖关系：**
```
cmp-nvim-lsp ⊘ nvim-lspconfig ⊘ nvim-cmp
```
显示这个插件依赖的其他插件

**更新状态：**
```
■ already up to date      # 已是最新版本
■ updates available       # 有更新可用（橙色）
■ needs install           # 需要安装
```

### 常用操作

**在仪表板中的操作：**

```
q         - 退出仪表板，返回编辑器
Enter     - 进入所选插件的详情页面（显示来源、配置等）
d         - 进入所选插件所在的目录
<Tab>     - 折叠/展开插件的依赖信息
y         - 复制所选插件的信息
r         - 刷新/重新加载所选插件
x         - 删除所选插件
i         - 安装所选插件
u         - 更新所选插件
s         - 同步所选插件
```

**全局操作：**

```
:Lazy install    # 安装缺失的插件
:Lazy update     # 更新所有插件
:Lazy sync       # 同步所有插件（删除、安装、更新）
:Lazy clean      # 清理未使用的插件
:Lazy check      # 检查插件完整性
:Lazy clear      # 清空缓存
```

### 截图界面详细解析

根据启动时显示的那个窗口，这些指标表示：

| 项目 | 含义 | 你的情况 |
|------|------|--------|
| **Total** | 总插件数 | 13 个 |
| **Installed** | 已安装插件 | 11 个（✅ 正常） |
| **Updates** | 有更新的插件 | 1 个（lazy.nvim 有更新） |
| **Not Loaded** | 未加载的插件 | 1 个（cmp-path，这通常正常） |

**问题诊断：**
- ✅ 没有"broken"标签 - 说明没有损坏的插件
- ✅ 没有"missing"标签 - 说明所有依赖都存在
- ⚠️ 1 个插件有更新 - 这不是问题，只是提示有新版本可用
- ℹ️ 1 个插件未加载 - 这通常是按需加载的插件，不是问题

### 常见问题和解决方法

**问题 1: 大量插件显示 "broken" 标签**
```vim
:Lazy clean    # 清理所有坏的插件
:Lazy install  # 重新安装缺失的插件
```

**问题 2: 某个插件显示红色错误**
```vim
# 进入该插件的详情页面（按 Enter）
# 查看错误信息
# 按 L 查看日志
```

**问题 3: 启动时总是出现 Lazy 窗口**

这是 `checker = { enabled = true }` 的表现。我们已经改为：
```lua
checker = { enabled = false }  # 禁用启动检查提示
```

部署后启动就不会再自动出现了。

**问题 4: 更新插件后 Copilot 不工作**
```bash
# 清理缓存
rm -rf ~/.local/share/nvim/copilot.lua/

# 重启 Neovim
# 在 Neovim 中重新认证（注意：不是 auth login，新版子命令是 signin）
:Copilot auth signin
```

### 什么时候应该使用 Lazy

**安装新插件后：**
```vim
:Lazy install
```

**定期检查更新：**
```vim
:Lazy check    # 检查有没有更新
:Lazy update   # 更新所有插件
```

**调试问题：**
```vim
:Lazy debug    # 显示诊断信息
:Lazy log      # 查看操作日志
```

### 访问技巧

- 按 `j/k` 在列表中上下移动
- 按 `/` 搜索插件名
- 按 `?` 显示这个界面的帮助信息
- 按 `q` 随时返回编辑器

---

## 常见问题

### Q: 我看到 Lazy 窗口显示"updates available"是什么意思？

**A:** 这意味着某些插件有新版本可用。你可以：
1. 按 `u` 更新所有插件
2. 或按 `U` 切换到 Update 视图查看详情
3. 不更新也可以正常使用（可选）

### Q: 什么是"Not Loaded"插件？

**A:** 这些是按需加载的插件，只在满足特定条件时才加载（例如编辑特定文件类型时）。
这是正常的，不是问题。常见的按需加载插件：
- `cmp-path` - 编辑文件路径时加载
- `cmp-cmdline` - 在命令行模式时加载
- `cmp-buffer` - 需要时加载

### Q: 我可以从 Lazy 窗口中删除插件吗？

**A:** 可以，但不推荐。更好的方法是：
1. 从 Neovim 配置中删除该插件的定义
2. 运行 `:Lazy clean` 来清理未使用的插件

这样下次启动时插件就不会加载了。
- 通常你不需要手动操作，插件会自动管理

### Q: 我不小心进入了 Visual 模式怎么办？

**A:** 按 `Esc` 回到 Normal 模式

### Q: Copilot 建议没有出现？

**A:** 按顺序排查：
1. 确认在 Insert 模式（左下角显示 `-- INSERT --`）
2. 输入足够的代码上下文，然后停顿 1-2 秒
3. 确认当前文件类型没被禁用（配置里 `help` / `gitcommit` / `gitrebase` 等是关闭的）
4. `:Copilot status` —— 正常应显示 `Authenticated as GitHub user: ...  (status: OK)`
5. 显示未认证就 `:Copilot auth signin`
6. 还是不行就 `:checkhealth copilot`，它会把认证、node、LSP server 全查一遍

注意：建议是**灰色行内文字**，不会出现在 `Ctrl+Space` 的补全菜单里。
如果你是在补全菜单里找 Copilot，那是找不到的——见第六步的说明。

### Q: 一按 `i` 就报 `E21: Cannot make changes, 'modifiable' is off`？

**A:** 你的光标在一个只读 buffer 里，最常见的就是 **Copilot 面板**。

```vim
Ctrl+w w    " 切到下一个窗口（切回代码窗口）
:q          " 或者直接关掉当前这个只读窗口
```

以前这个问题非常容易触发：copilot.lua 默认注册了一个**全局** Insert 模式映射
`Alt+Enter` 用来打开面板，而面板 buffer 是只读且会抢焦点的。在终端里 `Alt+Enter`
通常被拆成 `<Esc><CR>` 所以碰不到，但在 **Neovide 这类 GUI 里它是真正的 `<M-CR>`**，
一不小心就按到，然后就再也打不了字了。

现在该映射已在配置里设为 `open = false` 关闭，面板只能用 `:Copilot panel open`
主动打开，所以不该再遇到。如果还是遇到了，先用上面的办法脱身，再 `:ls` 看看
是哪个 buffer。

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
:help copilot           # Copilot 帮助
:checkhealth copilot    # Copilot 自检（认证/依赖/LSP 全查一遍）
:checkhealth vim.deprecated  # 查有哪些插件在用已废弃的 API
```

祝你使用愉快！

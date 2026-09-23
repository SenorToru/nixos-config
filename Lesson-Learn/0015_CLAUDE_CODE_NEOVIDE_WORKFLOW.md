# 在 Neovide 里用 Claude Code：会话、面板、模式、剪贴板

> 日期：2026-09-23　|　相关配置：`home/toru.nix`（`init.lua`、`plugins/claudecode.lua`、`.claude/keybindings.json`）
>
> 触发场景：每次换会话都要关掉整个 Neovide 重开；分叉出来的会话和原来的同名分不清；
> 进了 Claude 面板就出不来，只能拿鼠标点左边；从外面复制的东西在代码区和
> Claude 输入框里粘贴逻辑不一样；用中日文输入法时 Enter 老是把半句话发出去。

本文分两半。**上半是教程**，日常翻这里；**下半是为什么**，改配置之前看。

---

# 上半：教程

## 〇、速查表

先记住这一张，其余都是展开。leader 是**空格**。

**在代码区（左）：**

| 键 | 作用 |
|---|---|
| `Ctrl+L` | **进 Claude 面板**。面板没开就新建，藏着就显示，开着就聚焦 |
| `Space a c` | 开关 Claude 面板（只切换可见性，不换会话） |
| `Space a z` | Claude 面板最大化（焦点进面板）。再按一次还原 |
| `Ctrl+Shift+H` / `Ctrl+Shift+L` | 分界线左移 / 右移 5%（Claude 变宽 / 变窄） |
| `Space a s`（可视模式） | 把选中的代码发给 Claude |
| `Space a b` | 把当前文件加进 Claude 的上下文 |
| `Space a a` / `Space a d` | 接受 / 拒绝 Claude 提出的 diff |

**在 Claude 面板（右）里：**

| 键 | 作用 |
|---|---|
| `Ctrl+H` | **回代码区**（面板若是最大化的，会先自动还原） |
| `Ctrl+Shift+H` / `Ctrl+Shift+L` | 调宽，不用先离开面板 |
| `Enter` | **换行**（不提交） |
| `Ctrl+Enter` | **提交**。斜杠命令也用它执行 |
| `Alt+Enter` | 提交（兜底，见下半「为什么要两个提交键」） |
| `Esc` | 打断 Claude 的回复。**开了 vim 模式后变成「进 NORMAL」，不再打断** |
| `Ctrl+C` | 打断 Claude 的回复（任何模式都有效） |
| `Ctrl+Shift+V` | 粘贴系统剪贴板里的东西 |

**在 Claude 输入框里打的命令：**

| 命令 | 作用 |
|---|---|
| `/resume` | **换会话**（弹选择器） |
| `/resume 名字` | 直接跳到那个会话 |
| `/clear 旧的名字` | 开新会话，同时给**正在离开的**这个贴上名字 |
| `/branch 新的名字` | 从当前位置分叉，新分支叫这个名字，原会话保持原样 |
| `/rename 名字` | 给**当前**会话改名 |
| `/compact` | 压缩上下文，但还是同一个会话 |

---

## 一、打开 Neovide 之后怎么叫出 Claude

```bash
neovide ~/nixos-config     # 一定要从项目目录打开，原因见第三节「会话按目录存」
```

然后按 **`Ctrl+L`** 或 **`Space a c`**，右边出现面板，光标已经在输入框里了。

就这样。**永远不需要为了换会话而重启 Neovide** —— 以前需要，是配置的锅，已经修掉了。

---

## 二、先搞清楚你在哪一层

面板里同时叠着三层「模式」，你觉得乱，是因为三层长得一样、却各管各的：

```
┌─ Neovide ─────────────────────────────────────────────────────────────┐
│  左：代码区                 右：Claude 面板（nvim 里的一个终端 buffer）   │
│  ┌─────────────────┐       ┌─ 第 2 层：nvim 终端模式 ─────────────────┐  │
│  │ 第 1 层：         │       │                                        │  │
│  │ nvim 的           │       │  终端模式（t）⇄ 终端普通模式（nt）       │  │
│  │ Normal / Insert / │       │  按键全给 Claude    按键给 nvim，可以翻页 │  │
│  │ Visual            │       │                     选中、复制            │  │
│  │                   │       │  ┌─ 第 3 层：Claude 自己的输入框 ──────┐  │  │
│  │                   │       │  │  （开了 vim 模式才有）              │  │  │
│  │                   │       │  │  INSERT ⇄ NORMAL                  │  │  │
│  │                   │       │  └───────────────────────────────────┘  │  │
│  └─────────────────┘       └────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

**每一层怎么进出：**

| 层 | 进 | 出 |
|---|---|---|
| 1 → 2（代码区 → 面板） | `Ctrl+L` | —— |
| 2 → 1（面板 → 代码区） | —— | `Ctrl+H` |
| 2 内部：t → nt | `Ctrl+\` 然后 `Ctrl+N` | —— |
| 2 内部：nt → t | `i` 或 `Ctrl+L` | —— |
| 3 内部：INSERT → NORMAL | `Esc` | —— |
| 3 内部：NORMAL → INSERT | `i` / `a` / `A` / `o` … | —— |

**记住一个规律就够：`Esc` 永远归最里面那一层。** 你在面板里按 `Esc`，它穿过 nvim 直接送到 Claude —— 没开 vim 模式时是「打断回复」，开了是「进 NORMAL」。所以 `Esc` **永远不会**让你离开面板。离开面板只有 `Ctrl+H`。

**什么时候需要第 2 层的 nt 模式？** 只有一种情况：想用键盘在 Claude 的**输出**里选中一段复制出来（见第七节）。平时翻页用滚轮或 `PgUp`/`PgDn` 就行，不需要进 nt。

---

## 三、会话（Session）

### 3.1 概念：会话 ≠ 面板

**一个会话 = 一次 Claude 对话 = 磁盘上一个文件：**

```
~/.claude/projects/-home-toru-nixos-config/3eed130f-19e8-405b-b91b-3e63755c4657.jsonl
                   └──── 由目录名转来 ─────┘ └──────────── 会话 ID ─────────────┘
```

**右边那个面板只是容器。** 关掉面板，会话文件还在；开一个新面板，不等于开了新会话。换会话是在**面板里面**用命令换，面板本身从头到尾不用动。

会话**按目录**存。从家目录打开 Neovide，`/resume` 里就看不到 `nixos-config` 的会话 —— 所以第一节要从项目目录打开。

### 3.2 新开一个会话：`/clear`

```
/clear 路由器-IPv6        ← 名字贴给「正在离开的」这个，新会话从零开始、暂时无名
/clear                   ← 不贴名字
```

⚠️ **名字给的是旧的，不是新的。** 这是最容易记反的地方。
想给新会话起名，进去之后再 `/rename 名字`。

⚠️ **陷阱**：如果你先 `/rename foo`，再**不带参数** `/clear`，新会话会**继承** `foo` 这个名字 —— 你又得到两个同名的。所以 `/clear` 时习惯性带上名字。

### 3.3 切换会话：`/resume`

打 `/resume`，按 **`Ctrl+Enter`**（Enter 现在是换行，见第五节），弹出选择器：

| 键 | 作用 |
|---|---|
| `↑` / `↓` | 上下选 |
| `Enter` | 切过去（选择器里 Enter 照常是确认） |
| `Space` | 预览这个会话的内容 |
| `Ctrl+R` | **给高亮的这个改名** |
| 直接打字或 `/` | 搜索过滤 |
| `Ctrl+A` | 显示本机**所有项目**的会话（再按一次回来） |
| `→` / `←` | 展开 / 折叠分组 |
| `Esc` | 退出选择器 |

每一行显示：名字（没起名就是 AI 生成的标题）、多久前动过、git 分支、文件大小。

知道名字的话直接 `/resume 名字`，不弹选择器。

⚠️ 切过去之后**权限模式不会恢复**成那个会话原来的，而是沿用你当前的。

### 3.4 分叉：`/branch`

```
/branch 试试-streaming-方案
```

从当前位置复制一份对话、切进新的那份。**原会话原封不动**，名字也不变。

**不要不带名字就分叉。** 不带名字时，新分支按**第一句提示词**命名 —— 而原会话的标题也是从同一句第一句生成的，所以两个必然一模一样。你之前分叉出来的会话和原会话同名，就是这么来的。

### 3.5 改名：`/rename`

```
/rename nixos-配置主线
```

改的是**当前**会话。改别的会话：`/resume` 进选择器，选中它，按 `Ctrl+R`。

### 3.6 删除

大多数时候**不用删**：

- **30 天没动过的会话会被自动清掉**（设置项 `cleanupPeriodDays`，默认 30）。选择器的杂乱会自己收敛。
- 反过来要注意：**想长期留着的会话，30 天不碰就没了。**
- 整个项目一次清空：`claude project purge`
- 非要删某一个：选择器里没有删除键，只能手动删文件
  ```bash
  rm ~/.claude/projects/-home-toru-nixos-config/<会话ID>.jsonl
  ```
  会话 ID 在 `/resume` 选择器里看不到，可以按修改时间对：`ls -lt ~/.claude/projects/-home-toru-nixos-config/`

### 3.7 什么时候该开新会话

一个信号就够：**话题变了。**

真实的例子：一个会话从 NixOS 配置聊着聊着漂到了路由器和运营商的 IPv6 设置，一晚上滚到 12.6 MB。第二天想接着聊 NixOS，只能回到分叉之前那个旧会话。

正确的做法是在话题漂走的**那一刻**：

```
/clear 路由器-IPv6排查        ← 把漂走的这段贴上标签存起来，自己回到干净的上下文
```

以后想接着查路由器，`/resume 路由器-IPv6排查`。

**`/clear` 和 `/compact` 怎么选：**
- 话题变了 → `/clear`（新会话，旧的存档）
- 同一件事做太久、上下文快满了 → `/compact`（压缩，还是同一个会话）

---

## 四、面板和代码区：移动、调宽、最大化

### 4.1 来回跳

```
   代码区  ──── Ctrl+L ────▶  Claude 面板
          ◀─── Ctrl+H ────
```

一左一右，和面板的位置对应。`Ctrl+H` 在任何时候都能用，不管 Claude 是不是在输出；按下去不会发任何东西给 Claude。

以前要按 `Ctrl+\` `Ctrl+N` 再 `Ctrl+W` `H` 四下，现在一下。

### 4.2 调宽

**`Ctrl+Shift+H`**：分界线往左 5%，Claude 变宽。
**`Ctrl+Shift+L`**：分界线往右 5%，Claude 变窄。

在代码区和面板里都能按，**在面板里打字时按也不会打断输入**。两边都至少保留 20 列，不会一不小心把某一边挤没。

打开时默认 35%。

### 4.3 最大化

**`Space a z`**（在代码区按）：面板占满全屏，焦点自动进面板。用来读长回复。

**还原**：直接 `Ctrl+H` 回代码区，会**自动还原**成最大化之前的宽度 —— 回代码区当然是要看代码。也可以在代码区再按一次 `Space a z`。

---

## 五、输入框：Enter 换行，Ctrl+Enter 提交

| 键 | 作用 |
|---|---|
| `Enter` | 换行 |
| `Ctrl+Enter` | 提交 |
| `Alt+Enter` | 提交（兜底） |

这样用中日文输入法时，Enter 误触最多多一个空行，不会把半句话发出去。

⚠️ **斜杠命令也要 `Ctrl+Enter`。** 打完 `/resume` 按 Enter 只会换行。这是这个设置唯一的代价。

**不受影响的地方**（它们是别的界面，Enter 照常是确认）：权限确认框、`/resume` 选择器、`/config` 设置面板、`/model` 选模型。

`Ctrl+Enter` 在 Claude 那边默认其实是 `chat:sendNow`（会**打断**正在进行的回复）。这里改成了普通的 `chat:submit`，Claude 正在干活时按它，消息**排队、不打断**：

- 普通消息：等手头这批工具调用做完，就在**同一轮里**递给 Claude
- 斜杠命令：等**整轮**结束才执行

想打断：

- **`Ctrl+C`** —— 打断当前回复。硬编码的，任何模式下都有效
- **`Ctrl+X` `Ctrl+S`** —— 打断，并把排队的消息立刻发出去（`chat:sendNow` 的另一个默认键，没被改掉）

别指望 `Esc`：开了 vim 模式后，`Esc` 在 INSERT 里只是进 NORMAL，**不会**打断回复。

---

## 六、在输入框里用 vim：`b`、`dw`、`ciw`

### 6.1 打开

在 Claude 输入框里打 `/config`，找到 **Editor mode**，改成 **vim**。

（这个设置写进 `~/.claude/settings.json`，那个文件在 `CLAUDE.md` 里划成 B 类 —— `/config` 运行时会改它，`state-sync` 负责带走，所以不放进 Nix。）

### 6.2 最先要知道的两件事

1. **开了之后，面板一进来是 INSERT，和平常一样直接打字。** 想用 vim 键时按 `Esc` 进 NORMAL。
2. ⚠️ **在 NORMAL 模式下打 `/`，打开的是历史搜索，不是斜杠命令。** 要打 `/resume` 必须先 `i` 回 INSERT。这个一定会踩一次。

### 6.3 练习顺序

输入框里先随便打一句：

```
please refactor the config loader to use the new parser
```

然后 `Esc` 进 NORMAL，按下面的顺序练：

| 练什么 | 按键 | 效果 |
|---|---|---|
| 按词跳 | `b` `b` `b` | 往回跳三个词 |
| | `w` `e` | 往前跳到下个词开头 / 词尾 |
| | `0` `$` | 跳到行首 / 行尾 |
| | `f` `p` | 跳到下一个 `p` |
| 删词 | 光标放在 `new` 上，`dw` | 删掉 `new ` |
| **改词**（最常用） | 光标放在 `config` 中间任意位置，`ciw` | 删掉整个 `config` 并进入 INSERT，直接打新词 |
| 改引号里的 | 光标在 `"..."` 里，`ci"` | 清空引号内部，进入 INSERT |
| 改括号里的 | `ci(` | 同上，括号版 |
| 撤销 | `u` | |
| 重复上一次修改 | `.` | 刚 `ciw` 改完一个词，移到另一个词按 `.` 就同样改掉 |

**`ciw` 为什么值得先学**：`dw` 要求光标在词**开头**，`ciw` 在词的**任何位置**都行 —— `i` 是 inner，`w` 是 word，「改掉光标所在的这个词」。

支持的文本对象：`iw` `aw` `iW` `aW` `i"` `a"` `i'` `a'` `i(` `a(` `i[` `a[` `i{` `a{`。
不支持：块选择（`Ctrl+V`）。

### 6.4 可选：`jj` 回 NORMAL

嫌 `Esc` 远，可以在 `~/.claude/settings.json` 里加：

```json
"vimInsertModeRemaps": { "jj": "<Esc>" }
```

一秒内连按两下 `j` 就回 NORMAL，两个 `j` 都不会留在输入框里。

---

## 七、往回翻 Claude 的输出，以及复制出来

**只是看**：鼠标滚轮，或者 `PgUp` / `PgDn`。不需要切任何模式。

**要复制一段出来**：

- 鼠标：直接拖选，然后 `Ctrl+Shift+C`
- 纯键盘：
  1. `Ctrl+\` `Ctrl+N` 进终端普通模式（nt）
  2. 用 `k` `j` `/关键词` 移到要复制的地方
  3. `v` 开始选，移动光标扩大选区
  4. `y` 或 `Ctrl+Shift+C` 复制（直接进系统剪贴板）
  5. `i` 或 `Ctrl+L` 回到输入状态

---

## 八、剪贴板：统一成终端风格

**一句话：从外面来、往外面去，都用 `Ctrl+Shift+C` / `Ctrl+Shift+V`。** 和 Ghostty 里的手感一样。

| 场景 | 复制 | 粘贴 |
|---|---|---|
| 代码区 | 选中后 `y` 或 `Ctrl+Shift+C` | `p` 或 `Ctrl+Shift+V` |
| Claude 面板 | 见第七节 | `Ctrl+Shift+V` |
| 代码区的插入模式 / 命令行 | —— | `Ctrl+Shift+V` |

代码区的 `y` / `p` 现在直通系统剪贴板，所以从浏览器复制的东西 `p` 就能贴出来，`y` 出去的也能直接贴进浏览器。

**三个要知道的地方：**

1. **`Ctrl+C` / `Ctrl+V` 不能用来复制粘贴。** 在 Claude 面板里 `Ctrl+C` 是打断、`Ctrl+V` 是粘贴**图片**；在代码区 `Ctrl+V` 是块选择。
2. **代码区里 `d` / `x` / `c` 删掉的内容也会进系统剪贴板**，会覆盖掉你刚从外面复制的东西。先粘贴、再删，或者删的时候用 `"_d`（删进黑洞寄存器）。
3. **Claude 的 vim 模式里的 `y` / `p` 是 Claude 自己的寄存器**，和 nvim、和系统剪贴板都不通。在 Claude 输入框里粘贴外面的东西，一律 `Ctrl+Shift+V`。

---

## 九、第一次 `nrb` 之后的实机验证

逐条过一遍，任何一条不对就说明配置没生效或者有我没测到的情况：

- [ ] `claude --version` 是 2.1.280（见 [0010](0010_CLAUDE_CODE_VERSION_PINNING.md)）
- [ ] 打开 Neovide，`Ctrl+L` 能叫出面板，光标在输入框里
- [ ] 面板里打几个字，`Backspace` 能正常删（`Ctrl+H` 映射没有误伤退格）
- [ ] 面板里 `Ctrl+H` 回到代码区；代码区 `Ctrl+L` 回到面板
- [ ] `Ctrl+Shift+H` / `Ctrl+Shift+L` 能调宽，在面板里按也行
- [ ] `Space a z` 最大化，`Ctrl+H` 回代码区时自动还原
- [ ] 输入框里 `Enter` 换行、`Ctrl+Enter` 提交
- [ ] **`Ctrl+Enter` 提交不了的话**，试 `Alt+Enter` —— 能用说明 Claude 没开 kitty 键盘协议（见下半「为什么要两个提交键」），告诉我
- [ ] 打 `/resume` + `Ctrl+Enter`，选择器弹出，`Enter` 能切过去
- [ ] 从浏览器复制一段文字：代码区 `p`、Claude 面板 `Ctrl+Shift+V` 都能贴出来
- [ ] 用中文或日文输入法打一句话，确认选词时的 Enter 不会把消息发出去

---

# 下半：为什么是这样

## 问题症状

1. **换会话必须关掉 Neovide 重开。** 面板开着的时候按 `Space a r`，面板闪一下，没有选择器。
2. **分叉出来的会话和原会话同名**，在选择器里分不清。
3. **进了面板出不来**。`Ctrl+\` `Ctrl+N` 记不住，只能拿鼠标点左边。
4. **剪贴板两边逻辑不一致**：从外面复制的东西，代码区里 `p` 不出来；往 Claude 输入框里贴又是另一套。
5. **中日文输入法下 Enter 误提交。** 配置注释里明明写着「Enter 留给换行」。

## 根本原因分析

### 一、`Space a r/R/C` 的参数被插件静默丢弃

`claudecode.nvim` 的 snacks 后端：

```lua
-- lua/claudecode/terminal/snacks.lua
function M.simple_toggle(cmd_string, env_table, config)
  if terminal and terminal:buf_valid() then
    if cc_is_visible(terminal) then cc_hide(terminal)       -- 只是藏起来
    else cc_show(terminal, true, config) end                -- 只是显示出来
  else
    M.open(cmd_string, env_table, config)                   -- 只有这里才真的带参数启动
  end
end
```

终端 buffer 只要还活着，`--resume` / `--fork-session` / `--continue` 就被算出来然后丢掉，
按键退化成开关面板。关掉整个 Neovide 之所以「有用」，是因为那是唯一能让那个
buffer 死掉的办法。

**这个坑 [000D](000D_CLAUDE_CODE_IN_NEOVIM.md) 第 6 条早就记过了**，连 `/resume` 这个正确做法都写了 ——
但那三个键留在配置里没删。文档说「别这么用」，配置却一直把这个键递到手边。
**教训：记下一个坑但不拆掉它，等于没记。** 能从配置里消除的坑，就别只写进文档。

### 二、分叉时不给名字，新分支按第一句提示词命名

官方文档：

> If you omit the name, Claude Code names the new branch after the first prompt in the conversation.

原会话没起过名的话，它的标题也是从同一句第一句提示词生成的。两个必然一样。
`--fork-session`（`Space a R` 用的就是它）同理。

### 三、nvim 没设 `clipboard`，Neovide 没映射任何粘贴键

```
nvim 剪贴板提供者    wl-copy       ✅ 正常（Wayland）
vim.opt.clipboard    （没设）       ← 代码区 y/p 只在 nvim 内部转
Neovide 粘贴键       （一个都没有）  ← 面板和代码区都没有统一的粘贴键
```

提供者一直是好的，`"+p` 一直能用 —— 只是没人会记得每次多打 `"+`。

### 四、Enter 从来没被解绑

旧配置：

```nix
bindings = {
  "ctrl+enter" = "chat:submit";
  "alt+enter" = "chat:submit";
};
```

`chat:submit` 的**默认键就是 Enter**。加两个新绑定不会顶掉默认绑定。
注释写的「Enter 留给换行」从一开始就不成立。

### 五、三层模式长得一样

见上半第二节的图。没有人告诉你面板里叠着三层，而 `Esc` 永远只归最里层 ——
于是按 `Esc` 想离开面板，结果是打断了 Claude。

## 已实施的修复

| 改动 | 位置 |
|---|---|
| 删除 `Space a r` / `a R` / `a C` | `plugins/claudecode.lua` 的 `keys` |
| 新增 `Ctrl+H`（终端模式）/ `Ctrl+L`（普通模式）跳转 | 同上 |
| 新增 `Ctrl+Shift+H` / `Ctrl+Shift+L` 调宽 5% | 同上 |
| 新增 `Space a z` 最大化，`Ctrl+H` 离开时自动还原 | 同上 |
| `vim.opt.clipboard = "unnamedplus"` | `init.lua` |
| `Ctrl+Shift+C`（可视）/ `Ctrl+Shift+V`（普通、插入、命令行、终端） | `init.lua` |
| `enter` → `chat:newline` | `.claude/keybindings.json` |

## 为什么这样解决

### 为什么是 `Ctrl+H` / `Ctrl+L`

约束有三条：

1. **`Esc` 不能碰。** 它在 Claude 里同时是「打断」「进 vim NORMAL」「双击清空草稿 / 打开回退菜单」。
2. **Claude 占了这些 Ctrl 键**：`C D G L O R V B T S Z P N A E K U W Y J`。
   经典的 `Ctrl+H/J/K/L` 窗口导航里 J、K、L 全被占了。
3. **面板在右边**，从面板出发只需要往左这一个方向。

`Ctrl+H` 是唯一剩下的，又恰好是需要的那个方向。

但 `Ctrl+H` 在 Claude 的文档里是**保留键**（发退格字节 `0x08`）。风险是：
nvim 这层要是把 `Ctrl+H` 和 `Backspace` 当成同一个键，映射之后面板里就没法删字了。
**实测**（下面第三节的方法）：映射后 `Backspace` 仍以 `0x7f` 原样送进终端，
`Ctrl+H` 被 nvim 截走、成功退出终端模式。二者在 Neovide + nvim 这条链路上是分得开的。

`Ctrl+L` 只映射在普通模式，所以在面板里按 `Ctrl+L` 仍然是 Claude 的「重绘屏幕」，不受影响。

### 为什么 `Ctrl+L` 用 `ClaudeCodeFocus`，又要单独处理一个分支

`ClaudeCodeFocus` 三种情况都对：面板藏着就显示、开着就聚焦、没开过就新建。
但它还有第四个分支：**你已经身处面板里时，它会把面板藏起来**。
从代码区按 `Ctrl+L` 碰不到这个分支；但在面板的终端普通模式（nt）里按，会碰到 ——
那一刻你人在面板里。所以 `enter_panel()` 先判断当前窗口是不是面板，是的话只 `startinsert`。

### 为什么要两个提交键：实测数据

`Ctrl+Enter` 能不能和 `Enter` 区分，取决于终端有没有开 **kitty 键盘协议**。
在 nvim 0.12.4 的终端里，把各种键发给一个打印原始字节的子进程：

| 按键 | 传统模式 | kitty 协议 |
|---|---|---|
| `Enter` | `0a` | `0a` |
| `Ctrl+Enter` | `0a` ← **和 Enter 一样** | `ESC[13;5u` |
| `Alt+Enter` | `ESC 0a` | `ESC[13;3u` |
| `Shift+Enter` | `0a` ← 和 Enter 一样 | `ESC[13;2u` |
| `Backspace` | `7f` | `7f` |
| `Ctrl+H` | `08` | `ESC[104;5u` |

（`modifyOtherKeys` 模式 nvim 0.12 不支持，结果和传统模式相同。）

再测 nvim 的终端对协议查询 `CSI ? u` 的回应：`ESC [ ? 0 u` —— **支持**。
Claude 启动时会先问，终端答了就开，所以正常情况下 `Ctrl+Enter` 能用。

但这是间接证据：我验证的是「nvim 会回答、开了之后编码正确」，没法在无头环境里验证
「Claude 确实会去开」。所以留 `Alt+Enter` 兜底 —— 它在传统模式下是 `ESC 0a`，
**任何情况下都和 `Enter` 分得开**。

### 为什么剪贴板选终端风格而不是 `Ctrl+C` / `Ctrl+V`

`Ctrl+C`、`Ctrl+V` 在这里有三个本职工作：打断 Claude、粘贴图片、vim 块选择。
`Ctrl+Shift+C` / `Ctrl+Shift+V` 谁都没占，而且和 Ghostty 的手感一致。

终端模式的粘贴走 `vim.api.nvim_paste()` 而不是直接发字符 —— 它会用 bracketed paste
把内容包起来，Claude 就知道这是粘贴进来的一整块，多行内容里的换行不会被逐行当成提交。

### 测试方法（以后改键位时复用）

在无头 nvim 里起一个终端、跑一个打印原始字节的子进程、逐个喂键、读终端 buffer。
**两个坑**：

1. `vim.wait()` 在 `-c` 执行期间**不处理 typeahead**，`nvim_input()` 喂的键根本不会被消费。
   必须用 `vim.defer_fn` 链起来，让 `-c` 先返回、主循环真正跑起来。
2. `startinsert` 在无头模式下同样不会立刻生效（停在 `nt`）。要喂一个 `i` 进终端模式。

测配置本身时，用**新生成的** home 层配置 + 一个假的 `claude`：

```bash
NV=<neovim-unwrapped 的路径>   # 必须绕开 wrapper，否则 wrapper 会把真 claude 排在 PATH 最前
env HOME=<临时目录> \
    XDG_CONFIG_HOME=/tmp/hm/home-files/.config \
    XDG_DATA_HOME=$HOME/.local/share \
    PATH="<放假 claude 的目录>:$PATH" \
    $NV --headless -c "luafile 测试脚本.lua"
```

`HOME` 要指到临时目录：claudecode.nvim 会往 `~/.claude/ide/` 写锁文件，
不隔离的话会干扰正在运行的真 Claude Code 的 IDE 连接。

## 后续注意事项

- **`Space a c` 只切换面板可见性，不换会话。** 换会话永远是面板里的 `/resume`。
- **`Ctrl+Shift+V` 粘贴进面板没有做自动化测试**：测它要往真实的系统剪贴板里写东西，
  会覆盖掉当时剪贴板里的内容。靠实机验证清单那一条。
- **Neovide 能不能把 `Ctrl+Shift+字母` 和 `Ctrl+字母` 分开交给 nvim**，无头测试替代不了
  （无头测试里是直接往 nvim 喂 `<C-S-h>`，跳过了 Neovide）。实机清单里有对应条目。
- `<C-h>` 的终端模式映射是**全局**的，不只在 Claude 面板里。在 nvim 里开别的 `:terminal`
  时，`Ctrl+H` 同样会跳到左边窗口。
- **会话 30 天不动会被自动删除**（`cleanupPeriodDays`）。要长期保留某段对话，
  要么隔段时间 `/resume` 进去动一下，要么 `/export` 成文本存起来。
- 想改提交键或换行键，改 `home/toru.nix` 里的 `home.file.".claude/keybindings.json"`。
  **别用 `/keybindings` 在 Claude 里改**：那个文件是 home-manager 管的只读符号链接，改不了，
  而且改了也会在下次 `nrb` 时被覆盖。

## 相关文档

- [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md) —— claudecode.nvim 的接入过程；第 6 条是本文第一个根因的最初记录
- [0010_CLAUDE_CODE_VERSION_PINNING.md](0010_CLAUDE_CODE_VERSION_PINNING.md) —— claude-code 的升级方法；`/rename`、选择器里的 `Ctrl+R` 需要的版本
- [0000_NEOVIM_GUIDE.md](0000_NEOVIM_GUIDE.md) —— Neovim 本身的基础操作
- [0009_COPILOT_GHOST_TEXT_MIGRATION.md](0009_COPILOT_GHOST_TEXT_MIGRATION.md) —— Copilot 的 `Alt` 系列键位，和本文的 `Ctrl` 系列不冲突

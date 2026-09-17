# lazy.nvim 在慢网下装不上插件：部分克隆与 .cloning 残留标记

> 日期：2026-09-17　|　相关配置：`home/toru.nix` 的 `nvim/lua/config/lazy.lua`
>
> 触发场景：给 Neovim 接入 Claude Code 后首次启动，
> snacks.nvim 死活装不上（见 [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md)）。

## 问题症状

启动 Neovide，lazy.nvim 面板里 snacks.nvim 一直在 **Failed**：

```
Failed (1)
  ○ snacks.nvim  claudecode.nvim
      Cloning into '/home/toru/.local/share/nvim/lazy/snacks.nvim'...
      remote: Total 13280 (delta 55), reused 30 (delta 30), pack-reused 13217 (from 3)
      Receiving objects: 100% (13280/13280), 2.68 MiB | 82.00 KiB/s, done.
      Resolving deltas: 100% (7898/7898), done.
      warning: Clone succeeded, but checkout failed.
      You can inspect what was checked out with 'git status'
      and retry with 'git restore --source=HEAD :/'

      Process was killed because it reached the timeout

Loaded (5)
  ● lazy.nvim 120109.21ms  init.lua
```

两个关键线索：

1. **`Clone succeeded, but checkout failed`** —— clone 成功了，却卡在 checkout。
2. **`lazy.nvim 120109.21ms`** —— 正好 120 秒，是 lazy.nvim 默认的 `git.timeout`。

## 根本原因（两个叠在一起）

### 原因 1：部分克隆让 checkout 变成第二次联网

lazy.nvim 默认用**部分克隆（partial clone）**：

```lua
-- lazy.nvim/lua/lazy/manage/task/git.lua:139
if Config.options.git.filter then
  args[#args + 1] = "--filter=blob:none"
end
```

`--filter=blob:none` 的意思是：初次只拉 commit 和 tree 对象，**文件内容（blob）不拉**，
等到真正需要某个文件时再按需从网络取。

正常网速下这是个很划算的优化 —— 初次下载量小很多。
但它有个前提：**后续的按需拉取是廉价的。**

本机实测下行只有 ~80 KiB/s。于是：

```
git clone --filter=blob:none   -> 2.68 MiB，能在超时内跑完   ✅
git checkout（要拉全部 blob）   -> 又一次完整的网络往返       ❌ 超时被杀
```

这就是为什么日志写着「clone 成功，checkout 失败」—— 真正耗时的不是 clone，是 checkout。

验证方式：手动补 checkout 时能明显看出它在联网，而不是本地解包。

```bash
cd ~/.local/share/nvim/lazy/snacks.nvim
git status --short | head        # 全是 D，说明文件在 HEAD 里但工作区没有
du -sh .                         # 只有 14M（纯 .git，无 blob）
git reset --hard HEAD            # 这一步会跑很久，因为在下载 blob
du -sh .                         # 完成后 41M
```

### 原因 2：`.cloning` 残留标记让修好的目录被反复删掉

**这一条才是最坑的。** 手动把 checkout 补完、`git status` 干净、
`lua/snacks/init.lua` 都在了，重启 Neovim —— lazy 还是把整个目录删掉重新 clone。

原因在 lazy.nvim 判断「插件是否已安装」的逻辑里：

```lua
-- lazy.nvim/lua/lazy/core/plugin.lua:219-231
local installed = {}
Util.ls(Config.options.root, function(_, name, type)
  if type == "directory" and name ~= "readme" then
    installed[name] = type
  elseif type == "file" and name:sub(-8) == ".cloning" then
    name = name:sub(1, -9)
    cloning[#cloning + 1] = name
  end
end)

for _, failed in ipairs(cloning) do
  installed[failed] = nil        -- ← 有 .cloning 标记就当成没装
end
```

lazy 在 clone 开始时会在插件根目录写一个 `<插件名>.cloning` 空文件，
clone 正常结束就删掉。**但如果进程是被超时杀掉的，这个标记就留下来了。**

于是每次启动，lazy 看到标记 → 认定该插件未安装 → 删掉目录重新 clone →
又超时被杀 → 标记继续残留。**死循环，而且手动修目录完全没用。**

```bash
$ ls -la ~/.local/share/nvim/lazy/ | grep -i "cloning\|snacks"
drwxr-xr-x  3 toru users 4096 ... snacks.nvim
-rw-r--r--  1 toru users    0 ... snacks.nvim.cloning     # ← 罪魁祸首
```

## 解决方法

### 1. 清掉残留状态（一次性）

```bash
rm -rf ~/.local/share/nvim/lazy/snacks.nvim \
       ~/.local/share/nvim/lazy/snacks.nvim.cloning
```

**标记文件必须一起删**，只删目录没用。

### 2. 手动做一次完整克隆（一次性）

慢网下让 lazy 自己装很容易再次超时，直接在命令行装，不受 lazy 超时限制：

```bash
cd ~/.local/share/nvim/lazy
git clone --recurse-submodules --origin=origin \
  https://github.com/folke/snacks.nvim.git snacks.nvim
```

注意**不加 `--filter`** —— 完整克隆一次把 blob 全拉下来，checkout 是纯本地操作。

### 3. 改配置（永久）

`home/toru.nix` 里 `nvim/lua/config/lazy.lua`：

```lua
require("lazy").setup({
  spec = { { import = "plugins" } },
  checker = { enabled = false },

  git = {
    timeout = 600,   -- 默认 120 秒，慢网下不够
    filter = false,  -- 关掉部分克隆，避免 checkout 变成第二次联网
  },
})
```

## 为什么这样解决

### 为什么关掉 `filter` 而不是只调大 `timeout`

只调 `timeout` 也能让它装完，但没解决结构性问题：

| | 只调 timeout | 同时关 filter（选此） |
|---|---|---|
| 首次安装能否完成 | 能（等得够久） | 能 |
| checkout 是否还依赖网络 | **是** | 否，纯本地 |
| 网络中途断开的后果 | 工作区半成品 + `.cloning` 残留 | clone 失败即失败，状态干净 |
| 后续 `:Lazy update` | 每次都可能再触发 blob 拉取 | 不会 |

关键在**失败模式**：部分克隆的失败会留下一个「看起来装好了、其实是空的」目录，
外加一个让 lazy 反复重装的隐形标记 —— 这种状态极难自查。
完整克隆失败就是干净地失败，重试即可。

代价是初次下载量变大。在这台机器上这是划算的：一次性多下几十 MB，
换掉一个会反复发作且难以诊断的故障模式。

> `git.filter` 的官方注释说关掉它「is NOT supported and will increase downloads a lot」，
> 那句话针对的是 git < 2.19 的兼容场景。本机 git 版本很新，
> 关掉它只是放弃一个优化，不影响功能。

### 为什么手动 clone 而不是让 lazy 重试

lazy 的每次重试都受 `git.timeout` 约束，而新的 timeout 值要等
`nixos-rebuild switch` 之后才生效 —— 在那之前重试必然还是 120 秒被杀。
命令行 clone 不受这个限制，先把插件装上，配置改动随下次 rebuild 生效。

## 后续注意事项

1. **看到 `Clone succeeded, but checkout failed`，先想到部分克隆。**
   这句话几乎总是意味着「blob 还在网上没下来」，而不是磁盘或权限问题。

2. **插件反复自动重装、手动修目录没用 —— 去找 `.cloning` 标记。**

   ```bash
   ls ~/.local/share/nvim/lazy/*.cloning
   ```

   这个文件不在插件目录**里面**，而在插件根目录下，和插件目录平级，
   所以 `ls 插件目录` 是看不见它的。

3. **手动装插件后，`git status` 必须是干净的。** 有一堆 `D` 说明 checkout 没完成，
   `git reset --hard HEAD` 补上（慢网下这一步可能要几分钟，因为在下 blob）。

4. **判断插件是否真的装好：**

   ```vim
   :lua print(pcall(require, "snacks"))
   :Lazy
   ```

   目录存在不等于装好。

5. **这个坑不限于 snacks.nvim。** 任何大仓库（对象多、blob 大）在慢网下都会中招，
   snacks.nvim 只是因为有 13280 个对象而首先暴露出来。

## 相关文档

- [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md) —— 引入 snacks.nvim 的原因
- [0007_LAZY_NVIM_DASHBOARD.md](0007_LAZY_NVIM_DASHBOARD.md) —— Lazy 面板的读法
- [0006_COPILOT_STARTUP_ISSUES.md](0006_COPILOT_STARTUP_ISSUES.md) —— 另一条 lazy 配置教训：`checker = false`

# nix-ld：让预编译二进制在 NixOS 上跑起来

> 日期：2026-09-17　|　相关配置：`modules/common.nix` 的 `programs.nix-ld.enable = true`
>
> 起因是 VSCode 里的 Claude Code 扩展做 Anthropic Subscription 认证时失败，
> 但这条教训适用于**所有**从 NixOS 之外拿来的预编译程序：
> VSCode 扩展自带的可执行文件、`npm i -g` 装的带原生模块的包、
> 各种官网下载的 AppImage/tarball、语言服务器的预编译发行版。

## 问题症状

在 VSCode 里用 Anthropic Subscription 登录 Claude Code 时，
认证流程走不下去 —— 表现为浏览器链接打不开、认证窗口不出现。

这类症状在 NixOS 上非常有迷惑性，因为**报错往往和真实原因无关**。
预编译二进制起不来时，典型的报错长这样：

```
bash: ./some-binary: cannot execute: required file not found
```

或者更莫名其妙的：

```
No such file or directory
```

—— 文件明明就在那里。**"No such file or directory" 指的不是这个程序本身，
而是它写死在 ELF 头里的动态链接器路径。**

## 根本原因

Linux 可执行文件在 ELF 头的 `INTERP` 段里写死了动态链接器的绝对路径。
绝大多数发行版用的是 FHS 标准位置：

```
/lib64/ld-linux-x86-64.so.2
```

**NixOS 默认没有这个路径。** 所有东西都在 `/nix/store/...` 下，
连 glibc 的链接器也不例外。所以任何在别处编译、指望 FHS 布局的二进制
在 NixOS 上根本无法启动 —— 内核找不到解释器，进程起都起不来。

本机实测，Claude Code 的 VSCode 扩展确实自带一个这样的二进制：

```bash
$ ls -la ~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude
-rwxr-xr-x 1 toru users 228663608 ...        # 228 MB 的预编译 ELF

$ head -c 4096 .../native-binary/claude | grep -ao '/lib64/ld-linux[^\x00]*'
/lib64/ld-linux-x86-64.so.2                   # ← 写死的 FHS 路径
```

作为对照，nixpkgs 里的 `claude-code` 包**已经被 auto-patchelf 改写过**：

```bash
$ head -c 4096 /nix/store/...-claude-code-2.1.223/bin/.claude-wrapped \
    | grep -ao '/nix/store/[^\x00]*ld-linux[^\x00]*'
/nix/store/m07h00fl6538s4gavrp66a20ka4hg7fy-glibc-2.42-67/lib/ld-linux-x86-64.so.2
```

这就是**「从 nixpkgs 装的东西不需要 nix-ld，从外面拿来的才需要」**的原因。

> ⚠️ 关于「认证时打不开外部链接」这个具体症状：
> 二进制起不来是**实测确认**的事实。
> 从「二进制起不来」推导到「浏览器链接打不开」是**推理**：
> 扩展是 spawn 这个 `claude` 二进制去跑 OAuth 流程的，
> 二进制起不来，流程就死在那里，URL 自然永远不会被打开。
>
> 另外值得注意：当时系统的默认浏览器还是 GNOME Web（Epiphany），
> 直到后来才改成 Firefox（见
> [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) 的「修复 3」）。
> 也就是说「打开外部链接」这条路当时**可能是双重损坏**的。

## 解决方法

`modules/common.nix`：

```nix
# 启用 nix-ld (用于运行非 NixOS 应用和二进制文件)
programs.nix-ld.enable = true;
```

它做的事很简单 —— 在 FHS 标准位置放一个 shim：

```bash
$ ls -la /lib64/ld-linux-x86-64.so.2
/lib64/ld-linux-x86-64.so.2 -> /nix/store/...-nix-ld-2.0.6/libexec/nix-ld

$ echo $NIX_LD
/run/current-system/sw/share/nix-ld/lib/ld.so
```

这个 shim 被调用时，会去读 `NIX_LD` 环境变量，找到 Nix 里真正的
glibc 链接器，然后把控制权交过去。等于给写死 FHS 路径的二进制
造了一条转接线。

同时它还准备了一个常用共享库的集合（本机 124 个条目）：

```bash
$ ls /run/current-system/sw/share/nix-ld/lib/ | head
ld.so  libacl.so.1  libatomic.so.1  libblkid.so.1  libbz2.so.1
libcrypto.so.3  libcurl.so.4  libstdc++.so.6  libz.so.1  ...
```

glibc、libstdc++、zlib、openssl 这些最常被依赖的都在里面，
所以大多数程序开了 `enable` 就能跑。

## 如果还缺库

`nix-ld.enable` 只覆盖常用库。二进制起来了但报 `libXXX.so.N: cannot open
shared object file`，说明缺的库不在默认集合里，补进去：

```nix
programs.nix-ld = {
  enable = true;
  libraries = with pkgs; [
    # 举例：需要图形/音频的程序常常要这些
    # alsa-lib
    # libGL
    # xorg.libX11
  ];
};
```

诊断缺哪个库：

```bash
# 看二进制声明了哪些依赖
head -c 200000 <二进制> | grep -ao 'lib[a-z0-9_+-]*\.so\.[0-9]*' | sort -u

# 看运行时到底缺什么
LD_DEBUG=libs <二进制> 2>&1 | grep -i "not found"
```

## 为什么用 nix-ld 而不是别的办法

| 方案 | 适用场景 | 评价 |
|------|----------|------|
| **`programs.nix-ld.enable`**（选此） | 系统范围，让任意外来二进制能跑 | 一行配置，一劳永逸；代价是稍微破坏了 NixOS 的纯粹性 |
| `pkgs.buildFHSEnv` | 单个程序需要完整 FHS 环境 | 隔离干净，但每个程序都要写一份，重 |
| `steam-run <程序>` | 临时跑一次 | 方便但要手动加前缀，不适合被别的程序 spawn 的场景 |
| `patchelf --set-interpreter` | 你能控制那个文件 | 最"正确"，但 VSCode 扩展会自动更新，改完下次就被覆盖 |
| 打包进 nixpkgs | 长期依赖的工具 | 最干净，`claude-code` 走的就是这条 |

**关键取舍：** VSCode 扩展是**自动更新**的，每次更新都会重新解压出一个未经
patchelf 处理的二进制。所以 `patchelf` 这类"修文件"的办法在这个场景下必然失效，
必须用 `nix-ld` 这种"修环境"的办法。

## 后续注意事项

1. **`nix-ld` 不是万能的。** 它只解决"找不到动态链接器"和"常用库缺失"。
   如果程序还要求 FHS 布局里的**别的东西**（比如写死 `/usr/share/...` 的资源路径），
   nix-ld 帮不上，得上 `buildFHSEnv`。

2. **能从 nixpkgs 装就从 nixpkgs 装。** nixpkgs 的包经过 auto-patchelf，
   依赖关系被 Nix 完整追踪，不依赖 nix-ld 这条转接线。
   本仓库的 `claude-code` 就是走的 nixpkgs（见
   `modules/development.nix`），VSCode 扩展那份只是顺带受益。

3. **遇到"文件明明存在却说 No such file or directory"，
   第一反应应该是查 ELF 解释器**，而不是怀疑路径写错了：

   ```bash
   head -c 4096 <二进制> | grep -ao '/lib[^\x00]*ld-linux[^\x00]*'
   ```

   指向 `/lib64/...` 就是需要 nix-ld；指向 `/nix/store/...` 说明已被处理过。

4. **`programs.nix-ld.enable` 放在 `modules/common.nix`**，
   因为这是所有机器都该有的基础能力，不属于某个具体应用的配置。

## 相关文档

- [000D_CLAUDE_CODE_IN_NEOVIM.md](000D_CLAUDE_CODE_IN_NEOVIM.md) —— 在 Neovide 里用 Claude Code
- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— 默认浏览器从 Epiphany 改成 Firefox
- [0005_COPILOT_UNZIP_DEPENDENCY.md](0005_COPILOT_UNZIP_DEPENDENCY.md) —— 另一个"外部工具缺依赖"的例子

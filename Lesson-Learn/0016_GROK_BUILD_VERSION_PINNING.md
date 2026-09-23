# 在 NixOS 上装最新的 Grok Build：版本覆写与关掉自更新

> 日期：2026-09-23　|　相关配置：`modules/development.nix`、`modules/grok-build-version.json`
>
> 触发场景：想在终端里用 xAI 的 coding agent 帮忙配 NixOS。
> nixpkgs 里有 `grok-build`，但版本旧得离谱。

## 问题症状

| 渠道 | 版本 |
|------|------|
| `nixos-26.05`（本机 nixpkgs `1e8bc65`） | **0.2.93** |
| 官方 stable 频道（`https://x.ai/cli/stable`） | **1.0.41** |

隔着整整一个大版本：v1.0 在 2026-08 才正式发布，stable 频道每周一版。
AI agent 这类工具的能力几乎全在新版本里，装 0.2.93 基本等于没装。

顺带分清三个名字很像的东西，别装错：

| 名字 | 是什么 | 适不适合配本机 NixOS |
|------|--------|----------------------|
| `pkgs.grok-build`（命令 `grok`） | xAI 官方的终端 coding agent，和 Claude Code 同类 | ✅ 就是它 |
| `pkgs.grok-cli` | 社区项目 superagent-ai/grok-cli，走 API key 按量计费 | 不是官方的 |
| Grok Bot | xAI 的**云端** agent 平台，bot 跑在 xAI 的云电脑里 | ❌ 碰不到本机文件 |

## 根本原因分析

### 一、和 claude-code 是同一个处境

`nixos-26.05` 是发布分支，不跟上游滚，`nix flake update` 对它是空操作。
这件事在 [0010](0010_CLAUDE_CODE_VERSION_PINNING.md) 已经完整记过，不重复。

### 二、包定义本身只是个下载器

看 nixpkgs 的 `pkgs/by-name/gr/grok-build/package.nix`：

- `src` 是 `fetchurl "https://x.ai/cli/grok-${version}-${platform}"` —— 官方预编译二进制
- `autoPatchelfHook` 修动态链接（所以**不依赖 nix-ld**）
- `installPhase` 装成 `$out/bin/grok`，再链一个 `$out/bin/agent`，顺手生成 shell 补全
- `versionCheckHook` 在构建期跑 `grok --version` 对版本号

版本相关的只有 `version` 和 `src` 两个属性。**换掉这两个就等于换版本**，
其余逻辑照用 nixpkgs 的。

### 三、和 claude-code 不同的地方：没有 manifest

claude-code 上游有现成的 `manifest.json`（带版本号和每个平台的 checksum），
下载下来直接喂给包定义的 `manifest` 参数就行。

grok-build 的包定义**没有**这种参数，版本号和哈希是写死在 `let` 里的。
所以不能用 `.override`，要用 `.overrideAttrs` 直接覆写 `version` 和 `src`，
哈希自己用 `nix-prefetch-url` 算。

### 四、它会自己更新，而且更新到别处

`grok --help` 里有 `update` 子命令；二进制里内嵌的文档写着：

- 启动时会检查更新，自更新装进 `$GROK_HOME/bin/grok`（默认 `~/.grok/bin/grok`，它叫 managed install）
- 关掉的办法有四个：

  | 开关 | 作用范围 |
  |------|----------|
  | `--no-auto-update` | 单次会话 |
  | `GROK_DISABLE_AUTOUPDATER=1` | 进程 |
  | stderr 不是 TTY | 自动 |
  | `~/.grok/config.toml` 里 `[cli] auto_update = false` | 持久 |

不关的话，机器上会出现**两个 grok**：`/run/current-system/sw/bin/grok`（Nix 管）
和 `~/.grok/bin/grok`（它自己管），版本还不一样。哪个生效取决于 PATH 顺序，
而且下一次 `nrb` 什么也纠正不了。这正是 [000A](000A_NIXOS_CONFIG_AUDIT.md)
记过的「装出两份」那一类坑，只不过另一份在 Nix 视野之外。

## 已实施的修复

`modules/development.nix` 的 overlay 里，和 claude-code 并列：

```nix
grok-build = prev.grok-build.overrideAttrs (
  old:
  let
    pin = lib.importJSON ./grok-build-version.json;
    inherit (prev.stdenv.hostPlatform) system;
    platform = { x86_64-linux = "linux-x86_64"; aarch64-linux = "linux-aarch64"; }.${system};
  in
  {
    inherit (pin) version;
    src = prev.fetchurl {
      url = "https://x.ai/cli/grok-${pin.version}-${platform}";
      hash = pin.hashes.${system};
    };
    nativeBuildInputs = old.nativeBuildInputs ++ [ prev.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/grok --set GROK_DISABLE_AUTOUPDATER 1
    '';
  }
);
```

版本号和哈希放在 `modules/grok-build-version.json`：

```json
{
  "version": "1.0.41",
  "hashes": {
    "x86_64-linux": "sha256-nOA+0j4W6gEHK0SWJj1iE6J4meHj4QfwCNNu34LnBAc="
  }
}
```

`grok-build` 加进 `environment.systemPackages`，和 `claude-code` 放在一起。

### 升级办法

```bash
V=$(curl -fsSL https://x.ai/cli/stable)
H=$(nix hash convert --hash-algo sha256 \
  "$(nix-prefetch-url "https://x.ai/cli/grok-$V-linux-x86_64")")
printf '{\n  "version": "%s",\n  "hashes": {\n    "x86_64-linux": "%s"\n  }\n}\n' \
  "$V" "$H" > modules/grok-build-version.json
```

然后走正常的重建流程。只换 JSON，模块定义一个字不用动。

### 验证（2026-09-23 实测）

```bash
$ /tmp/res/sw/bin/grok --version
grok 1.0.41 (4220f3b224a6)

$ grep -o 'GROK_DISABLE_AUTOUPDATER[^ ]*' "$(readlink -f /tmp/res/sw/bin/grok)"
GROK_DISABLE_AUTOUPDATER='1'

$ nix path-info -r /tmp/res /tmp/hm | grep grok-build | sort -u
/nix/store/r0k1h6g7l9waclrzicbd8mja4yqgfh97-grok-build-1.0.41
```

闭包里只有一个 grok-build 派生，zsh 补全 `_grok` 也生成了。

## 为什么这样解决

**为什么不加 nixpkgs-unstable input：** 理由同 0010 —— 为一个包多拉一整个 nixpkgs 不值得。
而且 unstable 也未必跟得上每周一版的 stable 频道。

**为什么不用官方的 `curl … | bash` 安装脚本：** 装进 `~/.grok/bin/`，Nix 管不到，
新机器上不会自动出现；预编译二进制的 ELF 解释器还写死了 `/lib64/...`，
得靠 nix-ld 转接（[000C](000C_NIX_LD_PREBUILT_BINARIES.md)）。
走 nixpkgs 的包定义有 `autoPatchelfHook`，这两个问题都没有。

**为什么用 `wrapProgram` 而不是 `environment.sessionVariables`：**
环境变量走 PAM / shell 初始化，从 Neovide、systemd 服务、别的 agent 里启动时
不一定继承得到。钉在二进制上的包装脚本从哪里启动都生效，
而且这个开关跟着包走，不会散落到 `shell.nix` 里。

**为什么不写进 `~/.grok/config.toml`：** grok 会在运行时自己写这个文件 ——
首次启动后里面就多了 `[privacy] privacy_banner_acked`、`[marketplace]` 的几个标记
（2026-09-23 实测）。声明成只读符号链接会让这些写入失败 —— CLAUDE.md 里
「不要为了声明式的纯度关掉工具的功能」那一条。

**为什么放 `modules/` 不放 `hosts/`：** 换台机器照样成立。

## 后续注意事项

1. **不要手动敲 `grok update`。** 包装脚本挡住的只是**启动时的自动检查**；
   显式的 `grok update` 照样会往 `~/.grok/bin/` 装一份。
   万一装了：`rm -rf ~/.grok/bin/grok`，再 `which -a grok` 确认只剩 Nix 那个。
2. **加 ARM 机器**时要在 JSON 里补 `aarch64-linux` 的哈希（文件名后缀 `linux-aarch64`），
   否则求值报缺键。overlay 里的 `platform` 表已经留好了。
3. **`~/.grok/` 的 A / B / C 划分还没做。** 装的时候还没登录用过，
   目录里会有什么没实测。登录用过几天后跑 `migration-check`，
   逐项分类后更新 `home/migration.nix` 和 MIGRATION.md 附表里的那一行。
4. **它会读本仓库的 `CLAUDE.md`，但要先信任这个目录**（2026-09-23 实测）。
   第一次 `grok inspect` 显示 `Project trusted: no`、`Project Instructions (0)`；
   在仓库里交互式启动一次 `grok`、按提示信任之后，变成
   `/home/toru/nixos-config/CLAUDE.md (project, ~6999 tokens)`。
   **没信任时它对这里的约定一无所知**，所以新机器上第一次用它改仓库之前，
   先跑 `grok inspect` 确认这一行在。

   信任之后它还会顺带读 Claude Code 的东西，都是 `inspect` 里
   「Harness Compatibility → claude」那几项默认开着的结果：

   - **权限**：`.claude/settings.local.json` 的 allow 列表被原样加载
     （`7 loaded`）。以后在 Claude Code 里放宽权限，Grok 也跟着放宽。
   - **skill**：除了 `skills` 装的 25 个，还会捡到
     `~/.claude/skills/synced/` 里 claude.ai 同步下来的 3 个
     （`docs` / `import-memory` / `morning`），它们依赖 claude.ai 的连接器，
     在 Grok 里用不了，`docs` 还和它自带的 `/docs` 撞名。
     装新工具后数 skill 的时候，这 3 个别算错。

   `inspect` 里的 `[privacy] — unrecognized config key` 警告是 grok
   **自己写进 config.toml 又自己不认**，与本仓库无关，不用管。
5. **nixpkgs 以后追上了**（26.11 或 backport），可以删掉这个 overlay 回到原包。
   判据：`nix eval --raw nixpkgs#grok-build.version` 不低于 JSON 里的版本。

## 相关文档

- [0010_CLAUDE_CODE_VERSION_PINNING](0010_CLAUDE_CODE_VERSION_PINNING.md) —— 同一处境的第一次，发布分支为什么不滚
- [000C_NIX_LD_PREBUILT_BINARIES](000C_NIX_LD_PREBUILT_BINARIES.md) —— 预编译二进制为什么在 NixOS 上起不来
- [000A_NIXOS_CONFIG_AUDIT](000A_NIXOS_CONFIG_AUDIT.md) —— 「装出两份」
- [MIGRATION.md](../MIGRATION.md) 第 0 节 C 类表、第 7.3 节 —— `grok login`

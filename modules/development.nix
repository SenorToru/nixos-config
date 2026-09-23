{
  lib,
  pkgs,
  ...
}:

{
  # ============================================
  # claude-code 版本覆写
  # ============================================
  # nixos-26.05 分支上的 claude-code 停在 2.1.223，`nix flake update` 对它
  # **完全无效** —— 26.05 是发布分支，不会跟着上游滚。而 Session 管理的好些
  # 功能有版本门槛（/rename 与会话选择器的 Ctrl+R、agent view 的键位、
  # chat:queueSubmit、diff panel 分别要 2.1.221 / 2.1.257 / 2.1.247 / 2.1.260），
  # 2.1.223 全都够不着。
  #
  # 两条升级路线里选了这条：
  #
  #   (a) 加一个 nixpkgs-unstable input，只为取它的 claude-code。
  #       能拿到 2.1.272，走 cache.nixos.org 的二进制缓存。
  #       代价是仓库里多一整个 nixpkgs —— 多一份 tarball、多一份求值开销，
  #       为一个包不值得。
  #
  #   (b) 就用 26.05 的包定义，只把 manifest 换成新版。  <-- 采用
  #       claude-code 这个包本身只做一件事：按 manifest 里的 version 和
  #       checksum 去 downloads.claude.ai 下载官方预编译二进制，再
  #       autoPatchelf 一遍。所以换掉 manifest 就等于换版本，
  #       包定义本身不用动。
  #
  # manifest 的刷新办法（上游有 latest 端点）：
  #
  #   V=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)
  #   curl -fsSL "https://downloads.claude.ai/claude-code-releases/$V/manifest.json" \
  #     -o modules/claude-code-manifest.json
  #
  # 注意**不要**去取同目录下的 manifest.zst.json。那是 nixos-unstable 上
  # 新包定义用的格式（二进制经 zstd 压缩，构建时需要 zstd 解压），
  # 26.05 的包定义只认不带 .zst 的那份。
  #
  # 用 overlay 而不是在两处各写一次：claude-code 同时出现在下面的
  # systemPackages 和 home/toru.nix 的 programs.neovim.extraPackages 里
  # （后者是必需的，插件从 nvim 内部 spawn claude，走的是 wrapper PATH）。
  # 覆写 pkgs.claude-code 可以让两处同时生效，不会漏掉一边而装出两个版本 ——
  # 那正是 000A 记过的坑。
  #
  # ============================================
  # grok-build 版本覆写
  # ============================================
  # 同一个处境、同一个解法：26.05 上的 grok-build 停在 0.2.93，
  # 而上游已经 1.0.x（v1.0 在 2026-08 正式发布，stable 频道每周一版）。
  # nixpkgs 的包定义同样只是按版本号去 x.ai 下预编译二进制再
  # autoPatchelf，所以只换「版本号 + 哈希」，包定义照用。
  #
  # 和 claude-code 的区别：上游没有现成的 manifest 可拉，
  # 版本号和哈希得自己算，存在 grok-build-version.json 里。刷新办法：
  #
  #   V=$(curl -fsSL https://x.ai/cli/stable)
  #   H=$(nix hash convert --hash-algo sha256 \
  #     "$(nix-prefetch-url "https://x.ai/cli/grok-$V-linux-x86_64")")
  #   printf '{\n  "version": "%s",\n  "hashes": {\n    "x86_64-linux": "%s"\n  }\n}\n' \
  #     "$V" "$H" > modules/grok-build-version.json
  #
  # 目前只有 x86_64-linux 一个哈希。加 ARM 机器时补一个
  # aarch64-linux（文件名后缀是 linux-aarch64），否则求值时直接报缺键。
  #
  # **自更新必须关掉。** grok 启动时会检查更新，并把新版装进
  # ~/.grok/bin/grok（它所谓的 managed install）—— 于是机器上出现
  # 两个 grok，一个 Nix 管、一个它自己管，版本还不一样。
  # 官方给的开关里 GROK_DISABLE_AUTOUPDATER=1 是进程级的，
  # 用 wrapProgram 钉在二进制上，从哪里启动（终端、Neovide、脚本）都生效，
  # 不依赖 shell 环境。手动敲 `grok update` 仍然会装，别敲。
  nixpkgs.overlays = [
    (_final: prev: {
      claude-code = prev.claude-code.override {
        manifest = lib.importJSON ./claude-code-manifest.json;
      };

      grok-build = prev.grok-build.overrideAttrs (
        old:
        let
          pin = lib.importJSON ./grok-build-version.json;
          inherit (prev.stdenv.hostPlatform) system;
          platform =
            {
              x86_64-linux = "linux-x86_64";
              aarch64-linux = "linux-aarch64";
            }
            .${system};
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
    })
  ];

  environment.systemPackages = with pkgs; [
    nil
    nixfmt
    nodejs_24
    # GitHub CLI 用于 Copilot 认证
    # 如果希望仅使用 VSCode 认证而不使用 GitHub CLI，可注释掉此行
    github-cli

    # Claude Code CLI（unfree，已由 common.nix 的 allowUnfree 放行）
    # nixpkgs 版本经过 auto-patchelf 处理，不依赖 nix-ld
    claude-code

    # Grok Build（xAI 的终端 coding agent，unfree）。命令名是 grok，
    # 另有一个同指向的 agent 链接。版本覆写见上面的 overlay
    grok-build
  ];

  # ============================================
  # 注意：这里故意**不**声明 programs.neovim
  # ============================================
  # neovim 只在 home/toru.nix (home-manager) 中定义一次。
  #
  # 曾经这里也有一份 programs.neovim.enable = true，结果产生了两个不同的
  # neovim 派生：
  #   nvim    -> home-manager 版（extraPackages 带 node / unzip / nil / nixfmt）
  #   vim, vi -> 这里的系统版（不带任何 extraPackages）
  # 于是用 `vim` 打开文件时，Copilot 的 language server 找不到 node 和
  # unzip，表现为 "Status: Offline" / "copilot is not running"，而用 `nvim`
  # 打开却一切正常——极难排查。
  #
  # viAlias / vimAlias / defaultEditor 现已统一在 home/toru.nix 里设置。
  #
  # **neovide 和 vscode 同理，也已经从上面的 systemPackages 移走。**
  #
  #   neovide  现由 home/toru.nix 的 programs.neovide 声明。
  #   vscode   现由 home/toru.nix 的 programs.vscode 声明 —— 那是
  #            stylix 的 vscode target 写主题扩展和 userSettings 的前提，
  #            裸包它管不到。
  #
  # 两边各装一份的话，Nix 不报冲突但会得到两个派生，
  # 而只有 home-manager 那份能读到 stylix 生成的配置。
  #
  # 判断规则：**凡是要被 stylix（或任何 home-manager 模块）接管配置的
  # 程序，都必须由 home 层声明，不能留在这里当裸包。**
}

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
  nixpkgs.overlays = [
    (_final: prev: {
      claude-code = prev.claude-code.override {
        manifest = lib.importJSON ./claude-code-manifest.json;
      };
    })
  ];

  environment.systemPackages = with pkgs; [
    vscode
    nil
    nixfmt
    neovide
    nodejs_24
    # GitHub CLI 用于 Copilot 认证
    # 如果希望仅使用 VSCode 认证而不使用 GitHub CLI，可注释掉此行
    github-cli

    # Claude Code CLI（unfree，已由 common.nix 的 allowUnfree 放行）
    # nixpkgs 版本经过 auto-patchelf 处理，不依赖 nix-ld
    claude-code
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
}

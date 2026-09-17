{
  pkgs,
  ...
}:

{
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

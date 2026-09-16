{
  config,
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
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}

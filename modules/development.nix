{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
      nil
      nixfmt
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    configure = {
      # Set NeoVim indent rules.
      customRC = ''
        lua << EOF
        vim.opt.tabstop = 2
        vim.opt.softtabstop = 2
        vim.opt.shiftwidth = 2
        vim.opt.expandtab = true
        vim.opt.autoindent = true
        vim.opt.smartindent = true
        EOF
        '';
    };
  };
}

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
      nil
      nixfmt
      neovide
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      customRC = ''
        " 通用缩进设置（命令行与 GUI 均生效）
        set tabstop=2
        set softtabstop=2
        set shiftwidth=2
        set expandtab
        set autoindent
        set smartindent

        " 专属于 Neovide GUI 的特定渲染配置（终端不会读取）
        if exists('g:neovide')
          " 设置字体（请确保系统已安装相应字体）
            " set guifont=JetBrainsMono\ Nerd\ Font:h12

            " 启用流畅平滑光标动画
            let g:neovide_cursor_animation_length = 0.13
            let g:neovide_cursor_trail_size = 0.8
            endif
            '';
    };
  };
}

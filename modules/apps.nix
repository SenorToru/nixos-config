{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # 常用网络与知识管理
    brave
    obsidian

    # 办公与生产力
    libreoffice-fresh

    # 图形与设计
    gimp
    inkscape

    # 实用工具
    peazip
  ];
}

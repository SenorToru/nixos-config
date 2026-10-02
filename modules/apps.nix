{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # 常用网络与知识管理
    obsidian

    # 办公与生产力
    libreoffice-fresh

    # 图形与设计
    gimp
    inkscape
    # DWG 手工转换：dwg2dxf 转 DXF，dwg2SVG（注意大写 SVG）转 SVG，
    # 转好之后用 Inkscape 打开。用法见提交注释或 dwg2dxf --help。
    libredwg

    # 实用工具
    peazip

    # 通讯
    telegram-desktop
  ];
}

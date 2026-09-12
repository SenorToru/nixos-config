{ config, pkgs, ... }:

{
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # 自动添加Flathub源
  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  # 自动安装
  services.flatpak.packages = [
    "com.github.tchx84.Flatseal"
    "com.tencent.WeChat"
    "eu.betterbird.Betterbird"
    "com.baidu.NetDisk"
  ];
}

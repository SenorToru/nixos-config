{ config, pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # 蓝牙与音频
  hardware.bluetooth.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # 打印支持
  services.printing.enable = true;

  # 浏览器
  programs.firefox.enable = true;

  # 桌面应用与扩展管理
  environment.systemPackages = with pkgs; [
    gnome-extension-manager
    # 覆盖并隐藏 GNOME 原生拼图 Extensions 图标
    (makeDesktopItem {
      name = "org.gnome.Extensions";
      desktopName = "Extensions";
      noDisplay = true;
    })
  ];
}

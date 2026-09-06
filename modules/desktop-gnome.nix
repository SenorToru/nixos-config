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
    # 覆盖并隐藏 GNOME 原生拼图 Extensions 图标
    (makeDesktopItem {
      name = "org.gnome.Extensions";
      desktopName = "Extensions";
      noDisplay = true;
    })
    gnome-extension-manager
    gnomeExtensions.applications-menu # Add a category-based menu for apps.
    gnomeExtensions.dash-to-panel # An icon taskbar for Gnome.
    gnomeExtensions.burn-my-windows # Window Open/Close effect.
    gnomeExtensions.gtile # Super + Return to quickly setting Windows on grid.
    gnomeExtensions.draw-on-gnome # Free drawing tool on screen.
    gnomeExtensions.vitals-widget # System status monitor on desktop
    gnomeExtensions.kimpanel # Input Method Panel using KDE's kimpanel protocol for Gnome-Shell
  ];
}

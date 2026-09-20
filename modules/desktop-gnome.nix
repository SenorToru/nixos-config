{ pkgs, ... }:

{
  # 只开 dconf 本身，**不在系统层声明任何具体设置**。
  #
  # 原来这里有一份 profiles.user.databases 设 button-layout。已挪到
  # home/toru.nix 的 dconf.settings，理由是按仓库判据它属于用户偏好
  # （按钮放左放右跟着人走，不跟着机器走），而且分散在两层的话
  # 「这一条到底在哪声明的」会变成每次都要查一遍的问题。
  #
  # 现在 dconf 的单一真相是 home/toru.nix。
  programs.dconf.enable = true;

  environment.systemPackages = with pkgs; [
    (makeDesktopItem {
      name = "org.gnome.Extensions";
      desktopName = "Extensions";
      noDisplay = true;
    })
    gnome-extension-manager
    gnomeExtensions.applications-menu
    gnomeExtensions.dash-to-panel
    gnomeExtensions.burn-my-windows
    gnomeExtensions.gtile
    gnomeExtensions.draw-on-gnome
    gnomeExtensions.vitals-widget
    gnomeExtensions.kimpanel
    gnomeExtensions.color-picker
  ];
}

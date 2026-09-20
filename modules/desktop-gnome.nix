{ pkgs, ... }:

{
  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings = {
          "org/gnome/desktop/wm/preferences" = {
            button-layout = "close,minimize,maximize:";
          };
        };
      }
    ];
  };

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

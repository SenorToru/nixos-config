{
  config,
  pkgs,
  inputs,
  ...
}:

let
  # 统一的浏览器策略基础规则
  baseExtensionPolicies = {
    ExtensionUpdate = true;
    ExtensionSettings = {
      "*" = {
        installation_mode = "allowed";
      };
      # uBlock Origin
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "force_installed";
      };
      # Proton Pass
      "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4885390/latest.xpi";
        installation_mode = "force_installed";
      };
      # Dark Reader
      "addon@darkreader.org" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        installation_mode = "force_installed";
      };
      # SponsorBlock
      "sponsorBlocker@ajay.app" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
        installation_mode = "force_installed";
      };
      # Easy Youtube Video Downloader Express
      "{b9acf540-acba-11e1-8ccb-001fd0e08bd4}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4997872/latest.xpi";
        installation_mode = "force_installed";
      };
    };
  };
in
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

  # 原生 Firefox 配置（自动生成 /etc/firefox/policies/policies.json）
  programs.firefox = {
    enable = true;
    policies = baseExtensionPolicies;
  };

  # 声明式为原生 Zen 提供相同的宿主策略文件
  # 原生 Zen 启动时直接读取 /etc/zen/policies/policies.json
  environment.etc."zen/policies/policies.json".text = builtins.toJSON {
    policies = baseExtensionPolicies;
  };

  # 桌面应用与扩展管理
  environment.systemPackages = with pkgs; [
    # 原生 Zen 浏览器（基于 flake input 安装）
    inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default

    # 覆盖并隐藏 GNOME 原生拼图 Extensions 图标
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
  ];
}

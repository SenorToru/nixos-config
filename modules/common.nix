{ config, pkgs, ... }:

{
  # 启用 Flakes 和命令行新特性
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # 存储优化与自动垃圾回收
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  # 允许非自由软件 (VS Code 必需)
  nixpkgs.config.allowUnfree = true;

  # 时区与基础英文环境
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  # 基础网络与常用 CLI 工具
  networking.networkmanager.enable = true;
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    pciutils
    usbutils
    jq
    ripgrep
    fd
    tree
  ];

  # 字体配置 (支持中日韩文字)
  fonts = {
    packages = with pkgs; [
      sarasa-gothic
      noto-fonts
      noto-fonts-cjk-serif
    ];

    fontconfig.enable = true;
    fontconfig.defaultFonts = {
      monospace = [
        "Sarasa Mono"
        "Noto Sans Mono CJK"
      ];
      sansSerif = [
        "Sarasa Gothic"
        "Noto Sans CJK"
      ];
      serif = [
        "Noto Serif CJK"
      ];
    };
  };
}

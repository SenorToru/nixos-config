{ pkgs, ... }:

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

  # 启用 nix-ld (用于运行非 NixOS 应用和二进制文件)
  programs.nix-ld.enable = true;

  # 固件更新（LVFS）。任何带 UEFI 的机器都该开，不绑具体硬件，
  # 所以放在 common 而不是 hosts/*/tuning.nix。
  # 用法：`fwupdmgr refresh && fwupdmgr get-updates`。
  services.fwupd.enable = true;

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

  # 字体与 fontconfig 统一在 modules/localization.nix 中配置。
  # 这里曾经也有一份 fonts.packages + fontconfig.defaultFonts，与
  # localization.nix 重复声明了 noto-fonts / noto-fonts-cjk-serif /
  # sarasa-gothic，且 defaultFonts 引用的字体只装在 localization.nix 里。
}

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop-gnome.nix
    ../../modules/localization.nix
    ../../modules/development.nix
  ];

  # ThinkPad 主机名
  networking.hostName = "thinkpad-nixos";

  # UEFI 引导配置
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ThinkPad 本地物理键盘 (JIS 106)
  console.keyMap = "jp106";
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };

  # 用户账户定义
  users.users."toru" = {
    isNormalUser = true;
    description = "Toru Sugihara";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  system.stateVersion = "26.05";
}

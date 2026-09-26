{ pkgs, inputs, ... }:

{
  imports = [
    # 本机专属
    ./hardware-configuration.nix
    ./tuning.nix
    ./hwinfo.nix

    # 共用模块
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/desktop-gnome.nix
    ../../modules/localization.nix
    ../../modules/development.nix
    ../../modules/flatpak.nix
    ../../modules/apps.nix
    ../../modules/browsers.nix
    ../../modules/shell.nix
    ../../modules/dns.nix
    ../../modules/syncthing.nix
    ../../modules/stylix.nix
    ../../modules/refind.nix

    inputs.home-manager.nixosModules.home-manager
    inputs.stylix.nixosModules.stylix
  ];

  networking.hostName = "nixos-vm";

  # 仓库里的名字：hosts/vm/ 目录名 + flake 属性名
  custom.flakeHost = "vm";

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 必须保持 false。改回 true 的话 systemd-boot 每次 switch 都会抢 NVRAM
  # 第一位，rEFInd 就白装了 —— modules/refind.nix 里有 assertion 守着，
  # 但别去绕过它。
  #
  # 装机过程中它曾经是 true，目的是让 systemd-boot 先建好自己的 NVRAM 项
  # （那是开不了机时的退路）；装 rEFInd 之前改成 false。这里记的是最终状态。
  boot.loader.efi.canTouchEfiVariables = false;

  custom.refind = {
    enable = true;
    resolution = {
      width = 1920;
      height = 1080;
    };

    espMountPoints = [
      "/boot"
      "/mnt/winesp"
    ];

    # icon 的路径基准是 **ESP 卷根**，和同一个文件里 banner / icons_dir
    # 的基准（rEFInd 目录）不一样。写错不报错，只显示一个约 32x32 的
    # 内置占位方块，而同目录下的功能图标一切正常 —— 见 Lesson-Learn/0013 的坑 4。
    #
    # 这里只能手写全路径：refindDir / themeDir 是 modules/refind.nix 里的
    # let 绑定，**没有暴露成选项**，host 文件取不到。
    # 所以：**改了模块里那两个变量，这一行必须跟着改**，
    # 否则这个图标会静默退化成占位方块。
    extraEntries = ''
      menuentry "Windows 10" {
      icon /EFI/refind/themes/finn-term/icons/os_win.png
      volume WINESP
      loader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };

  console.keyMap = "us";
  services.xserver.xkb.layout = "us";

  users.users."toru" = {
    isNormalUser = true;
    description = "Toru Sugihara";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };
  home-manager.users.toru = import ../../home/toru.nix;
  home-manager.backupFileExtension = "hm-bak";

  # 虚拟机专属：开 SSH，从宿主机连进来操作，
  # 不用对着 virt-manager 窗口手打。
  services.openssh.enable = true;

  system.stateVersion = "26.05";
}

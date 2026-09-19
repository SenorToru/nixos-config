{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    # 本机专属（跟着这台硬件走）
    ./hardware-configuration.nix
    ./tuning.nix

    # 共用模块（任何机器都能直接 import）
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/desktop-gnome.nix
    ../../modules/localization.nix
    ../../modules/development.nix
    ../../modules/flatpak.nix
    ../../modules/apps.nix
    ../../modules/browsers.nix
    ../../modules/shell.nix
    ../../modules/stylix.nix

    inputs.home-manager.nixosModules.home-manager

    # Stylix 的 NixOS 模块。它会通过 stylix.homeManagerIntegration.autoImport
    # （默认开）自动把配色传给 home-manager.users.* 那一份，
    # 所以 home/toru.nix 里**不需要**再单独 import 一次。
    # 必须排在 home-manager 模块之后。
    inputs.stylix.nixosModules.stylix
  ];

  # ThinkPad 主机名
  networking.hostName = "thinkpad-nixos";

  # UEFI 引导配置
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 引导菜单最多保留 20 个条目。
  #
  # 默认是 null（不限制）。本机 rebuild 很频繁，generation 攒得快：
  # 写这条时有 36 个。菜单太长不好选，而且每换一次内核，/boot 就要多存
  # 一份约 50-60 MiB 的 kernel + initrd，1 GiB 的 ESP 撑不住几轮。
  #
  # 注意这**只限制引导菜单条目**，不删 store 里的东西。
  # 控制磁盘占用是 modules/common.nix 里 nix.gc 的事，两者互不替代。
  #
  # 副作用：下次 switch 时，超出 20 个的旧条目会从引导菜单里移除。
  # 那些 generation 本身还在（GC 才管删），
  # `nixos-rebuild switch --rollback` 仍然可用，
  # 只是没法再从开机菜单里直接选中它们了。
  boot.loader.systemd-boot.configurationLimit = 20;
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
    # 登录 shell。zsh 本体由 modules/shell.nix 在系统层 enable（那是通用的），
    # 这里只做「哪个用户用它」的指派 —— 用户名是本机的事，不该写进共用模块。
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

  # 当 home-manager 要接管一个已存在的普通文件时，默认行为是**整个激活失败**
  # （"Existing file ... would be clobbered"），系统层已经切过去了，home 层却没生效，
  # 属于很难受的半成功状态。
  # 设了这个之后，HM 会把挡路的文件改名成 <原名>.hm-bak 再继续，不再中断激活。
  #
  # 触发过一次：xdg.mimeApps 同时管理 ~/.config/mimeapps.list 和已废弃的
  # ~/.local/share/applications/mimeapps.list，而后者已存在一个 0 字节空文件。
  home-manager.backupFileExtension = "hm-bak";

  system.stateVersion = "26.05";
}

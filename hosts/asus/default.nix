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
    # 由 refind-hwinfo 生成，供 rEFInd 启动画面用。换了硬件重跑一次那个命令。
    ./hwinfo.nix

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
    ../../modules/dns.nix
    ../../modules/syncthing.nix
    ../../modules/stylix.nix
    ../../modules/refind.nix
    # 只有这台机器要装的可选模块
    ../../modules/steam.nix

    inputs.home-manager.nixosModules.home-manager
    # 必须排在 home-manager 模块之后，原因见 hosts/thinkpad/default.nix。
    inputs.stylix.nixosModules.stylix
  ];

  # ASUS TX Air (FA401KM)。前身是跑 Bluefin 的那台，重装成 Windows + NixOS 双系统。
  networking.hostName = "asus";

  # 仓库里的名字：hosts/asus/ 目录名 + flake 属性名。
  # home/desktop-prefs.nix 靠它判断哪些偏好只在这台生效。
  custom.flakeHost = "asus";

  # 这台机器的默认主题。重装之后回到它；日常用 `theme` 命令切换，
  # 选择记在 ~/.local/state/theme/current（重建、重启都保留）。
  # 不和别的机器同步，每台各写各的。选项定义在 modules/common.nix。
  custom.defaultTheme = "kanagawa";

  # 引导：两层结构，和 thinkpad 一致。
  # rEFInd 做顶层入口，systemd-boot 管 generation 和回滚。
  boot.loader.systemd-boot.enable = true;

  # 必须是 false，理由和 thinkpad 相同：否则 systemd-boot 每次 switch
  # 都抢 NVRAM 第一位。modules/refind.nix 里有 assertion 守着。
  boot.loader.efi.canTouchEfiVariables = false;

  # 两个 ESP（NixOS 盘 2 GiB、Windows 盘 1 GiB）都比 thinkpad 的宽裕，
  # 但 kernel + initrd 每换一次内核就多存一份，菜单条目照样限一下。
  boot.loader.systemd-boot.configurationLimit = 20;

  # 内核**明确钉在 6.18 LTS**，不跟 linuxPackages_latest，
  # 也不用不带版本号的 linuxPackages（那个是「nixpkgs 当前的默认内核」，
  # nixpkgs 一换默认，内核就跟着跨大版本）。
  #
  # 原因是 NVIDIA 开源内核模块：thinkpad 用的 linuxPackages_latest（7.2.6）
  # 上，nixpkgs 里的驱动 595.71.05 编译不过
  # （nvidia/os-interface.c: implicit declaration of function 'strncpy'，
  # 是驱动和新内核头文件不兼容），整个系统构建失败。
  # 这台机器有独显，要以驱动能编译为先。
  #
  # 6.18 对 Ryzen AI 350（Krackan Point）和 RTL8852CE 都够新。
  #
  # **6.18 到期退役时会怎样：** nixpkgs 会删掉 linuxPackages_6_18 这个属性，
  # 构建直接报 "linux 6.18 was removed because it has reached its end of life"。
  # 这是**故意想要的响亮失败**：构建发生在 switch 之前，当前系统不受影响。
  # 该怎么办见 ASUS_INSTALL.md 附录 D。
  #
  # 想换回 latest 或换别的版本：先确认 nvidiaPackages.stable 能在那个内核上编译
  # （`nix build .#nixosConfigurations.asus.config.system.build.toplevel`
  # 就会暴露），别只看 nixpkgs 有没有更新的驱动版本。
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  # ============================================
  # rEFInd 顶层引导入口
  # ============================================
  custom.refind = {
    enable = true;

    # 占位值，**必须在真机上校一遍**。
    #
    # 不能靠猜 —— thinkpad 那台第一次填 1080p，rEFInd 直接报固件不提供。
    # 装好后把这里临时设成 1x1，rEFInd 启动时会列出固件 GOP 的全部模式，
    # 挑面板原生那个（通常是 Mode 0）填回来，再 nrb + sudo refind-sync。
    # 流程见 MIGRATION.md 第 6.4 节。
    resolution = {
      width = 2560;
      height = 1600;
    };

    # 双盘双启动：两个 ESP 各装一份 rEFInd，refind-sync 一条命令写两个。
    # NVRAM 项只为第一个（NixOS 盘的 /boot）建。见 MIGRATION.md 第 6.5 节。
    # /mnt/winesp 的挂载声明在 tuning.nix。
    espMountPoints = [
      "/boot"
      "/mnt/winesp"
    ];

    # Windows 在另一块盘（Samsung）上，volume 不能省 ——
    # 否则 rEFInd 只会在自己所在的 ESP 里找 bootmgfw.efi。
    # volume 写的是 Windows ESP 的分区标签，装 Windows 时 diskpart 里
    # 设成了 SYSTEM，两边要一致。
    # icon 必须是从 ESP 卷根算起的绝对路径。
    extraEntries = ''
      menuentry "Windows 11" {
          icon   /EFI/refind/themes/finn-term/icons/os_win.png
          volume SYSTEM
          loader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };

  # 键盘布局。Bluefin 上的输入源只有 xkb us，先按 US 写。
  # 装好后如果这台的物理键盘其实是 JIS，改成 jp106 / jp。
  console.keyMap = "us";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # 用户账户定义
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

  # 挡路的已存在文件改名成 <原名>.hm-bak，不中断激活。原因见 thinkpad。
  home-manager.backupFileExtension = "hm-bak";

  system.stateVersion = "26.05";
}

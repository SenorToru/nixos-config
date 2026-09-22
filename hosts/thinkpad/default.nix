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
    ../../modules/stylix.nix
    ../../modules/refind.nix

    inputs.home-manager.nixosModules.home-manager

    # Stylix 的 NixOS 模块。它会通过 stylix.homeManagerIntegration.autoImport
    # （默认开）自动把配色传给 home-manager.users.* 那一份，
    # 所以 home/toru.nix 里**不需要**再单独 import 一次。
    # 必须排在 home-manager 模块之后。
    inputs.stylix.nixosModules.stylix
  ];

  # ThinkPad 主机名
  networking.hostName = "thinkpad-nixos";

  # 这台机器在仓库里的名字：hosts/thinkpad/ 目录名 + flake 属性名。
  # **和上面的 hostName 不一样**，别把两者混用 —— shell 别名、
  # refind-hwinfo 的输出路径都靠它。选项定义在 modules/common.nix。
  custom.flakeHost = "thinkpad";

  # UEFI 引导配置
  #
  # 两层结构：rEFInd 做顶层入口（好看 + 将来多系统选单），
  # systemd-boot 继续管 generation —— 回滚安全网在那一层，不能丢。
  # rEFInd 的配置在下面 custom.refind，模块在 modules/refind.nix。
  boot.loader.systemd-boot.enable = true;

  # 必须是 false。
  #
  # 保持 true 的话，systemd-boot 每次 switch 都会把自己设回 UEFI 启动顺序
  # 第一位，rEFInd 永远轮不到 —— 正好抵消装它的意义。
  # modules/refind.nix 里有一条 assertion 守着这个。
  #
  # **改成 false 不会删掉已存在的 "Linux Boot Manager" NVRAM 项**，
  # 只是不再更新它。那一项因此成了安全网：rEFInd 出任何问题，
  # 开机敲 F12 选它就能正常进系统，不需要 U 盘救援。
  boot.loader.efi.canTouchEfiVariables = false;

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

  # ============================================
  # rEFInd 顶层引导入口
  # ============================================
  # 分辨率和仓库里的名字是**这台机器的事**，所以填在这里，
  # 模块本身不带任何本机假设。加新机器时各填各的。
  #
  # 启动画面上那几行硬件**不在这里** —— 由 refind-hwinfo 探测后写进
  # ./hwinfo.nix（上面 imports 里），换了硬件重跑一次那个命令即可。
  # 内核那一行也不在，它由模块从 config.boot.kernelPackages 直接取。
  custom.refind = {
    enable = true;

    # 2560x1440 = 面板原生，**已实机确认是固件 GOP 的 Mode 0**。
    #
    # 这个值不能靠猜。第一次装的时候填的是 1920x1080（想当然地以为
    # 「1080p 哪个固件都支持」），结果 rEFInd 启动时直接报该模式不存在 ——
    # 这台 ThinkPad 的 GOP 压根不提供 1080p。它实际给的是：
    #     Mode 0: 2560x1440   面板原生，正解
    #     Mode 5: 1600x1200   4:3，会有黑边
    #     Mode 6: 1920x1440   4:3，比例和面板对不上，画面变形
    #
    # 教训：**每台新机器都必须先装上去看固件报什么，再回来填。**
    # 流程见 MIGRATION.md 第 6.4 节。
    resolution = {
      width = 2560;
      height = 1440;
    };

  };

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

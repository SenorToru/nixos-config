{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ============================================
  # 这台机器在仓库里的名字
  # ============================================
  # `hosts/<这个名字>/` 的目录名，同时也是 flake.nix 里
  # nixosConfigurations 的属性名。
  #
  # **它不一定等于 networking.hostName。** 本机就是例子：
  # 目录叫 hosts/thinkpad/、flake 属性叫 thinkpad，
  # 而 networking.hostName 是 thinkpad-nixos。
  #
  # 凡是要拼 `hosts/<名字>/` 或 `--flake .#<名字>` 的地方都用它，
  # 不要用 $(hostname) 或 networking.hostName —— 那是**运行时的主机名**，
  # 和**仓库里的标识**是两件事。踩过一次，见 Lesson-Learn/0013 坑 5。
  #
  # 放 common.nix 而不是某个具体模块：home/ 的别名和 modules/refind.nix
  # 都要用，是仓库级的通用事实。
  options.custom.flakeHost = lib.mkOption {
    type = lib.types.str;
    default = config.networking.hostName;
    defaultText = lib.literalExpression "config.networking.hostName";
    description = "这台机器在仓库里的名字（hosts/ 目录名 + flake 属性名）。";
  };

  config = {
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

    # ============================================
    # sudo 输入密码时回显星号
    # ============================================
    # 默认行为是**完全无回显** —— 敲键盘屏幕上一点反应都没有，
    # 分不清是没输进去、键盘没连上，还是已经输了几位。
    # pwfeedback 让每输入一个字符就打一个 `*`。
    #
    # 这是 sudo 自己的 Defaults 标志，只能写进 sudoers，
    # 所以用 extraConfig 而不是 defaultOptions —— 后者是给默认规则加
    # 命令标签的（渲染成 `%wheel ALL=(ALL:ALL) SETENV: ALL`），不是 Defaults 行。
    #
    # 安全性说明：星号会泄露密码长度给肩窥者，这是这个选项固有的取舍。
    # 历史上 pwfeedback 有过一个缓冲区溢出漏洞（CVE-2019-18634），
    # 但那在 sudo 1.8.31 就修掉了，本机是 1.9.17p2，不受影响。
    #
    # 只对 sudo 生效。ssh 的密钥口令、`su`、`passwd` 各有各的实现，
    # 不受这里控制；GNOME 的图形提权弹窗本来就显示圆点。
    security.sudo.extraConfig = ''
      Defaults pwfeedback
    '';

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

      # 分区与文件系统工具。
      #
      # 加进来而不是靠 nix shell 临时取，理由是**需要它们的时候往往在
      # 处理硬盘问题** —— 可能刚救回来一个系统、可能没网，
      # 那时候再去下载最不合时宜。三个包都很小。
      #
      # 而且 MIGRATION.md 第 4.3 节（加 NTFS 共享盘）明确让人跑
      # parted 和 mkfs.ntfs，而加共享盘正常是**装好之后**才做的事 ——
      # 文档里让跑的命令，不该在目标系统上不存在。
      parted
      gptfdisk # sgdisk，脚本里比 parted 好用
      ntfs3g # mkfs.ntfs；内核态驱动是 ntfs3，但格式化要这个
    ];

    # 字体与 fontconfig 统一在 modules/localization.nix 中配置。
    # 这里曾经也有一份 fonts.packages + fontconfig.defaultFonts，与
    # localization.nix 重复声明了 noto-fonts / noto-fonts-cjk-serif /
    # sarasa-gothic，且 defaultFonts 引用的字体只装在 localization.nix 里。
  };
}

{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  hardware.bluetooth.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.printing.enable = true;

  # ============================================
  # 默认终端：Ghostty
  # ============================================
  # 终端本体由 home/toru.nix 的 programs.ghostty 声明（那边才能接 stylix），
  # 这里只负责告诉桌面「按下『在终端中打开』时该开谁」。
  #
  # 走的是 Default Terminal Execution Specification：桌面环境调
  # xdg-terminal-exec，它按 XDG_CURRENT_DESKTOP 匹配下面的键，
  # 找不到就用 default。GNOME 的 gsettings
  # org.gnome.desktop.default-applications.terminal 已经指向
  # xdg-terminal-exec，所以不需要再去改 dconf。
  #
  # GNOME 和 default 都写上：前者是本机现状，后者保证将来换桌面环境
  # （或者加一台跑别的 DE 的机器）时行为不变。
  xdg.terminal-exec = {
    enable = true;
    settings = {
      GNOME = [ "com.mitchellh.ghostty.desktop" ];
      default = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

  # ============================================
  # 文件管理器右键「在终端中打开」
  # ============================================
  # 上面那个 xdg.terminal-exec **管不到 Nautilus**，必须再加这一层。
  #
  # 原因：Nautilus 50 的二进制里硬编码了 org.gnome.Console，
  # 直接通过 D-Bus 调 GNOME Console，既不读 xdg-terminals.list，
  # 也不读 org.gnome.desktop.default-applications.terminal 那个遗留
  # gsettings 键。验证方法：
  #
  #     grep -aoE "org\.gnome\.(Console|Terminal)" \
  #       $(readlink -f $(command -v nautilus) | xargs dirname)/.nautilus-wrapped
  #
  # 所以光配 xdg.terminal-exec 的话，右键菜单会**静默地**继续开 kgx，
  # 构建和配置都看不出问题 —— 又一个「配置正确但没生效」的坑。
  #
  # 解决办法不用装第三方扩展：**Ghostty 自己就带一个 Nautilus 扩展**
  # （ghostty.py，标签就是 Open in Ghostty），由 home-manager 装到
  # /etc/profiles/per-user/toru/share/nautilus-python/extensions/。
  #
  # 它之前没生效，是因为少了 nautilus-python —— 那是加载 .py 扩展的
  # 运行时，没有它任何 Python 扩展都不会被读，Nautilus 就退回内置的
  # kgx 菜单项。所以这里只需要补上运行时本身。
  #
  # 踩过的弯路记一下：一开始用的是 programs.nautilus-open-any-terminal，
  # 右键菜单确实变成 Ghostty 了，但会出现**两个** Open in Ghostty ——
  # 那个模块顺带装了 nautilus-python，于是 ghostty 自带的扩展也一起
  # 被激活，两个扩展各加一项。换成只装运行时就只剩一项。
  #
  # 两层各管一部分，将来换终端时**两处都要改**：
  #   xdg.terminal-exec   遵循 XDG 规范的程序
  #   终端自带的扩展      Nautilus 右键菜单（换终端时要确认新终端
  #                       是否也自带；不自带的话再考虑
  #                       programs.nautilus-open-any-terminal）
  environment.systemPackages = [ pkgs.nautilus-python ];

  # 注：刻意**没有**把 GNOME 自带的 Console (kgx) 排除掉。
  # 它留着当兜底——ghostty 万一起不来（显卡/Wayland 相关问题），
  # 还有一个能开的终端可以用来 rollback。
  # 想清掉的话是一行：environment.gnome.excludePackages = [ pkgs.gnome-console ];
}

{ pkgs, ... }:

{
  # ============================================
  # Stylix —— 全局配色的单一真相
  # ============================================
  # 一份 base16 配色方案，由 stylix 渗透到所有支持的程序，各程序自己的
  # 配置格式由它生成。这样换主题只改这个文件一处，不用去 bat、starship、
  # tmux…… 各改一遍 —— 那正是 CLAUDE.md 反复警告的「两边描述同一件事，
  # 改了一边忘改另一边」。
  #
  # 放 modules/ 而不是 hosts/：配色方案换台机器一样成立，不绑定硬件。
  # （壁纸将来如果要按屏幕分辨率区分，那一条才该挪进 hosts/。）

  # stylix.enable 默认是 false，不写这一句整个模块不生效。
  stylix.enable = true;

  # ============================================
  # 配色方案
  # ============================================
  # 手写死一份，**不**让 stylix 从壁纸自动生成配色。
  # 自动生成的结果不可预测，换张壁纸整套颜色就变了，和这里想要的
  # 「配色是稳定的、壁纸是可换的」正好相反。
  #
  # base16-schemes 里有 303 套现成方案，将来多主题切换就是换这一行。
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";

  # ============================================
  # polarity —— 必须显式写，不能省
  # ============================================
  # 这一条容易被当成「配色方案自己知道自己是深色，不用重复说」而漏掉，
  # 但实际不是：polarity 的默认值是 "either"，而 GNOME 那边的逻辑是
  #
  #     color-scheme = if polarity == "dark" then "prefer-dark" else "default"
  #     （stylix/modules/gnome/hm.nix）
  #
  # "either" 不等于 "dark"，会落到 "default"，也就是**亮色**界面。
  # 结果就是深色终端配亮色 GNOME 窗口的错配。
  # 读 polarity 的不止 GNOME，还有 qt、zen-browser、dunst 等十几个 target。
  #
  # 硬规则：**base16Scheme 和 polarity 永远成对出现**，
  # 将来加亮色主题时两个都要改。
  stylix.polarity = "dark";

  # ============================================
  # 壁纸
  # ============================================
  # 用 nixpkgs 自带的 NixOS 官方壁纸：不用管下载和文件放哪，可复现，
  # 换台机器自动就有。
  #
  # 选 nineish-dark-gray 的理由和「好看」无关：它近乎单色（近黑底
  # + 极淡灰描边），所以在任何配色方案下都不违和。将来要频繁切主题，
  # 一张强色调的壁纸会跟一半的主题打架。
  #
  # 另外 gnome target 的壁纸功能要求 stylix.image 不为 null，
  # 不给的话那部分是空转的。
  stylix.image = "${pkgs.nixos-artwork.wallpapers.nineish-dark-gray}/share/backgrounds/nixos/nix-wallpaper-nineish-dark-gray.png";

  # ============================================
  # 逐个白名单启用，不用「默认全开」
  # ============================================
  # autoEnable 默认是 true，会去接管它认识的**所有**已启用程序，
  # 包括 Neovim 和 GTK —— 那会立刻和 home/toru.nix 里手写的
  # colorscheme gruvbox 打架。
  #
  # 关掉总开关、逐个 enable，好处是每一步的影响范围都可控，
  # 出问题能精确定位到是哪个 target。
  stylix.autoEnable = false;

  # ============================================
  # target 写在哪一层：和本仓库既有分工一致
  # ============================================
  # stylix 的 target 分两种实现：NixOS 级（modules/<名字>/nixos.nix）
  # 和 home-manager 级（hm.nix）。**只能写在自己那一层**，写错层
  # 会得到 `The option 'stylix.targets.bat' does not exist`。
  #
  # 本文件只放：调色板本身（上面那几项）+ NixOS 级的 target。
  # 用户程序的 target（bat / starship / tmux / …）全部写在
  # home/toru.nix，理由和 modules/shell.nix 开头那段完全一样 ——
  # 系统层只放必须在系统层的东西，交互体验归 home/toru.nix。
  #
  # 上面 enable / base16Scheme / polarity / image / autoEnable 这几项
  # 会由 stylix.homeManagerIntegration.followSystem（默认开）以 mkDefault
  # 的优先级自动透传给 home-manager，所以那边不用重复写一遍调色板。
  # 「以 mkDefault 透传」这一点将来做多主题切换时是关键：
  # specialisation 里的普通赋值可以干净地覆盖掉它。
  #
  # 注意 stylix.targets **不在**上面那份透传清单里，所以同名 target
  # 在两层要各写一次，不是写一处两边都生效。
  stylix.targets = {
    # gtk 的 NixOS 侧只做一件事：programs.dconf.enable = true，
    # 这是 home-manager 的 GTK 设置能落地的前提。
    # 本仓库 modules/desktop-gnome.nix 里本来就开了 dconf，
    # 这里是幂等的，写上是为了不依赖另一个模块的实现细节。
    gtk.enable = true;

    # gnome 的 NixOS 侧管 GDM 登录界面的光标，以及在设了 stylix.image
    # 时把 gnome-backgrounds 从默认包里排掉（避免系统壁纸和这里指定的
    # 壁纸两套并存）。
    gnome.enable = true;

    # qt 刻意不开，理由写在 home/toru.nix 的同一处：
    # platform 在 GNOME 上取到 "gnome"，而 stylix 只支持 "qtct"，
    # 开了只会报警告不注入配色；要真生效得引入 kvantum，
    # 而本机唯一的 Qt 图形程序只有 fcitx5 的配置对话框，不划算。
  };

  # console / plymouth / grub 这三个 NixOS 级 target 仍然没开：
  # 都是开机和 TTY 场景，平时看不到，而且它们是**多主题切换切不到**的
  # 那部分（home-manager specialisation 只能换 HM 级的东西）。
  # 等主题方案最终定下来再一次性配好，避免切主题后开机画面对不上。
}

{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  # 仓库位置与 flake 属性名。别名和脚本都从这里取，不要各写一份。
  repoPath = "${config.home.homeDirectory}/nixos-config";
  flakeHost = osConfig.custom.flakeHost;

  baseExtensionPolicies = {
    ExtensionUpdate = true;
    ExtensionSettings = {
      "*" = {
        installation_mode = "allowed";
      };
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "force_installed";
      };
      "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4885390/latest.xpi";
        installation_mode = "force_installed";
      };
      "addon@darkreader.org" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        installation_mode = "force_installed";
      };
      "sponsorBlocker@ajay.app" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
        installation_mode = "force_installed";
      };
      "{b9acf540-acba-11e1-8ccb-001fd0e08bd4}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4997872/latest.xpi";
        installation_mode = "force_installed";
      };
    };
  };

  # ============================================
  # 别名（bash / zsh 共用同一份）
  # ============================================
  # 硬规则：**不遮蔽任何标准命令**。没有 ls=eza、cat=bat、grep=rg 这种写法。
  # 理由见下面「Shell 环境」一节第 2 条 —— 人看到的输出和 AI 看到的输出
  # 必须是同一个东西。
  commonAliases = {
    # 目录列表：一律另起名字，ls 保持 coreutils 原样
    ll = "eza -l --group-directories-first --git";
    la = "eza -la --group-directories-first --git";
    lt = "eza --tree --level=2";

    # 本仓库的高频操作（命令本体见 CLAUDE.md「验证流程」）
    #
    # 仓库路径和主机名都**不写死**：
    #   repoPath  从 home.homeDirectory 推，换用户名也成立
    #   flakeHost 从系统层的 custom.flakeHost 取，不是 networking.hostName ——
    #             后者在本机是 thinkpad-nixos，而 flake 属性是 thinkpad
    #
    # 写死过一次：四个别名里都是 `/home/toru/nixos-config#thinkpad`，
    # 结果新机器上 nrb 会去构建 thinkpad 的配置。
    nrb = "sudo nixos-rebuild switch --flake ${repoPath}#${flakeHost}";
    nrt = "sudo nixos-rebuild test --flake ${repoPath}#${flakeHost}";
    ncheck = "nix build ${repoPath}#nixosConfigurations.${flakeHost}.config.system.build.toplevel --out-link /tmp/res";
    nhm = "nix build ${repoPath}#nixosConfigurations.${flakeHost}.config.home-manager.users.${config.home.username}.home.activationPackage --out-link /tmp/hm";
    # 用 nixos-rebuild 而不是 nix-env --list-generations：后者要开
    # /nix/var/nix/profiles/system.lock，非 root 直接 permission denied。
    # 前者不用 sudo，而且带构建日期、内核版本和 Current 标记。
    ngen = "nixos-rebuild list-generations";

    # git
    gs = "git status -sb";
    gd = "git diff";
    gl = "git log --oneline --graph --decorate -20";
  };

  # ============================================
  # 多主题：home-manager specialisation
  # ============================================
  # 目标是 Omarchy 那种「随时换整套配色」。stylix 本身是**构建期**着色，
  # 没有运行时切换的概念，所以这里用 Nix 原生的等价物：
  # 每套主题预先构建成一个 home-manager specialisation，
  # 切换时跑它的 activate 脚本。
  #
  # 为什么这条路走得通（是查了实现确认的，不是想当然）：
  # stylix 的 homeManagerIntegration 把系统层的调色板设置以
  # **lib.mkDefault** 的优先级灌进 home 层
  # （stylix/home-manager-integration.nix:18），所以 specialisation 里
  # 一条普通赋值就能干净地盖掉它。
  #
  # 为什么用 home 层而不是 NixOS 层的 specialisation：
  #   1. 不需要 sudo，不改系统状态。
  #   2. **不污染引导菜单。** NixOS specialisation 会给每个 generation
  #      每套主题各生成一个引导项，20 个 generation × N 套主题，
  #      直接打穿 hosts/thinkpad/default.nix 里 configurationLimit = 20
  #      那条限制。
  #   3. 日常看得见的东西全在 home 层：ghostty、bat、starship、
  #      neovim、gtk、gnome(dconf)、vscode、zsh 配色。
  #      切不到的只有 console(TTY) / plymouth / grub，
  #      那三个本来也没开。
  #
  # 已知代价：home-manager 官方把 specialisation 标为 experimental，
  # 原文是 "the activation process may change in backwards incompatible
  # ways"。升级 home-manager 时要留意这一块。

  # 壁纸按明暗配对。两张都是 NixOS 官方那套雪花几何，同一个图形的
  # 深浅两版，所以换主题时观感是连续的，不会突然变成另一张图。
  # 选它们的理由仍然是「近乎单色」—— 要频繁切主题，
  # 强色调的壁纸会跟一半的主题打架。
  wallpapers = {
    dark = "${pkgs.nixos-artwork.wallpapers.nineish-dark-gray}/share/backgrounds/nixos/nix-wallpaper-nineish-dark-gray.png";
    light = "${pkgs.nixos-artwork.wallpapers.nineish}/share/backgrounds/nixos/nix-wallpaper-nineish.png";
  };

  # 光标也按明暗配对。stylix.cursor 本身是单一值（不像 icons 会按
  # polarity 自动选），但它在 homeManagerIntegration 的透传清单里，
  # 所以 specialisation 能覆盖 —— 在 mkTheme 里统一处理，
  # 免得亮色主题配一个白光标（在浅色背景上几乎看不见）。
  #
  # 包和尺寸在 modules/stylix.nix 里设，这里只换名字。
  cursors = {
    dark = "Bibata-Modern-Ice"; # 白色，配深色背景
    light = "Bibata-Modern-Classic"; # 黑色，配浅色背景
  };

  # base16Scheme 和 polarity **必须成对**出现，理由见 modules/stylix.nix：
  # polarity 默认值 "either" 不等于 "dark"，GNOME 会落到亮色界面，
  # 结果是深色终端配亮色窗口的错配。这里用一个函数生成，
  # 从结构上保证不会漏掉其中一个，顺带把壁纸和光标也一起配好。
  #
  # 调色板有两种给法，二选一：
  #   scheme   base16-schemes 包里的方案文件名（现成的 19 套走这条）
  #   palette  直接写一份 base16 属性集（手写的那两套走这条）
  # stylix.base16Scheme 的类型是 path | lines | attrs，
  # 属性集这条路实测可用。
  mkTheme =
    {
      polarity,
      scheme ? null,
      palette ? null,
    }:
    {
      configuration = {
        stylix.base16Scheme =
          if palette != null then
            palette
          else if scheme != null then
            "${pkgs.base16-schemes}/share/themes/${scheme}.yaml"
          else
            throw "mkTheme: scheme 和 palette 必须给一个";
        stylix.polarity = polarity;
        stylix.image = wallpapers.${polarity};
        # 只写 name 不行：stylix.cursor 是个 nullOr submodule，
        # 在 specialisation 里只给一个子属性的话，package 和 size 会退回
        # 它们各自的默认值 null，把透传进来的 mkDefault 顶掉，
        # 于是 stylix/hm/cursor.nix 里 home.pointerCursor 拿到 null 包，
        # 报 "cannot coerce null to a string"。（实测踩到过。）
        #
        # 所以整个 submodule 一起给，package 和 size 从外层 config 取 ——
        # 那是 modules/stylix.nix 里设的那份，仍然只有一处真相。
        stylix.cursor = {
          inherit (config.stylix.cursor) package size;
          name = cursors.${polarity};
        };
      };
    };

  # ============================================
  # 主题清单
  # ============================================
  # **基础主题 gruvbox-dark-hard 不在这里** —— 它是 modules/stylix.nix
  # 里的默认值，切回它用 `theme default`。所以总数是 19 + 1 = 20 套，
  # 10 暗 10 亮。
  #
  # 方案名是 base16-schemes 包里的 yaml 文件名，全部逐个确认过存在。
  # 明暗归类不是按名字猜的：base16 的 yaml 自带 variant 字段，
  # 交叉比对过 base00 的相对亮度，303 个方案上零矛盾。
  #
  # 其中 7 组是「同族明暗对」（gruvbox / catppuccin / nord /
  # tokyo-night / rose-pine / solarized / onedark），换句话说
  # 大部分主题都能原地切明暗。
  # everforest / kanagawa / dracula 在 base16-schemes 里没有亮色变体，
  # github / ayu-light / selenized-light 则没有对应的暗色，属于落单的。
  #
  # 加主题只需往这张表里加一行，生成逻辑和 theme 命令都不用动。
  # 代价是每套给「改配置后重建」增加约 5 秒（实测，见提交注释）。
  themes = {
    # ---------- 暗色（连基础的 gruvbox-dark-hard 共 10 套） ----------
    catppuccin-mocha = {
      scheme = "catppuccin-mocha";
      polarity = "dark";
    };
    everforest = {
      scheme = "everforest-dark-hard";
      polarity = "dark";
    };
    nord = {
      scheme = "nord";
      polarity = "dark";
    };
    tokyo-night = {
      scheme = "tokyo-night-dark";
      polarity = "dark";
    };
    rose-pine = {
      scheme = "rose-pine";
      polarity = "dark";
    };
    solarized-dark = {
      scheme = "solarized-dark";
      polarity = "dark";
    };
    onedark = {
      scheme = "onedark";
      polarity = "dark";
    };
    kanagawa = {
      scheme = "kanagawa";
      polarity = "dark";
    };
    dracula = {
      scheme = "dracula";
      polarity = "dark";
    };

    # ---------- 手写调色板：Cyberpunk 2077（暗） ----------
    # base16-schemes 里没有现成的，自己配一份。
    #
    # 取色依据是游戏的视觉标识而不是随便挑霓虹色：
    #   #fcee0a  那个标志性的酸性黄，游戏 UI、logo、义体高亮都用它
    #   #00f0ff  夜之城的电子青
    #   #ff003c  警示红/洋红，任务失败和敌对标记
    #   #d300c5  霓虹紫，招牌和全息广告
    # 背景取近黑但带一点蓝（#0b0d13）而不是纯黑，
    # 纯黑在 OLED 以外的屏幕上反而显脏。
    #
    # 分配到 base16 的槽位时按本仓库 zsh 那套语义走
    # （见 programs.zsh.syntaxHighlighting.styles 的注释）：
    # 黄给字符串、绿给「能跑的命令」、青给插值、紫给关键字。
    # 所以最抢眼的酸性黄落在 base0A，写字符串时最显眼。
    #
    # base03（注释）刻意用了偏亮的 #4b5878：霓虹配色容易把注释
    # 压到看不见，这是 gruvbox 那个 fg=black 坑的同类问题。
    cyberpunk-2077 = {
      polarity = "dark";
      palette = {
        base00 = "0b0d13"; # 背景，近黑带蓝
        base01 = "141824";
        base02 = "1f2535"; # 选中
        base03 = "4b5878"; # 注释，刻意提亮保证可读
        base04 = "7d8aa8";
        base05 = "c5d1e6"; # 正文，冷白
        base06 = "e2eaf7";
        base07 = "ffffff";
        base08 = "ff003c"; # 警示红，报错
        base09 = "ff6d1f"; # 霓虹橙，选项
        base0A = "fcee0a"; # 标志性酸性黄，字符串
        base0B = "00ff9f"; # 霓虹薄荷绿，命令
        base0C = "00f0ff"; # 电子青，插值
        base0D = "0a84ff"; # 电光蓝，内建
        base0E = "d300c5"; # 霓虹紫，关键字
        base0F = "ff5470";
      };
    };

    # ---------- 亮色（10 套） ----------

    # ---------- 手写调色板：NieR: Automata（亮） ----------
    # 游戏 UI 是一整套做旧的米色 + 暗橄榄字，几乎没有饱和色，
    # 这也是它和其它亮色主题最不一样的地方 —— 别的亮色主题背景
    # 都偏白偏冷，这套是暖米色。
    #
    #   #d1cdbe  主背景，泛黄的米色（游戏菜单底色）
    #   #4e4a3f  正文，暗橄榄褐（游戏里的字色）
    #   #a24b42  唯一比较跳的颜色，对应游戏里的警示红
    # 其余强调色全部压低饱和度，保持那种褪色、风化的观感。
    #
    # 注意它不是「把暗色反过来」：低饱和度是刻意的，
    # 如果按常规亮色主题的做法给足饱和度，就不像 NieR 了。
    nier-automata = {
      polarity = "light";
      palette = {
        base00 = "d1cdbe"; # 背景，做旧米色
        base01 = "c7c2b1";
        base02 = "b9b3a0"; # 选中
        base03 = "8b8676"; # 注释
        base04 = "6d6857";
        base05 = "4e4a3f"; # 正文，暗橄榄褐
        base06 = "3a3730";
        base07 = "2a2823";
        base08 = "a24b42"; # 警示红，报错
        base09 = "b1763c"; # 陶土橙，选项
        base0A = "977a2e"; # 暗金，字符串
        base0B = "68764a"; # 橄榄绿，命令
        base0C = "4d7a70"; # 灰青，插值
        base0D = "5a6d88"; # 石板蓝，内建
        base0E = "7c5f7e"; # 灰紫，关键字
        base0F = "8a6a48";
      };
    };

    gruvbox-light = {
      scheme = "gruvbox-light-hard";
      polarity = "light";
    };
    catppuccin-latte = {
      scheme = "catppuccin-latte";
      polarity = "light";
    };
    nord-light = {
      scheme = "nord-light";
      polarity = "light";
    };
    tokyo-night-light = {
      scheme = "tokyo-night-light";
      polarity = "light";
    };
    rose-pine-dawn = {
      scheme = "rose-pine-dawn";
      polarity = "light";
    };
    solarized-light = {
      scheme = "solarized-light";
      polarity = "light";
    };
    one-light = {
      scheme = "one-light";
      polarity = "light";
    };
    github = {
      scheme = "github";
      polarity = "light";
    };
    ayu-light = {
      scheme = "ayu-light";
      polarity = "light";
    };
    selenized-light = {
      scheme = "selenized-light";
      polarity = "light";
    };
  };

  # 20 套的列表如果只按字母排，暗色和亮色会交错在一起，选起来很难找。
  # 所以把明暗信息在**构建期**烤进 theme 命令里：这张表 Nix 这边是
  # 已知的，运行时却只能看到 specialisation 的目录名，没法反推。
  themePolarity = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: t: "    ${name}) echo ${t.polarity} ;;") themes
  );
  # 记住当前选的主题。放 XDG_STATE_HOME 下：它就该是「跨会话保留、
  # 但丢了也不影响正确性」的那类数据（和 atuin 的库、nvim 的 shada 同类）。
  # theme 命令写它，home.activation.restoreTheme 读它。
  themeStateFile = "\${XDG_STATE_HOME:-$HOME/.local/state}/theme/current";

  # theme 命令的实现，见下面 home.packages 处的说明。
  themeSwitcher = pkgs.writeShellApplication {
    name = "theme";
    runtimeInputs = [ pkgs.fzf ];
    text = ''
      # ============================================
      # 基础 generation 从 systemd 单元里取，不从 gcroots 取
      # ============================================
      # 这一点踩过坑，不是随便选的来源。
      #
      # ~/.local/state/home-manager/gcroots/current-home 指向的是
      # **当前激活的** generation。切到某套主题之后，它就指向那个
      # specialisation 自己的 generation —— 而 specialisation **不嵌套**
      # （home-manager 在 modules/misc/specialisation.nix 里写了
      # specialisation = lib.mkOverride 0 { } 来防止无限递归），
      # 那个 generation 底下没有 specialisation 目录。
      #
      # 结果就是：切过去之后 theme list 只剩 default，
      # theme default 跑的是当前主题自己的 activate（切不回去），
      # 指名切别的主题则报「没有这套主题」—— 一去不复返。
      #
      # systemd 单元里记的始终是 nixos-rebuild switch 装上的那个
      # **基础** generation，跑 activate 不会改它，所以拿它当锚点。
      unit="/etc/systemd/system/home-manager-$USER.service"

      if [ ! -e "$unit" ]; then
        echo "找不到 home-manager 的 systemd 单元: $unit" >&2
        echo "先跑一次 nixos-rebuild switch。" >&2
        exit 1
      fi

      base=$(grep -oE '/nix/store/[a-z0-9]+-home-manager-generation' "$unit" | head -1)

      if [ -z "$base" ] || [ ! -d "$base" ]; then
        echo "从单元里解析不出基础 generation。" >&2
        exit 1
      fi

      # ============================================
      # 当前是哪一套：读状态文件，**不要**去比对 gcroot
      # ============================================
      # 这里踩过坑。原先的写法是把
      #   ~/.local/state/home-manager/gcroots/current-home
      # 和基础 generation、各 specialisation 的 realpath 逐个比对。
      # 平时看着没问题，但开机之后就会报错成 default。
      #
      # 原因是 activate 脚本的执行顺序：
      #
      #   第 445 行  restoreTheme 钩子跑 specialisation 的 activate，
      #              那一步会把 current-home 指向 specialisation
      #   第 468 行  基础 activate 在**所有钩子跑完之后**执行
      #                nix-store --realise "$newGenPath" \
      #                  --add-root "$currentGenGcPath"
      #              无条件把 current-home 指回它自己
      #
      # 于是开机后进入一个错位状态：配置文件是 specialisation 写的
      # （所以看到的配色是对的），gcroot 却指着基础 generation。
      # 这个顺序改不了 —— 那一行在 home-manager 自己的脚本里，
      # 排在用户钩子之后。
      #
      # 状态文件才是「选了哪套」的权威记录：theme 每次切换成功都写它，
      # restoreTheme 每次开机都照它恢复，两边引用的是同一个事实。
      state_file="${themeStateFile}"
      current_name="default"
      if [ -r "$state_file" ]; then
        saved=$(cat "$state_file")
        # 记录的主题可能已经从 themes 表里删掉了。那种情况下
        # restoreTheme 会警告一声然后保持默认，所以这里也报 default，
        # 两边说法一致。不加这个判断的话列表里会一行标记都没有。
        if [ -n "$saved" ] && { [ "$saved" = "default" ] || [ -d "$base/specialisation/$saved" ]; }; then
          current_name="$saved"
        fi
      fi

      # 明暗对照表在构建期由 Nix 生成（见 home/toru.nix 的 themePolarity）。
      # 运行时只能看到 specialisation 的目录名，反推不出明暗。
      polarity_of() {
        case "$1" in
          default) echo dark ;;
      ${themePolarity}
          *) echo "?" ;;
        esac
      }

      # 20 套按字母排会让明暗交错，很难找。这里先暗后亮、组内按字母，
      # 并把明暗标在名字后面。
      list_themes() {
        {
          echo "default"
          if [ -d "$base/specialisation" ]; then
            find "$base/specialisation" -maxdepth 1 -mindepth 1 -printf '%f\n'
          fi
        } | while read -r n; do
          printf '%s\t%s\n' "$(polarity_of "$n")" "$n"
        done | sort -k1,1 -k2,2 | while IFS=$'\t' read -r p n; do
          printf '%-20s %s\n' "$n" "[$p]"
        done
      }

      # 从 list_themes 的一行里取回主题名
      name_of_line() { echo "$1" | awk '{print $1}'; }

      # 在当前主题那一行末尾加标记
      mark_current() { sed "s/^\\($current_name  *\\[[a-z?]*\\]\\)\$/\\1  <- 当前/"; }

      case "''${1-}" in
        list|-l|--list)
          list_themes | mark_current
          exit 0
          ;;
        "")
          line=$(list_themes | mark_current \
            | fzf --prompt='主题> ' --height=60% --layout=reverse --border) || exit 0
          target=$(name_of_line "$line")
          ;;
        *)
          target="$1"
          ;;
      esac

      [ -z "$target" ] && exit 0

      if [ "$target" = "default" ]; then
        script="$base/activate"
      else
        script="$base/specialisation/$target/activate"
      fi

      if [ ! -x "$script" ]; then
        echo "没有这套主题: $target" >&2
        echo "可用的：" >&2
        list_themes | sed 's/^/  /' >&2
        exit 1
      fi

      "$script"

      # ============================================
      # 记住这次的选择，好让开机后能恢复
      # ============================================
      # 不记的话，下次开机 home-manager-toru.service 会重跑**基础**
      # generation 的 activate，主题就被打回默认。nixos-rebuild switch
      # 同理。恢复动作在 home.activation.restoreTheme 里，见那边的注释。
      state="${themeStateFile}"
      mkdir -p "$(dirname "$state")"
      printf '%s\n' "$target" > "$state"

      # ============================================
      # 强制已经开着的 GTK 程序重建整套样式
      # ============================================
      # 不加这一步的话，切主题后 GTK 程序的**标题栏不会变色**，
      # 内容区却变了，要注销重登才一致。原因查清楚了：
      #
      #   切换主题时，GTK 这边唯一变的是 ~/.config/gtk-{3,4}.0/gtk.css
      #   这个符号链接的目标。dconf 里那组 interface 键
      #   （gtk-theme / color-scheme / 各种字体）在同明暗的主题之间
      #   **完全相同** —— gtk-theme 永远是 adw-gtk3，
      #   color-scheme 永远跟着 polarity 走。
      #
      #   也就是说没有任何 dconf 变化去触发 GTK 重建样式。
      #   stylix 的 activate 脚本里 "gtk" 出现 0 次，它只写文件、
      #   从不通知运行中的程序（对比 gnome-shell 那边是有
      #   gnome-extensions disable/enable 重载钩子的，所以顶栏立刻变）。
      #
      # 把 gtk-theme 改一下再改回来，GtkSettings:gtk-theme-name 变化会
      # 让 GTK 重建整条样式级联，标题栏也跟着重算。
      # 中间那一下会让窗口闪一次，这是代价。
      if command -v gsettings >/dev/null 2>&1; then
        gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
        if [ -n "$gtk_theme" ]; then
          gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
          gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
        fi
      fi

      echo
      echo "已切到主题: $target"
      echo "GTK 程序已强制重载样式。Electron 程序（VSCode 等）和终端"
      echo "仍然要重开才会跟上 —— 它们的配色是启动时读的文件。"
    '';
  };
in
{
  imports = [
    # Agent Skills：一份 skill 同时喂给 Claude Code / Copilot / Zed / Gemini。
    # 拆出去是因为它自带一套命令（skills、skills-update）和生成逻辑，
    # 塞进这个文件会把本来就长的 toru.nix 顶到没法读。
    ./agent-skills.nix

    # state-sync（搬 B 类用户状态）和 migration-check（查漂移）。
    # 同样自带命令和构建期测试，拆出去。见 MIGRATION.md 第 7 和第 10 节。
    ./migration.nix
  ];

  home.username = "toru";
  home.homeDirectory = "/home/toru";
  home.stateVersion = "26.05";

  # 每套主题生成一个 specialisation，见上面 let 里的说明。
  specialisation = lib.mapAttrs (_name: mkTheme) themes;

  # ============================================
  # 开机 / 重建之后把主题恢复回来
  # ============================================
  # 没有这一段的话，切过的主题**记不住**：
  # home-manager-toru.service 是 WantedBy=multi-user.target 的系统服务，
  # 每次开机都跑一遍**基础** generation 的 activate，把主题覆盖回默认。
  # nixos-rebuild switch 也走同一条路，所以每次重建也会被打回去。
  #
  # 这不是 NixOS 的固有限制，只是 specialisation 本身不带「记住选择」
  # 这个概念 —— 它只提供「切过去」的能力，记不记得是配置的事。
  #
  # 防递归靠的是 specialisation 不嵌套这个特性（home-manager 在
  # modules/misc/specialisation.nix 里用 mkOverride 0 防无限递归）：
  # specialisation 自己的 generation 底下没有 specialisation 目录，
  # 所以下面那个 [ -x ] 测试必然失败，钩子自动空转，不用额外的标志位。
  # 这个特性之前坑过 theme 命令，这次正好拿来当守卫。
  #
  # 刻意**不**调 theme 命令而是直接跑 activate：开机时还没有图形会话，
  # theme 里那段 gsettings 的 GTK 重载会失败；而那时也没有程序需要重载。
  #
  # 失败不让它中断整个激活（|| true）：主题恢复不了顶多是配色不对，
  # 不该把 nixos-rebuild switch 拖成 CLAUDE.md 坑 4 那种半成功状态。
  home.activation.restoreTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state="${themeStateFile}"
    if [ -r "$state" ]; then
      want=$(cat "$state")
      if [ -n "$want" ] && [ "$want" != "default" ]; then
        if [ -x "$newGenPath/specialisation/$want/activate" ]; then
          verboseEcho "restoreTheme: 恢复主题 $want"
          run "$newGenPath/specialisation/$want/activate" || \
            warnEcho "restoreTheme: 恢复 $want 失败，保持默认主题"
        elif [ -d "$newGenPath/specialisation" ]; then
          # 只在基础 generation 上报警告。specialisation 自己激活时
          # 走不到这里（它没有 specialisation 目录），不会误报。
          warnEcho "restoreTheme: 记录的主题 $want 已不存在，保持默认主题"
        fi
      fi
    fi
  '';

  # ============================================
  # theme —— 主题切换命令
  # ============================================
  # 做成 PATH 上的**真二进制**而不是 shell 函数或别名。
  # 这是 CLAUDE.md「Shell 环境」那一节的硬规则：别名只存在于交互 shell，
  # 脚本和 AI 跑 `zsh -c 'theme ...'` 会直接 command not found。
  #
  # 切换靠跑 specialisation 自己的 activate 脚本。那个路径是稳定的：
  #   ~/.local/state/home-manager/gcroots/current-home
  # 是 home-manager 维护的、指向当前 generation 的符号链接。
  #
  # 注意两件事：
  #   1. 跑 activate 会**新建一个 home-manager generation**，这是
  #      home-manager 官方文档里就这么说的正常行为，不是副作用。
  #   2. 下一次 nixos-rebuild switch 会把主题**重置回基础主题**。
  #      因为 switch 激活的是基础 generation，而 specialisation 是
  #      挂在它下面的分支。想长期换主题就改 modules/stylix.nix 里的
  #      base16Scheme，而不是靠这个命令。
  #
  # 实现见文件开头 let 里的 themeSwitcher，包在下面的 home.packages 里。

  # ============================================
  # Firefox（系统默认浏览器）
  # ============================================
  programs.firefox = {
    enable = true;
    policies = baseExtensionPolicies;
  };

  # 把 Firefox 设为默认浏览器。
  # 之前没有任何模块声明过默认浏览器，GNOME 便自行选了 Epiphany
  # （`xdg-settings get default-web-browser` 会返回 org.gnome.Epiphany.desktop），
  # 于是从终端 / 其它应用打开链接都会跳到 GNOME Web。
  #
  # xdg.mimeApps 会接管 ~/.config/mimeapps.list。
  # BROWSER 变量给不读 mimeapps.list 的 CLI 程序（如部分 TUI）用。
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
    };
  };

  home.sessionVariables.BROWSER = "firefox";

  # ============================================
  # Shell 环境（zsh 为主，bash 保持对等）
  # ============================================
  # 设计前提：这台机器上的 shell 不只给人用，也经常被 AI 编码助手
  # （Claude Code / Copilot CLI 之类）拿去跑命令。它们跑的是**非交互** shell，
  # `.zshrc` 根本不会被 source。由此有三条硬规则：
  #
  #   1. 工具必须是 PATH 上的真二进制，不能靠 alias。
  #      alias 只存在于交互 shell，`zsh -c 'll'` 会直接 command not found。
  #      下面所有工具都通过 programs.* 落到 /etc/profiles/per-user/toru/bin
  #      （home-manager.useUserPackages = true 的效果），任何 shell、
  #      任何模式下都能直接调用。
  #
  #   2. 绝不用 alias 遮蔽 ls / cat / grep / find 这类标准命令。
  #      否则终端里看到的是 eza 的彩色分栏，AI 看到的是 coreutils ls 的
  #      原始输出，同一条命令两份结果，排查问题时会互相误导；更糟的是
  #      一旦 alias 漏进脚本，输出格式变了，解析就全错。
  #      home-manager 的 programs.eza 默认就会写 `ls = "eza"`，
  #      所以下面显式关掉它的 shell integration，另起不冲突的名字。
  #
  #   3. bash 和 zsh 配成同一套基线（PATH、direnv、starship、别名都双边启用）。
  #      AI 用哪个 shell 结果都一样，不会出现「我这边好好的，它那边不行」。
  #
  # 注：启用 programs.bash 后，home-manager 要接管 ~/.bashrc。
  #     已存在的那份会被改名成 ~/.bashrc.hm-bak，不会中断激活 ——
  #     靠的是 hosts/thinkpad/default.nix 里的 backupFileExtension，见 000B。

  programs.zsh = {
    enable = true;

    # 系统层 programs.zsh.enable 已经在 /etc/zshrc 里跑过 compinit。
    # 这里再来一次的话，每开一个终端都要多花几百毫秒重建补全缓存。
    enableCompletion = false;

    # home.stateVersion 是 "26.05"，新版 home-manager 的 dotDir 默认值
    # 已经变成 ~/.config/zsh。这里显式按回家目录：~/.zshrc 是所有外部工具
    # （包括 AI 助手）默认会去找的位置，换成 XDG 路径要靠 ZDOTDIR 转接，
    # 多一层可能出错的环节，不值得。
    dotDir = config.home.homeDirectory;

    autosuggestion.enable = true;

    syntaxHighlighting = {
      enable = true;

      #   main      命令是否存在、参数、引号、重定向的基础着色。默认就只有它。
      #   brackets  括号 / 引号配对着色，落单的一律标红。
      #             写长 nix 表达式和嵌套 shell 命令时，少一个 } 或 )
      #             当场就能看见，不用等 zsh 报 parse error。
      #   cursor    高亮光标所在的那个词，长命令里定位用。
      #
      # **数组顺序有含义**：zsh-syntax-highlighting 按顺序依次跑，后面的
      # highlighter 覆盖前面的对同一段文本的着色。上游文档因此要求
      # cursor 排在最后，否则它加的高亮会被 main 压掉。
      #
      # mkForce 是必须的，不是偷懒。home-manager 的 zsh 模块在 config 段里
      # 无条件追加一条 `highlighters = [ "main" ]`（普通优先级），列表选项
      # 又是合并而非覆盖，所以直接写 [ "brackets" "cursor" ] 的结果是
      # `ZSH_HIGHLIGHT_HIGHLIGHTERS=(brackets cursor main)` —— main 跑到了
      # 最后，正好把 cursor 压掉。已在 /tmp/hm/home-files/.zshrc 里实测确认。
      # mkForce 丢掉模块那条定义，顺序才完全由这里说了算。
      highlighters = lib.mkForce [
        "main"
        "brackets"
        "cursor"
      ];

      # ============================================
      # 配色：手写，因为 stylix 没有这个 target
      # ============================================
      # stylix 的 106 个 target 里没有 zsh 也没有 zsh-syntax-highlighting，
      # 所以这一份要自己写。但这不是绕开 stylix ——
      # 颜色全部取自 config.lib.stylix.colors，改 base16 方案时
      # 这里自动跟着变，单一真相仍然成立。
      #
      # 顺带说明：stylix 自己那 106 个 target 内部就是这种「把 base16
      # 色号映射到各程序配置键」的表，比如 fish 那个 target 总共才十行。
      # 所以手写这一份和 stylix 做的事是同构的，只是写在本仓库里。
      #
      # 为什么值得写（终端调色板已经是 gruvbox 了，不写也不会太离谱）：
      #
      #   1. comment 的插件默认值是 fg=black,bold，而 gruvbox 的
      #      color0 正是背景色 #1d2021 本身 —— 注释可能直接看不见。
      #      改成 base03 才有对比度。这一条是真 bug 级的。
      #   2. ANSI 只有 16 色，表达不了 base09（橙）和 base0F（棕）。
      #      写死 hex 才能用满整套 base16。
      #   3. 从别的机器 ssh 过来、或者掉进 TTY 时，终端调色板不是
      #      gruvbox，只有写死 hex 才还是这套颜色。
      #
      # 本机 COLORTERM=truecolor，fg=#RRGGBB 这种真彩色写法可用。
      #
      # 没列出的 key 保持插件默认值，不是遗漏 —— 那些要么很少出现，
      # 要么默认值本来就合理。
      styles =
        let
          c = config.lib.stylix.colors;
        in
        {
          # --- 出错：最该一眼看见的 ---
          unknown-token = "fg=#${c.base08},bold"; # 命令不存在
          bracket-error = "fg=#${c.base08},bold"; # 括号不配对

          # --- 能跑的东西：统一用绿，和「出错的红」成对 ---
          command = "fg=#${c.base0B}";
          hashed-command = "fg=#${c.base0B}";
          alias = "fg=#${c.base0B}";
          suffix-alias = "fg=#${c.base0B},underline";
          global-alias = "fg=#${c.base0B}";
          precommand = "fg=#${c.base0B},underline"; # sudo / command / nohup
          autodirectory = "fg=#${c.base0B},underline";
          arg0 = "fg=#${c.base0B}";

          # --- shell 自己的东西：用蓝，和外部命令区分开 ---
          builtin = "fg=#${c.base0D}";
          function = "fg=#${c.base0D}";
          reserved-word = "fg=#${c.base0E}"; # if / for / while，base16 里紫是关键字

          # --- 字符串：黄。刻意不用绿，否则和「能跑的命令」撞色 ---
          single-quoted-argument = "fg=#${c.base0A}";
          double-quoted-argument = "fg=#${c.base0A}";
          dollar-quoted-argument = "fg=#${c.base0A}";
          rc-quote = "fg=#${c.base0A}";

          # --- 字符串里的插值/转义：青，从黄色底子里跳出来 ---
          dollar-double-quoted-argument = "fg=#${c.base0C}";
          back-double-quoted-argument = "fg=#${c.base0C}";
          back-dollar-quoted-argument = "fg=#${c.base0C}";
          globbing = "fg=#${c.base0C}"; # * ? [
          history-expansion = "fg=#${c.base0C}"; # !

          # --- 命令替换 / 进程替换的定界符：紫 ---
          command-substitution-delimiter = "fg=#${c.base0E}";
          process-substitution-delimiter = "fg=#${c.base0E}";
          back-quoted-argument-delimiter = "fg=#${c.base0E}";

          # --- 选项和重定向：橙。这是 ANSI 16 色给不了的那个颜色 ---
          single-hyphen-option = "fg=#${c.base09}";
          double-hyphen-option = "fg=#${c.base09}";
          redirection = "fg=#${c.base09}";
          named-fd = "fg=#${c.base09}";
          numeric-fd = "fg=#${c.base09}";

          # --- 其余 ---
          path = "fg=#${c.base05},underline";
          comment = "fg=#${c.base03}"; # 见上面第 1 条
          assign = "fg=#${c.base05}";
          default = "fg=#${c.base05}";

          # --- brackets highlighter：按嵌套层级轮转，落单的用上面的红 ---
          bracket-level-1 = "fg=#${c.base0D}";
          bracket-level-2 = "fg=#${c.base0B}";
          bracket-level-3 = "fg=#${c.base0E}";
          bracket-level-4 = "fg=#${c.base0A}";
          bracket-level-5 = "fg=#${c.base0C}";

          # --- cursor highlighter：用反显而不是具体颜色，
          #     这样任何 base16 方案下都一定看得见 ---
          cursor = "standout";
          cursor-matchingbracket = "standout";
        };
    };

    # 这里刻意**没有** historySubstringSearch.enable。
    # 它会 bindkey ↑/↓ 到 zsh-history-substring-search，和 atuin 抢同两个键，
    # 而且功能是 atuin 的真子集：它只对 ~/.zsh_history 做子串匹配，
    # 而 atuin 查的是 sqlite 库，带目录、退出码、耗时、时间戳。
    # 见下面 programs.atuin 一节。

    history = {
      size = 100000;
      save = 100000;
      extended = true; # 历史里带时间戳
      ignoreSpace = true; # 空格开头的命令不入历史（临时粘 token 时用得上）
      expireDuplicatesFirst = true;
    };

    shellAliases = commonAliases;
  };

  # bash 不再是登录 shell，但仍然要能用，而且行为要和 zsh 一致。
  programs.bash = {
    enable = true;
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    historySize = 100000;
    historyFileSize = 100000;
    shellAliases = commonAliases;
  };

  # ============================================
  # atuin —— 命令历史（取代 zsh 自带的历史检索）
  # ============================================
  # 把历史记进一个 sqlite 库，每条带上：执行目录、退出码、耗时、时间戳、
  # 会话 id。所以能做到 zsh 原生历史做不到的事，比如「只看我在这个目录里
  # 跑过什么」「只看成功过的命令」。
  #
  # 按键分工（重叠的部分已经在别处关掉了，不重复安装同类功能）：
  #   Ctrl+R  atuin 的全库搜索。fzf 也会绑这个键，但 atuin 在 .zshrc 里
  #           加载更晚，最终由 atuin 接管 —— 已核对生成的 .zshrc 确认。
  #   ↑       atuin 的历史检索。原先的 zsh-history-substring-search 已移除，
  #           它绑同样的键而功能是 atuin 的子集。
  #   Ctrl+T / Alt+C  仍归 fzf（文件 / 目录），和 atuin 不重叠，保留。
  #
  # 没有关掉 programs.zsh.history：zsh 仍然照常写 ~/.zsh_history。
  # 这是刻意的 —— 它是 atuin 的导入源，也是 atuin 万一出问题时的兜底。
  # 两者不冲突：atuin 换掉的只是**检索界面**，不是记录本身。
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    settings = {
      # 不联网。没有 atuin 账号时本来也不会同步，但显式关掉更稳 ——
      # 本机上行下行都很慢（实测 ~80 KiB/s），不需要后台再去抢带宽。
      auto_sync = false;

      # 版本由 nixpkgs 管，不需要 atuin 自己去查有没有新版。
      # 开着的话每次启动都要发一次网络请求，还会提示一个你没法用
      # `atuin update` 装的升级。
      update_check = false;
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = {
      add_newline = false;
      # 默认 500 ms。这台机器上大仓库的 git status 偶尔会超，
      # 超时的表现是提示符里的 git 段直接消失，容易误以为不在仓库里。
      command_timeout = 1000;
    };
  };

  # direnv：进项目目录自动加载 devShell。
  # nix-direnv 会为每个 .envrc 建立 GC root，否则 common.nix 里那个
  # 「每周 --delete-older-than 7d」的自动 GC 会把 devShell 清掉，
  # 下次进目录又要重新求值一遍。
  #
  # 两个 shell 的 hook 都挂上，别关任何一个：AI 助手用 bash 还是 zsh
  # 取决于它自己的实现，两边都挂才不会出现「只有我这边能进 devShell」。
  #
  # 注意：hook 只对**交互** shell 生效。非交互场景（`bash -c ...`）里
  # 要拿到 devShell 环境，得显式用 `direnv exec . <命令>`。
  # 这条已经写进 CLAUDE.md，供以后的 AI 会话参考。
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    # 注意：`fzf --zsh` 会绑 Ctrl+R（历史）、Ctrl+T（文件）、Alt+C（目录）三个键。
    # 其中 Ctrl+R 和 atuin 重叠，最终由后加载的 atuin 接管（已在生成的
    # .zshrc 里核对过顺序）。Ctrl+T / Alt+C 和 atuin 不重叠，保留。
    # home-manager 的 fzf 模块没有单独关掉某一个键位的选项，所以靠加载顺序解决。
    #
    # fd 由 modules/common.nix 提供
    defaultCommand = "fd --type f --hidden --exclude .git";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    # 刻意**不**加 options = [ "--cmd cd" ]。
    # 那会把 cd 换成 zoxide 的模糊跳转，人用着舒服，
    # 但脚本和 AI 写的 `cd ../foo` 就不再是标准 cd 语义了。
    # 模糊跳转用 z / zi，cd 保持原样。
  };

  programs.eza = {
    enable = true;
    # 见本节开头第 2 条：默认的 integration 会写 `ls = "eza"`，遮蔽标准 ls。
    # 需要的别名已经在 commonAliases 里用 ll / la / lt 另起了名字。
    enableZshIntegration = false;
    enableBashIntegration = false;
    # 不开 icons：本机装的是 Sarasa Mono J，不是 Nerd Font，
    # 开了只会得到一片豆腐块。要图标得先补一个 Nerd Font。
  };

  programs.bat = {
    enable = true;
    config = {
      # 这里刻意**没有** theme。配色由 stylix 统一注入（它会生成一套
      # 名为 base16-stylix 的 tmTheme 并设成默认），见 modules/stylix.nix。
      #
      # 原先这里写的是 theme = "gruvbox-dark"，和 stylix 的
      # config.theme = "base16-stylix" 都是普通赋值，两条同时存在
      # Nix 会直接报 conflicting definition values，不是静默取其一。
      style = "numbers,changes";
    };
  };

  programs.btop.enable = true;
  programs.lazygit.enable = true;

  # vivid 生成 LS_COLORS，让 eza 的文件着色也走 stylix 那套配色。
  # 主题名由 modules/stylix.nix 的 vivid target 注入，这里只管开关。
  #
  # shell 集成的实现是在 rc 里跑一次 export LS_COLORS="$(vivid generate ...)"，
  # 也就是每开一个终端多一次子进程。实测单次 < 10 ms，可以接受
  # （对比：zsh 的 compinit 是几百毫秒，那个才值得专门关掉）。
  programs.vivid = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  # ============================================
  # Ghostty —— 终端模拟器
  # ============================================
  # 换掉 GNOME 自带的 Console (kgx)。换的理由不是 kgx 不好用，
  # 而是**它没法被统一配色**：stylix 的 106 个 target 里没有 kgx、
  # gnome-console 或 gnome-terminal（那个叫 console 的 target 是
  # 内核 TTY，不是 GNOME Console）。kgx 只有 auto/night/day/hacker
  # 四个内置主题，自定义要走没有文档的 custom-liveries 字典。
  #
  # 终端的 16 色调色板决定了所有 CLI 工具实际显示成什么颜色，
  # 所以它是配色统一里最不能将就的一环。
  #
  # 配色和字体全部由 stylix 注入（见下面的 targets.ghostty），
  # 这里不写任何 theme / font-family，否则又是两处各说一遍。
  #
  # 桌面的「在终端中打开」指向哪个程序在 modules/desktop.nix，
  # 那是 NixOS 级的 xdg.terminal-exec，不在这一层。
  programs.ghostty = {
    enable = true;

    settings = {
      # 保留一屏以上的回滚历史。ghostty 默认是 10000，
      # 和之前 kgx 的 scrollback-lines 对齐，换终端不丢习惯。
      scrollback-limit = 10000000;

      # 关掉关闭确认弹窗。这台机器上终端开关很频繁，
      # 每次都要确认一下很碍事。
      confirm-close-surface = false;
    };
  };

  # ============================================
  # Stylix：哪些用户程序交给它着色
  # ============================================
  # 调色板本身（base16 方案、polarity、壁纸）在 modules/stylix.nix，
  # 会自动透传到这一层，所以这里**只写开关**，不重复写颜色。
  #
  # 这些 target 都是 home-manager 级的实现，必须写在这里；
  # 写进 modules/stylix.nix 会报 option does not exist。
  #
  # 这一批的共同点：程序本身上面已经用 programs.* 声明过，而且 stylix
  # 接管的只有配色，不碰任何行为选项，所以是纯增量、零冲突。
  stylix.targets = {
    bat.enable = true;
    starship.enable = true;
    fzf.enable = true;
    tmux.enable = true;
    btop.enable = true;
    lazygit.enable = true;
    vivid.enable = true;

    # ghostty 这一个和上面几个性质不同，值得单说：
    # 它注入的是**完整的 16 色 ANSI 调色板**（palette 0-15）。
    #
    # 这才是真正让配色统一的那一环。bat / starship / zsh 这些 CLI
    # 工具输出的都是 ANSI 色号（fg=red 就是 color1），色号最终渲染成
    # 什么 RGB 由终端的调色板决定。终端调色板不对的话，上面那些
    # target 就成了「用一个别的调色板去显示 gruvbox 的色号」，
    # 统一是假的。
    #
    # 顺带：这个 target 还会读 stylix.fonts.monospace 去设
    # ghostty 的 font-family，所以字体也在这一步被连带接管了，
    # 见 modules/localization.nix。
    ghostty.enable = true;

    # ============================================
    # 桌面本体：GTK / GNOME / Qt
    # ============================================
    # 到这一步为止接管的都是终端里的东西。下面三个管窗口和桌面，
    # 是「从终端到桌面」这条线上剩下的部分。
    #
    # 这三个在 modules/stylix.nix 里还各有一份 NixOS 侧的开关 ——
    # stylix.targets 不在自动透传清单里，两层必须各写一次。

    # gtk：把主题换成 adw-gtk3 并生成 gtk-3.0/gtk.css 与 gtk-4.0/gtk.css，
    # 同时用 stylix.fonts.sansSerif 设界面字体。
    gtk = {
      enable = true;

      # flatpakSupport 必须显式打开，**不能靠它自己的默认值**。
      # 它的默认写法是 mkEnableTarget "..." true，展开后是
      # `cfg.autoEnable && true` —— 而 modules/stylix.nix 里把
      # stylix.autoEnable 关掉了，于是这个子选项也跟着变成 false。
      # 也就是说「关掉总开关」会连带关掉各 target 的子功能，
      # 不只是 target 本身。这一点很容易漏，已实测确认过
      # （求值 stylix.targets.gtk.flatpakSupport.enable 得到 false）。
      #
      # 开了它会多生成一份 ~/.themes/adw-gtk3（把 CSS 直接烤进主题），
      # 并写 ~/.local/share/flatpak/overrides/global，让 Flatpak 应用
      # 也用这套主题。本机的微信、Betterbird、百度网盘、Flatseal
      # 都是 Flatpak 装的（见 modules/flatpak.nix），不开的话
      # 它们会是整个桌面里唯一不变色的一批窗口。
      #
      # 接管前确认过 ~/.local/share/flatpak/overrides/global 原本不存在，
      # 没有手动配置会被覆盖。以后若要用 Flatseal 调权限，注意那个
      # 文件已经归 home-manager 管，改动会在下次 switch 时被覆盖。
      flatpakSupport.enable = true;
    };

    # gnome：写 dconf 设壁纸、界面明暗（color-scheme，由 polarity 决定）
    # 和界面字体；另外自带一个 user-theme 扩展并在登录时自动启用，
    # 用来给 GNOME Shell 本身（顶栏、概览）套上同一套配色。
    # 不用手动往 desktop-gnome.nix 的扩展列表里加 user-themes。
    gnome.enable = true;

    # neovim：往 programs.neovim.plugins 加一个 Nix 管理的 mini.nvim，
    # 并在 init.lua 末尾调 require('mini.base16').setup({palette = ...})
    # 注入这套 base16 调色板。
    #
    # 和 lazy.nvim 的关系已经实测确认过，不冲突：
    # xdg.configFile."nvim/init.lua".text 的类型是 types.lines，
    # 多个定义**按行拼接**而不是报冲突，stylix 那段落在
    # require("config.lazy") 之后，所以它最后生效。
    neovim.enable = true;

    # neovide 的 target 刻意**不开**，这不是嫌麻烦，是踩过之后的决定。
    #
    # 它唯一做的事就是把字体写进 ~/.config/neovide/config.toml：
    #     [font]
    #     normal = ["Sarasa Mono J"]
    #     size = 12
    #
    # 开了之后 Neovide 会**间歇性地永远起不来**：进程在，窗口不出，
    # 一个 CPU 核跑满 99.5%，内存平在 187MB 不涨（说明是死循环不是慢计算）。
    # journal 里留下过 13 分 21 秒和 19 分 7 秒两条满载记录，
    # 而同一次启动里另一个实例只用了 19 秒就正常了 —— 所以是竞态，
    # 不是每次必现。用回退前的构建 + 只手工放这份 config.toml
    # 也能复现（实测转满 150 秒无进展），确认了变量就是它。
    #
    # 因为复现不稳定，没法证明「改个写法就好了」，所以直接绕开这条路径：
    # 下面 init.lua 里用 vim.opt.guifont 设字体。那是本机用了几个月
    # 的老办法，从没出过这个问题。
    #
    # 配色不受影响：Neovide 渲染的就是 Neovim 的颜色，
    # 上面 neovim.enable 那条已经覆盖，这里丢掉的只有字体和不透明度。

    # vscode：生成一套名为 Stylix 的主题扩展（以
    # ~/.vscode/extensions/stylix.stylix 的形式链进去），并把
    # workbench.colorTheme 设成它；同时用 stylix.fonts 设编辑器、
    # 终端、markdown 预览等一系列字体和字号。
    #
    # 前提是上面的 programs.vscode 声明 —— 裸包它管不到。
    vscode.enable = true;

    # qt 刻意**不开**。理由是实测下来性价比为负：
    #
    # platform 这个选项会从 NixOS 层透传过来（它是少数几个在透传清单里的
    # target 子选项之一），在 GNOME 上取到 "gnome"。而 stylix 只支持
    # "qtct"，开了会直接报两条 evaluation warning：
    #
    #   stylix: qt: `platform` other than 'qtct' are currently unsupported: gnome
    #   The value `gnome` for option `qt.platformTheme.name` is deprecated
    #
    # 也就是说配色根本没注入，只留下警告。
    #
    # 要让它真的生效得设 platform = "qtct"，代价是引入 qt5ct/qt6ct +
    # kvantum，而 stylix 自己的源码里就注释着 kvantum 有个会让
    # systemd 出问题的上游 bug（home-manager#6565）。
    #
    # 而这台机器上唯一的 Qt 图形程序是 fcitx5-config-qt（输入法设置，
    # 极少打开）—— Obsidian 是 Electron 不是 Qt。为一个偶尔打开的
    # 配置对话框引入 kvantum 不划算。以后真装了 Qt 应用再回来开。
  };

  # ============================================
  # 修掉 stylix GNOME 主题的首次激活失败
  # ============================================
  # 症状：首次 switch 时 home-manager 激活失败，
  #
  #     Activating onFilesChange
  #     Extension "user-theme@..." does not exist
  #     home-manager-toru.service: Main process exited, status=2
  #
  # 原因是鸡生蛋：stylix 给 gnome-shell.css 挂了个 onChange 钩子去
  # `gnome-extensions disable/enable` 那个扩展，但扩展是这次 switch 才
  # 装进 profile 的，**正在运行的 GNOME Shell 只在启动时扫描扩展目录**，
  # 所以此刻它还不认识这个 UUID。stylix 的脚本用 writeShellApplication
  # 生成（自带 set -euo pipefail），disable 一失败整个激活就退出。
  #
  # 影响不只是难看：systemd 会重试，第二次因为文件没再变所以能过，
  # 于是 nrb/nrt 报失败但系统其实是好的 —— 这种「假失败」比真失败更糟，
  # 会训练人忽略 switch 的报错（CLAUDE.md 坑 4 反复强调要把输出看到底）。
  # 而且这是个多机仓库，每台新机器第一次 switch 都会撞上。
  #
  # 解法不是关掉自动 reload —— 那个钩子在将来做多主题切换时正是需要的
  # （换主题后不用注销就能让 Shell 吃到新配色）。这里只是加一道守卫：
  # 先问运行中的 Shell 认不认识这个扩展，不认识就跳过。
  # 注销重登之后它就认识了，钩子照常工作。
  xdg.dataFile."themes/Stylix/gnome-shell/gnome-shell.css".onChange = lib.mkForce ''
    uuid='user-theme@gnome-shell-extensions.gcampax.github.com'
    gx=/run/current-system/sw/bin/gnome-extensions
    if [ -x "$gx" ] && "$gx" list 2>/dev/null | grep -qx "$uuid"; then
      "$gx" disable "$uuid" || true
      "$gx" enable "$uuid" || true
    fi
  '';

  # 注：firefox 的 target 刻意**不**在这一阶段开。
  # 它要求 stylix.targets.firefox.profileNames 指定 profile 名，
  # 而一旦指定，home-manager 就会接管那个 Firefox profile 的 settings，
  # 有覆盖现有浏览器配置的风险 —— 这不属于「零冲突」，留到后面单独处理。
  # 不设 profileNames 时 stylix 只会发一条 warning，不会报错。

  # ============================================
  # Vitals Widget 扩展的配色：手写，stylix 没有这个 target
  # ============================================
  # 和 zsh-syntax-highlighting 那份一样，是手写但**不脱离** stylix ——
  # 颜色全部取自 config.lib.stylix.colors。而且因为写在 dconf.settings
  # 里（home 层），它会跟着 specialisation 一起切，换主题时环的颜色
  # 自动跟着变。
  #
  # 键名和取值格式是读扩展源码确认的，不是猜的：
  #   schema path  /org/gnome/shell/extensions/vitalswidget/
  #   五个指标各有独立的 <name>-color 键，类型都是字符串
  #   ring.js 的 _parseColor 支持 #rrggbb、#rgb 和 rgb()/rgba()，
  #     其中只有 rgba() 这条路能带透明度
  #   background/border/icon 是直接插进 St 的 CSS
  #     （extension.js: `background-color: ${bgColor};`），
  #     所以同样可以用 rgba()
  #
  # 顺带修掉一个真问题：扩展默认的 border / icon / inactive-ring
  # 都是**白色**带透明度（rgba(255,255,255,...)），那是假设了深色背景。
  # 换到亮色主题（nier-automata、one-light 这些）上会几乎看不见。
  # 改成跟着调色板走之后两边都成立。
  dconf.settings."org/gnome/shell/extensions/vitalswidget" =
    let
      c = config.lib.stylix.colors;
      # ring.js 只认 rgb()/rgba() 这一种带透明度的写法（不认 8 位 hex），
      # 所以用 stylix 现成的 RGB 分量拼出来。
      rgba =
        base: alpha: "rgba(${c."${base}-rgb-r"}, ${c."${base}-rgb-g"}, ${c."${base}-rgb-b"}, ${alpha})";
    in
    {
      # 五个指标各用一个 base16 强调色。挑的是 base16 里彼此色相
      # 差得最开的五个，任何配色方案下都能一眼分辨：
      cpu-color = "#${c.base0D}"; # 蓝，主计算
      ram-color = "#${c.base0E}"; # 紫，内存
      storage-color = "#${c.base0B}"; # 绿，磁盘
      temp-color = "#${c.base09}"; # 橙，温度（语义上正好对上「热」）
      gpu-color = "#${c.base0C}"; # 青，图形

      # 环没走满的那一段。用 base03（注释色那一档），
      # 深浅两种主题下都是「比背景明显、又不抢眼」的灰。
      inactive-ring-color = rgba "base03" "0.25";

      # 控件本体。透明度沿用扩展原本的意图（背景半透、边框很淡），
      # 只把颜色换成跟着主题走。
      background-color = rgba "base00" "0.8";
      border-color = rgba "base03" "0.4";
      icon-color = rgba "base05" "0.9";

      # 下面这些是布局和行为，和配色无关，但同属这个扩展所以放一起。
      # 原先只活在 ~/.config/dconf 里，换机器不跟过去。
      # position-x / position-y 是面板上的百分比位置，
      # 在不同宽度的屏幕上仍然成立，所以可以当通用值搬。
      enable-popups = true;
      label-font-size = 11;
      orientation = "horizontal";
      vital-orientation = "vertical";
      position-x = 82.0;
      position-y = 2.0;
      ring-diameter = 48;
      show-labels = true;
      show-rings = true;
    };

  # ============================================
  # GNOME 的其余 dconf 设置
  # ============================================
  # 原先这些只活在 ~/.config/dconf 里 —— 换台机器全部丢失，
  # 属于 MIGRATION.md 第 0 节说的「其实该进 Nix 却没进」那一类。
  #
  # **刻意只收下面这些，不是整份 dconf dump。** 被排除的和理由：
  #
  #   org/gnome/desktop/interface、.../background
  #       stylix 在管（stylix.targets.gnome.enable），声明了会打架
  #   shell/extensions/user-theme
  #       由下面那段 home.activation 管（它要等扩展装好才能设）
  #   shell/app-picker-layout
  #       几百项的位置索引，加个应用就变，搬过去毫无意义
  #   shell/extensions/burn-my-windows
  #       active-profile 指向 ~/.config/burn-my-windows/profiles/<时间戳>.conf，
  #       是本机路径；其余键（last-*-version、prefs-open-count）是运行状态
  #   shell/extensions/dash-to-panel
  #       panel-* 全是空的 '{}' 默认值，extension-version / prefs-opened 是状态
  #   shell/extensions/appindicator
  #       这个扩展在 disabled-extensions 里，设了也没人读
  #   shell/welcome-dialog-last-shown-version、各种 window-state
  #       纯状态
  dconf.settings = {
    "org/gnome/shell" = {
      # 注意这里**不是** dconf dump 的原样照抄：原来的列表里还有一个
      # gnome-shell-screenshot@ttll.de，但那个扩展根本没装
      # （gnome-extensions list 里看不到它），是以前用 Extension Manager
      # 装了又删留下的死 UUID。GNOME 对不认识的 UUID 静默忽略，
      # 所以平时看不出来。照抄会把这个垃圾一起搬到新机器上。
      enabled-extensions = [
        "apps-menu@gnome-shell-extensions.gcampax.github.com"
        "burn-my-windows@schneegans.github.com"
        "color-picker@tuberry"
        "dash-to-panel@jderose9.github.com"
        "draw-on-gnome@daveprowse.github.io"
        "gTile@vibou"
        "kimpanel@kde.org"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "vitalsWidget@ctrln3rd.github.com"
      ];

      disabled-extensions = [ "appindicatorsupport@rgcjonas.gmail.com" ];

      favorite-apps = [
        "code.desktop"
        "neovide.desktop"
        "org.gnome.Nautilus.desktop"
        "firefox.desktop"
        "org.gnome.TextEditor.desktop"
        "com.mitchellh.ghostty.desktop"
      ];
    };

    # 窗口按钮布局。**从 modules/desktop-gnome.nix 的系统层挪过来的** ——
    # 按钮放左还是放右是用户偏好，跟着人走不跟着机器走，
    # 按仓库判据属于 home 层。挪过来之后系统层不再有任何 dconf 声明，
    # 只剩 programs.dconf.enable，单一真相。
    "org/gnome/desktop/wm/preferences".button-layout = "close,minimize,maximize:";

    # 输入法面板。
    #
    # font 的值是 **Pango 字体描述**，不是 fontconfig 族名 ——
    # Pango 会把它拆成 族名「Sarasa Fixed CL」+ 权重 ultralight + 字号 11。
    # 所以**不要拿 `fc-match "Sarasa Fixed CL Ultra-Light"` 去验证它**，
    # 那样整串会被当成族名，必然匹配失败、让人以为踩了坑 1。
    # 正确的验证是分开查：`fc-match "Sarasa Fixed CL"` 和
    # `fc-match "Sarasa Fixed CL:weight=extralight"`，两个都命中才对。
    #
    # 这里用 CL（中文）而系统等宽用 J（日文），是有意的：
    # 这个面板显示的是拼音候选词。
    "org/gnome/shell/extensions/kimpanel" = {
      font = "Sarasa Fixed CL Ultra-Light 11";
      vertical = true;
    };

    "org/gnome/shell/extensions/color-picker" = {
      enable-format = true;
      enable-notify = false;
      enable-shortcut = true;
      persistent-mode = true;
      preview-style = 0;
    };

    # 画板的调色板。九个颜色是手挑的，重配一遍很烦，值得搬。
    # 格式是 GVariant 的 (String, Array of String)，
    # home-manager 的 dconf 模块要用 lib.gvariant 显式构造 ——
    # 直接写 Nix 列表会被当成 'as' 而丢掉外层的 tuple。
    "org/gnome/shell/extensions/draw-on-gnome/drawing".tool-palette = lib.gvariant.mkTuple [
      "Palette"
      [
        "rgb(255,105,180):HotPink"
        "rgb(0,255,255):Cyan"
        "rgb(255,255,0):yellow"
        "rgb(255,69,0):Orangered"
        "rgb(127,255,0):Chartreuse"
        "rgb(148,0,211):DarkViolet"
        "rgb(255,255,255):White"
        "rgb(190,190,190):Gray"
        "rgb(0,0,0):Black"
      ]
    ];
  };

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    escapeTime = 10; # 默认 500 ms，会让 tmux 里的 vim 按 Esc 有明显延迟
    historyLimit = 50000;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";
  };

  # 没有对应 programs.* 模块、直接装二进制的那几个。
  # 注意：git / ripgrep / fd / jq / htop / tree 已经在 modules/common.nix 的
  # systemPackages 里了，不要在这里再装一份 —— 见 CLAUDE.md 的坑 3。
  # 尤其是 git：root 跑 `nixos-rebuild --flake` 时需要它，
  # 必须留在系统层 —— 但那**不妨碍**这里启用 programs.git，见下面那段。
  home.packages = with pkgs; [
    dua # 交互式磁盘占用分析（Omarchy 4 的默认选择）
    duf # 挂载点/剩余空间一览

    # 主题切换命令。定义在文件开头的 let 里，
    # 说明见上面「theme —— 主题切换命令」那一段。
    themeSwitcher
  ];

  # ============================================
  # Claude Code 的键位
  # ============================================
  # 只有键位进 Nix，**同目录的 settings.json 不进** —— 判据是
  # 「谁在写这个文件」：
  #
  #   keybindings.json   手写的，Claude Code 运行时不碰    -> A 类，声明式
  #   settings.json      /model、/effort、/config 都在改它  -> B 类，dotfiles-state
  #
  # 写成只读符号链接不影响键位（本来就没人改它），但会让 /model 和
  # /effort 直接失效 —— 所以两个文件分开处理，不是按目录一刀切。
  #
  # home-manager 没有 programs.claude-code 模块，而 ~/.claude 不在
  # XDG 路径下，所以用 home.file 而不是 xdg.configFile。
  #
  # Ctrl+Enter 和 Alt+Enter 都发送，Enter 留给换行 ——
  # 和 VS Code 那边 claudeCode.useCtrlEnterToSend = true 是同一套手感。
  home.file.".claude/keybindings.json".text = builtins.toJSON {
    "$schema" = "https://www.schemastore.org/claude-code-keybindings.json";
    "$docs" = "https://code.claude.com/docs/en/keybindings";
    bindings = [
      {
        context = "Chat";
        bindings = {
          "ctrl+enter" = "chat:submit";
          "alt+enter" = "chat:submit";
        };
      }
    ];
  };

  # ============================================
  # Git
  # ============================================
  # 之前 ~/.gitconfig 是仓库外的一个手写文件，有两个问题：
  #
  #   1. 换机器完全不跟过去（A 类漏网，见 MIGRATION.md 第 0 节）
  #   2. 更要命的是它里面**钉死了一个 store 绝对路径**：
  #        helper = !/nix/store/3s30bx…-gh-2.99.0/bin/.gh-wrapped auth git-credential
  #      那是当时 gh 的版本。nix.gc 每周删 7 天前的东西，那个路径迟早消失，
  #      届时凡走 HTTPS 的 git 操作都会在凭据助手上失败。
  #      症状还很隐蔽：SSH remote 不经凭据助手，平时完全看不出来。
  #
  # 现在写成 ${pkgs.gh}/bin/gh，跟着 store 走，GC 也动不了它
  # （home-manager 的 generation 引用着它）。
  #
  # 关于「git 必须留在系统层」那条：成立，root 跑 nixos-rebuild --flake
  # 时要用。但它**不妨碍**这里同时启用 programs.git ——
  # 坑 3 说的是 nvim/vim 那种「两个不同派生」的情况（一个带 extraPackages
  # 一个不带），而这里两边解析到的是**同一个 store path**
  # （useGlobalPkgs = true，HM 的 programs.git.package 默认就是 pkgs.git）。
  # 实测确认过：系统层和 home 层都是 …-git-2.54.0。
  # 改动这里之前请重新确认一次，别默认它永远成立。
  programs.git = {
    enable = true;

    # 全局 gitignore。原先在 ~/.config/git/ignore 这个仓库外的手写文件里，
    # 是 migration-check 第一次跑就抓出来的漏网之鱼。
    # Claude Code 的本地设置文件不该进任何项目的版本库。
    ignores = [ "**/.claude/settings.local.json" ];

    # 用 settings 而不是 userName / userEmail / extraConfig ——
    # 这个 home-manager 版本已经把那三个改名了，继续用会在每次构建时
    # 打弃用警告（`nrb` 的输出里多两行噪音，久了就没人看警告了）。
    settings = {
      user.name = "SenorToru";
      user.email = "dev@toru-leathers.com";

      pull.rebase = false;

      # 空字符串那一项是 gh 自己的写法：先清空 helper 列表再追加，
      # 避免和系统级 gitconfig 里可能存在的 helper 叠加。
      credential = {
        "https://github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };
    };
  };

  # ============================================
  # Neovim 配置 (HomeManager)
  # ============================================
  # 注 1：插件由 lazy.nvim 独立管理，不通过 HomeManager。
  # 注 2：这是全系统**唯一**的 neovim 声明处。modules/development.nix 里
  #       曾经还有一份系统级 programs.neovim，导致 vim / vi 指向另一个不带
  #       extraPackages 的 neovim，Copilot 在那个 neovim 下必然离线。
  #       别再把 programs.neovim 加回 development.nix。
  # Neovide —— Neovim 的图形前端。
  #
  # 从 modules/development.nix 的 systemPackages 挪到这里，理由是坑 3：
  # stylix 的 neovide target 是往 programs.neovide.settings 写配置的，
  # 要用它就必须有这个 home-manager 声明；而如果系统层再装一份裸包，
  # Nix 不报冲突但会装出两个 neovide，PATH 上谁赢取决于顺序 ——
  # 和当初 nvim / vim 指向两个不同派生是同一类问题。
  #
  # 配色不用在这里管：Neovide 渲染的就是 Neovim 的颜色，
  # 上面 stylix.targets.neovim 已经覆盖。这里 stylix 只注入字体和不透明度。
  programs.neovide.enable = true;

  # ============================================
  # VSCode
  # ============================================
  # 从 modules/development.nix 的 systemPackages 挪过来。必须挪：
  # stylix 的 vscode target 是往 programs.vscode.profiles.<名字> 写
  # 主题扩展和 userSettings 的，裸包它管不到（和 neovide 同一个道理）。
  #
  # 扩展不会丢，这一点确认过实现再动手的：
  #   mutableExtensionsDir 的默认值是「只用 default profile 时为 true」，
  #   而这里只用 default。在这个分支下 home-manager 是把声明的扩展
  #   **逐个符号链接**进 ~/.vscode/extensions/<id>，不替换整个目录，
  #   所以手动装的那几个（claude-code / nix-ide / nixfmt-vscode /
  #   markdown-preview-enhanced）原样保留，stylix 的主题只是多出来一个
  #   ~/.vscode/extensions/stylix.stylix。
  #
  # **需要知道的行为变化：settings.json 从此是指向 store 的只读符号链接。**
  # VSCode 图形界面里改设置将无法保存，要改就改下面这段再 rebuild。
  # 这和本仓库其它部分的做法一致，但 VSCode 是唯一一个平时会顺手在 GUI
  # 里改配置的程序，所以单独点出来。
  # 原来那份会被备份成 settings.json.hm-bak（backupFileExtension，见 000B）。
  programs.vscode = {
    enable = true;

    # 下面这些键是从原来的 ~/.config/Code/User/settings.json 逐条搬过来的，
    # 值一个没改。原文件里的注释也一并搬成了 Nix 注释 ——
    # 生成的 JSON 不能带注释，留在这里反而比原来更该待的地方。
    profiles.default.userSettings = {
      "[nix]" = {
        "editor.defaultFormatter" = "jnoortheen.nix-ide";
        "editor.formatOnSave" = true;
      };

      "explorer.confirmDelete" = false;
      "explorer.confirmDragAndDrop" = false;

      "chat.tools.terminal.autoApprove" = {
        nix = true;
      };

      "markdown-preview-enhanced.previewTheme" = "newsprint.css";
      "markdown-preview-enhanced.codeBlockTheme" = "auto.css";
      "markdown-preview-enhanced.revealjsTheme" = "solarized.css";

      "claudeCode.preferredLocation" = "panel";

      # Claude Code：用 Ctrl+Enter 发送指令，Enter 改为插入换行
      "claudeCode.useCtrlEnterToSend" = true;

      # 聊天面板正文字号（VSCode 默认 13，范围 6-100）。
      # 这一个键同时作用于 Claude Code 面板和内置的 GitHub Copilot Chat。
      #
      # 注意它和 stylix 注入的字号是两回事，不冲突：
      # stylix 设的是 editor.fontSize / terminal.integrated.fontSize 等，
      # 都取自 stylix.fonts.sizes.terminal，没有 chat.fontSize 这一个键。
      "chat.fontSize" = 16;
    };
  };

  programs.neovim = {
    enable = true;

    # 以下三项从 development.nix 迁移过来，确保 nvim / vim / vi / $EDITOR
    # 全部指向这一个带 extraPackages 的 neovim。
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    extraPackages = with pkgs; [
      # 格式化和 linting
      nixfmt
      nil

      # Node.js (Copilot 需要)
      nodejs_24

      # GitHub CLI (Copilot 认证)
      # 如果仅使用 VSCode 认证，可注释掉此行
      github-cli

      # Copilot 语言服务器需要 unzip
      unzip

      # 其他 LSP 依赖
      lua-language-server

      # Claude Code CLI
      # claudecode.nvim 是从 Neovim 内部 spawn `claude` 的，所以必须放进
      # extraPackages（nvim 的 wrapper PATH），只装进 systemPackages 不够。
      claude-code
    ];
  };

  # Neovim 配置文件 (通过 xdg.configFile 管理)
  xdg.configFile = {
    "nvim/init.lua" = {
      text = ''
        -- ============================================
        -- Neovim 初始化配置 (由 HomeManager 管理)
        -- ============================================

        -- 设置 <leader> 键
        vim.g.mapleader = " "
        vim.g.maplocalleader = " "

        -- 基础选项
        vim.opt.tabstop = 2
        vim.opt.softtabstop = 2
        vim.opt.shiftwidth = 2
        vim.opt.expandtab = true
        vim.opt.autoindent = true
        vim.opt.smartindent = true
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.opt.wrap = false
        vim.opt.signcolumn = "yes"

        -- Neovide 特定配置
        --
        -- 字体走 guifont 而**不是** Neovide 自己的 config.toml。
        -- 后者会让 Neovide 间歇性死循环（起不来、一个核 99.5%），
        -- 详见上面 stylix.targets 里 neovide 那段的记录。
        --
        -- 但族名和字号不是手写死的，是从 stylix 的字体设置插值进来的，
        -- 所以仍然只有一处真相：改 modules/localization.nix 里的
        -- stylix.fonts.monospace，这里自动跟着变。
        if vim.g.neovide then
          vim.opt.guifont = "${config.stylix.fonts.monospace.name}:h${toString config.stylix.fonts.sizes.terminal}"
          vim.g.neovide_cursor_animation_length = 0.13
          vim.g.neovide_cursor_trail_size = 0.8
        end

        -- 加载 lazy.nvim 配置
        require("config.lazy")
      '';
    };

    "nvim/lua/config/lazy.lua" = {
      text = ''
        -- ============================================
        -- Lazy.nvim 插件管理器配置
        -- ============================================

        local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
        if not (vim.uv or vim.loop).fs_stat(lazypath) then
          vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath,
          })
        end
        vim.opt.rtp:prepend(lazypath)

        require("lazy").setup({
          spec = {
            { import = "plugins" },
          },
          -- 禁用启动时的更新检查提示，避免交互式提示
          checker = { enabled = false },

          performance = {
            -- **这一项不能省，而且容易设错。**
            --
            -- home-manager 装 programs.neovim.plugins 里的插件时，不走
            -- wrapper 参数，而是把它们链到
            --     ~/.local/share/nvim/site/pack/hm/start/<插件>
            -- 靠 packpath 默认包含 $XDG_DATA_HOME/nvim/site 被找到。
            --
            -- 而 lazy.nvim 默认 reset_packpath = true，启动时直接
            --     vim.go.packpath = vim.env.VIMRUNTIME
            -- （见 lazy.nvim 的 lua/lazy/core/config.lua:295）
            -- 一句话把整个 packpath 清成只剩 runtime 自己，
            -- 于是 **Nix 装的插件全部消失**。症状是启动时报
            --     E5113: module 'mini.base16' not found
            -- 而那个文件明明存在于上面那个路径下。
            --
            -- mini.base16 是 stylix 的 neovim target 注入配色用的
            -- （它往 programs.neovim.plugins 加 Nix 管理的 mini.nvim，
            -- 再在 init.lua 末尾 require 它）。lazy 在第 33 行清掉
            -- packpath，stylix 的 require 在第 41 行，正好被打掉。
            --
            -- 注意**不是** performance.rtp.reset。那是另一个独立开关，
            -- 只管 runtimepath。实测四种组合：
            --     默认                        失败
            --     rtp.reset = false           仍然失败
            --     reset_packpath = false      成功
            --     两个都关                    成功
            -- 所以这里只关 reset_packpath，rtp.reset 保持默认的 true，
            -- 它那部分启动优化没必要一起丢掉。
            --
            -- 这是通用规则，不只为 mini.base16：**只要这个仓库用
            -- lazy.nvim，任何经 programs.neovim.plugins 装的插件都需要
            -- 它**。以后再加 Nix 管理的插件不用重新踩一遍。
            reset_packpath = false,
          },

          git = {
            -- 默认 120 秒。本机上行/下行都很慢（实测 ~80 KiB/s），
            -- snacks.nvim 这种 1.3 万对象的仓库根本装不完就被杀。
            timeout = 600,

            -- 默认 true，即用 `git clone --filter=blob:none` 做**部分克隆**：
            -- 初次只拉 commit 和 tree，blob 留到 checkout 时按需从网络取。
            -- 正常网速下这是优化，慢网下却是灾难 —— checkout 变成第二次
            -- 网络往返，一旦中断就留下「clone 成功但工作区是空的」目录，
            -- 报错写作 "Clone succeeded, but checkout failed"。
            -- 关掉它改为完整克隆：一次把所有对象拉全，checkout 纯本地操作，
            -- 代价是初次下载量变大，换来的是可靠。
            filter = false,
          },
        })
      '';
    };

    "nvim/lua/plugins/copilot.lua" = {
      text = ''
        -- ============================================
        -- GitHub Copilot 配置 (copilot.lua)
        -- ============================================
        -- 注意：不要再加 copilot-cmp。
        --   1. copilot-cmp 已停止维护（最后提交 2024-12），内部使用
        --      client.is_stopped()，在 Neovim 0.11+ 已废弃，启动时会报
        --      "client.is_stopped is deprecated"。
        --   2. copilot-cmp 要求关闭 suggestion / panel 模块，与下面的
        --      行内建议（ghost text）冲突。
        -- 现在统一使用 copilot.lua 自带的 suggestion 模块。

        return {
          {
            "zbirenbaum/copilot.lua",
            lazy = false,
            config = function()
              require("copilot").setup({
                -- Node.js 路径（由 home.nix 的 extraPackages 提供）
                copilot_node_command = "node",

                -- 行内建议（ghost text）
                suggestion = {
                  enabled = true,
                  auto_trigger = true,
                  -- nvim-cmp 菜单打开时自动隐藏 ghost text，避免两者重叠
                  hide_during_completion = true,
                  debounce = 75,
                  keymap = {
                    accept = "<M-l>",
                    accept_word = false,
                    accept_line = false,
                    next = "<M-]>",
                    prev = "<M-[>",
                    dismiss = "<C-]>",
                  },
                },

                -- 面板配置
                -- 关键修复：copilot.lua 默认会注册一个**全局 insert 模式**映射
                -- <M-CR> (Alt+Enter) 来打开面板。面板 buffer 是 modifiable=false
                -- 且会抢走焦点，所以在 Neovide 里一旦误触，之后每次输入都会得到
                -- "E21: Cannot make changes, 'modifiable' is off"。
                -- 在终端里 Alt+Enter 通常被拆成 <Esc><CR> 所以不会触发，
                -- GUI（Neovide）里才是真正的 <M-CR>，这就是只在 Neovide 复现的原因。
                -- 设为 false 关掉该全局映射；仍可用 :Copilot panel open 手动打开。
                panel = {
                  enabled = true,
                  auto_refresh = false,
                  keymap = {
                    jump_prev = "[[",
                    jump_next = "]]",
                    accept = "<CR>",
                    refresh = "gr",
                    open = false,
                  },
                },

                -- 文件类型配置
                filetypes = {
                  yaml = true,
                  markdown = true,
                  help = false,
                  gitcommit = false,
                  gitrebase = false,
                  hgcommit = false,
                  svn = false,
                  cvs = false,
                  ["."] = false,
                  nix = true,
                },
              })
            end,
          },
        }
      '';
    };

    "nvim/lua/plugins/formatting.lua" = {
      text = ''
        -- ============================================
        -- 代码格式化配置 (LSP 和 nil)
        -- ============================================

        return {
          {
            "neovim/nvim-lspconfig",
            event = { "BufReadPre", "BufNewFile" },
            config = function()
              local capabilities = vim.lsp.protocol.make_client_capabilities()
              capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

              -- Nix Language Server (nil) - 使用新的 vim.lsp API
              local nil_cmd = { "nil" }
              
              -- 启动 nil_ls 服务器
              local function setup_nil()
                local root_dir = vim.fs.dirname(
                  vim.fs.find({ "flake.nix", ".git" }, { upward = true })[1]
                )
                
                local client_id = vim.lsp.start({
                  name = "nil",
                  cmd = nil_cmd,
                  root_dir = root_dir,
                  capabilities = capabilities,
                  settings = {
                    ["nil"] = {
                      formatting = {
                        command = { "nixfmt" },
                      },
                    },
                  },
                })
              end

              -- 为 nix 文件设置 LSP
              vim.api.nvim_create_autocmd("FileType", {
                pattern = "nix",
                callback = setup_nil,
              })

              -- 设置 LSP 快捷键和格式化
              vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
                callback = function(ev)
                  local opts = { buffer = ev.buf }
                  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
                  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
                  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
                  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
                  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
                  vim.keymap.set("n", "<leader>f", function()
                    vim.lsp.buf.format({ async = true })
                  end, opts)
                end,
              })
            end,
            dependencies = {
              "nvim-cmp",
              "cmp-nvim-lsp",
            },
          },
        }
      '';
    };

    "nvim/lua/plugins/completion.lua" = {
      text = ''
        -- ============================================
        -- 自动补全配置 (nvim-cmp)
        -- ============================================

        return {
          {
            "hrsh7th/nvim-cmp",
            event = "InsertEnter",
            config = function()
              local cmp = require("cmp")

              cmp.setup({
                mapping = {
                  ["<C-b>"] = cmp.mapping(cmp.mapping.scroll_docs(-4), { "i", "c" }),
                  ["<C-f>"] = cmp.mapping(cmp.mapping.scroll_docs(4), { "i", "c" }),
                  ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "c" }),
                  ["<C-e>"] = cmp.mapping({
                    i = cmp.mapping.abort(),
                    c = cmp.mapping.close(),
                  }),
                  ["<CR>"] = cmp.mapping.confirm({ select = true }),
                },
                sources = cmp.config.sources({
                  { name = "nvim_lsp", priority = 9 },
                  { name = "buffer", priority = 5 },
                  { name = "path", priority = 3 },
                }),
              })

              -- 命令行补全
              cmp.setup.cmdline(":", {
                sources = cmp.config.sources({
                  { name = "path" },
                }, {
                  { name = "cmdline" },
                }),
              })
            end,
            dependencies = {
              "hrsh7th/cmp-nvim-lsp",
              "hrsh7th/cmp-buffer",
              "hrsh7th/cmp-path",
              "hrsh7th/cmp-cmdline",
            },
          },
        }
      '';
    };

    "nvim/lua/plugins/init.lua" = {
      text = ''
        -- ============================================
        -- 插件规范说明 (由 lazy.nvim 导入)
        -- 此文件为命名约定，实际插件定义在其他文件中
        -- ============================================

        return {}
      '';
    };

    "nvim/lua/plugins/ui.lua" = {
      text = ''
        -- ============================================
        -- UI 和主题配置
        -- ============================================

        return {
          {
            "nvim-tree/nvim-web-devicons",
            lazy = true,
          },
          {
            "nvim-lualine/lualine.nvim",
            dependencies = { "nvim-web-devicons" },
            config = function()
              require("lualine").setup({
                options = {
                  -- "auto" 会从**当前生效的配色方案**推导状态栏配色。
                  -- 原先写死的 "gruvbox" 对应的是 gruvbox.nvim 插件自带的
                  -- lualine 主题，那个插件已经移除（配色改由 stylix 注入），
                  -- 继续写死会得到一条和正文配色对不上的状态栏。
                  -- 用 auto 之后，将来换 base16 方案状态栏自动跟着变。
                  theme = "auto",
                  icons_enabled = true,
                },
                sections = {
                  lualine_a = { "mode" },
                  lualine_b = { "branch", "diff" },
                  lualine_c = { "filename" },
                  lualine_x = { "diagnostics", "encoding", "fileformat", "filetype" },
                  lualine_y = { "progress" },
                  lualine_z = { "location" },
                },
              })
            end,
          },
          -- 这里原先有 ellisonleao/gruvbox.nvim + colorscheme gruvbox，
          -- 已移除。配色改由 stylix 的 neovim target 注入：它往
          -- programs.neovim.plugins 加一个 Nix 管理的 mini.nvim，
          -- 并在 init.lua 末尾调 require('mini.base16').setup({palette=...})。
          --
          -- 顺序上 stylix 那段排在 require("config.lazy") **之后**
          -- （xdg.configFile 的 text 是 types.lines，多个定义按行拼接，
          -- stylix 的部分追加在尾部），所以即使留着 gruvbox 也会被盖掉。
          -- 但留着就是白下载一个插件 + 一条永远不生效的 colorscheme，
          -- 而且 lazy.nvim 的插件是运行时从网上拉的（见 000E），
          -- 在这台机器的慢网络上更没必要。
        }
      '';
    };

    "nvim/lua/plugins/nix.lua" = {
      text = ''
        -- ============================================
        -- Nix 语言支持配置
        -- ============================================

        return {
          {
            "LnL7/vim-nix",
            ft = { "nix" },
          },
        }
      '';
    };

    "nvim/lua/plugins/claudecode.lua" = {
      text = ''
        -- ============================================
        -- Claude Code 集成 (claudecode.nvim)
        -- ============================================
        -- coder/claudecode.nvim 是纯 Lua 实现的 Claude Code IDE 协议客户端，
        -- 和 VSCode 扩展走的是同一套 WebSocket 协议，所以能拿到同样的能力：
        -- 选区上下文、@ 引用文件、编辑以 diff 形式送回 Neovim 供审阅。
        --
        -- 它是从 Neovim 内部 spawn `claude` 可执行文件的，因此 `claude` 必须在
        -- nvim 的 wrapper PATH 里 —— 见上面 programs.neovim.extraPackages。
        -- 不需要设 terminal_cmd，默认值 "claude" 正好能从 PATH 找到。

        return {
          {
            "coder/claudecode.nvim",
            dependencies = { "folke/snacks.nvim" },
            cmd = {
              "ClaudeCode",
              "ClaudeCodeFocus",
              "ClaudeCodeSelectModel",
              "ClaudeCodeAdd",
              "ClaudeCodeSend",
              "ClaudeCodeTreeAdd",
              "ClaudeCodeStatus",
              "ClaudeCodeStart",
              "ClaudeCodeStop",
              "ClaudeCodeOpen",
              "ClaudeCodeClose",
              "ClaudeCodeDiffAccept",
              "ClaudeCodeDiffDeny",
              "ClaudeCodeCloseAllDiffs",
            },
            opts = {
              -- 终端界面
              terminal = {
                split_side = "right",
                split_width_percentage = 0.35,
                provider = "snacks",
                auto_close = true,
                auto_insert = true,
              },
              -- Claude 提出的修改以 diff 形式打开，审阅后再决定收不收
              diff_opts = {
                layout = "vertical",
                open_in_new_tab = false,
              },
            },
            keys = {
              { "<leader>a", nil, desc = "AI / Claude Code" },
              { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "开关 Claude 面板" },
              { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "聚焦 Claude 面板" },
              { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "恢复历史会话（选择器）" },
              {
                "<leader>aR",
                "<cmd>ClaudeCode --resume --fork-session<cr>",
                desc = "从历史会话岔出新会话",
              },
              { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "继续上一次会话" },
              { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "选择模型" },
              { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "把当前文件加入上下文" },
              { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "把选区发给 Claude" },
              { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "接受 diff" },
              { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "拒绝 diff" },
              { "<leader>aS", "<cmd>ClaudeCodeStatus<cr>", desc = "查看连接状态" },
            },
          },
          {
            -- claudecode.nvim 的终端后端，同时提供 diff 用的浮窗
            "folke/snacks.nvim",
            priority = 1000,
            lazy = false,
            opts = {
              input = { enabled = true },
              picker = { enabled = true },
            },
          },
        }
      '';
    };
  };

  # ============================================
  # GitHub CLI 认证说明 (仅供参考，不自动执行)
  # ============================================
  # 在新机器上配置 Copilot 认证，执行以下命令之一：
  #
  # 方式 1: 使用 GitHub CLI 认证 (自动化方式)
  #   gh auth login
  #   gh extension install github/gh-copilot
  #   # 然后在 Neovim 中运行: :Copilot auth
  #
  # 方式 2: 使用 VSCode 认证 (跳过本步，直接用 VSCode 完成认证)
  #   如不需要 GitHub CLI，可在 modules/development.nix 中注释掉 github-cli 行
}

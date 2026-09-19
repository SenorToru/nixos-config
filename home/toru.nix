{
  config,
  lib,
  pkgs,
  ...
}:

let
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
    nrb = "sudo nixos-rebuild switch --flake /home/toru/nixos-config#thinkpad";
    nrt = "sudo nixos-rebuild test --flake /home/toru/nixos-config#thinkpad";
    ncheck = "nix build /home/toru/nixos-config#nixosConfigurations.thinkpad.config.system.build.toplevel --out-link /tmp/res";
    nhm = "nix build /home/toru/nixos-config#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage --out-link /tmp/hm";
    # 用 nixos-rebuild 而不是 nix-env --list-generations：后者要开
    # /nix/var/nix/profiles/system.lock，非 root 直接 permission denied。
    # 前者不用 sudo，而且带构建日期、内核版本和 Current 标记。
    ngen = "nixos-rebuild list-generations";

    # git
    gs = "git status -sb";
    gd = "git diff";
    gl = "git log --oneline --graph --decorate -20";
  };
in
{
  home.username = "toru";
  home.homeDirectory = "/home/toru";
  home.stateVersion = "26.05";

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
  # 必须留在系统层，所以这里也不能启用 programs.git。
  home.packages = with pkgs; [
    dua # 交互式磁盘占用分析（Omarchy 4 的默认选择）
    duf # 挂载点/剩余空间一览
  ];

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

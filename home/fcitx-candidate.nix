# 候选窗配色（Rime 和 Mozc 共用）。
#
# GNOME 上看得见的那一块是扩展 kimpanel，不是 fcitx5 classic UI。
# kimpanel 的字号来自 dconf（home/toru.nix 里的 Pango 字体描述），
# 颜色来自 GNOME Shell 主题的 popup 样式。classic UI 的 theme.conf
# 它根本不读 —— 只改那份文件的话，nrb、重启、theme 都不会让画面变。
# 所以同一套颜色写两处：
#   classic UI 的 theme.conf：kimpanel 没画的时候（别的桌面）用
#   gnome-shell.css 末尾：现在这块面板用
# 字号不写进 CSS。扩展把 dconf 里的字体设成 inline style，会盖过样式表。
#
# 每种 stylix 主题各生成一份：字用和底色反差最大的那一档，
# 选中行用更亮的底，面板留一圈艳色边。
# 荧光只画在候选文字上（St.Label 的 text-shadow），不画在整块面板上。
# classic 主题格式没有文字阴影，那边只有这圈亮边。
# 放在 home 模块里，specialisation 激活时会按那套颜色重写。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  c = config.lib.stylix.colors;

  rgbOf = name: {
    r = lib.toInt c."${name}-rgb-r";
    g = lib.toInt c."${name}-rgb-g";
    b = lib.toInt c."${name}-rgb-b";
  };

  yOf = ch: ch.r * 299 + ch.g * 587 + ch.b * 114;
  abs = n: if n < 0 then -n else n;

  hexByte =
    n:
    let
      h = lib.toHexString n;
    in
    if n < 16 then "0${h}" else h;

  hexOf = ch: hexByte ch.r + hexByte ch.g + hexByte ch.b;

  # 往白里掺。亮色主题的强调色往往比纸色更暗，固定掺 50% 仍然暗过纸色。
  lighten = ch: pct: {
    r = ch.r + (255 - ch.r) * pct / 100;
    g = ch.g + (255 - ch.g) * pct / 100;
    b = ch.b + (255 - ch.b) * pct / 100;
  };

  lightenUntil =
    ch: minY:
    let
      go =
        pct:
        let
          mixed = lighten ch pct;
        in
        if yOf mixed > minY || pct >= 100 then mixed else go (pct + 5);
    in
    go 10;

  chroma =
    ch:
    let
      hi = lib.max ch.r (lib.max ch.g ch.b);
      lo = lib.min ch.r (lib.min ch.g ch.b);
    in
    hi - lo;

  mostContrast =
    bgY: names:
    lib.foldl' (
      best: name: if abs (yOf (rgbOf name) - bgY) > abs (yOf (rgbOf best) - bgY) then name else best
    ) (lib.head names) (lib.tail names);

  accentNames = [
    "base08"
    "base09"
    "base0A"
    "base0B"
    "base0C"
    "base0D"
    "base0E"
    "base0F"
  ];

  panel = rgbOf "base00";
  panelY = yOf panel;

  # 选最艳的那支，不选最亮的。暗色主题上艳的往往也更亮；
  # 亮色主题上艳的是深色，拿来做边，底再往白里掺到比纸色亮。
  vividAccent = lib.foldl' (
    best: name:
    let
      a = rgbOf name;
      b = rgbOf best;
    in
    if chroma a > chroma b || (chroma a == chroma b && yOf a > yOf b) then name else best
  ) (lib.head accentNames) (lib.tail accentNames);

  accent = rgbOf vividAccent;
  accentBrighter = yOf accent > panelY;

  highlight = if accentBrighter then accent else lightenUntil accent panelY;
  highlightY = yOf highlight;

  textName = mostContrast panelY [
    "base05"
    "base06"
    "base07"
  ];
  hiTextName = mostContrast highlightY [
    "base00"
    "base05"
    "base07"
  ];

  text = c.${textName};
  hiText = c.${hiTextName};
  bg = c.base00;
  hi = hexOf highlight;
  # 暗色：边比选中底再亮一档，顶替荧光。
  # 亮色：边用没掺白的那支艳色，否则亮边会融进纸色。
  border = hexOf (if accentBrighter then lighten accent 35 else accent);

  themeConf = pkgs.writeText "fcitx5-stylix-theme.conf" ''
    [Metadata]
    Name=Stylix
    Version=1
    Author=nixos-config
    Description=Generated from the active stylix palette
    ScaleWithDPI=True

    [InputPanel]
    NormalColor=#${text}
    HighlightColor=#${hiText}
    PageButtonAlignment=Last Candidate

    [InputPanel/TextMargin]
    Left=5
    Right=5
    Top=5
    Bottom=5

    [InputPanel/ContentMargin]
    Left=2
    Right=2
    Top=2
    Bottom=2

    [InputPanel/Background]
    Color=#${bg}
    BorderColor=#${border}
    BorderWidth=2

    [InputPanel/Background/Margin]
    Left=2
    Right=2
    Top=2
    Bottom=2

    [InputPanel/Highlight]
    Color=#${hi}

    [InputPanel/Highlight/Margin]
    Left=5
    Right=5
    Top=5
    Bottom=5

    [InputPanel/PrevPage]
    Image=prev.png

    [InputPanel/PrevPage/ClickMargin]
    Left=5
    Right=5
    Top=4
    Bottom=4

    [InputPanel/NextPage]
    Image=next.png

    [InputPanel/NextPage/ClickMargin]
    Left=5
    Right=5
    Top=4
    Bottom=4

    [Menu/Background]
    Color=#${bg}
    BorderColor=#${border}
    BorderWidth=2

    [Menu/Background/Margin]
    Left=2
    Right=2
    Top=2
    Bottom=2

    [Menu/ContentMargin]
    Left=2
    Right=2
    Top=2
    Bottom=2

    [Menu/CheckBox]
    Image=radio.png

    [Menu/SubMenu]
    Image=arrow.png

    [Menu/Highlight]
    Color=#${hi}

    [Menu/Highlight/Margin]
    Left=5
    Right=5
    Top=5
    Bottom=5

    [Menu/Separator]
    Color=#${border}

    [Menu/TextMargin]
    Left=5
    Right=5
    Top=5
    Bottom=5
  '';

  # 菜单图标相对主题目录。不拷的话翻页和子菜单只剩裂开的占位。
  # 不写 AccentColorField：写了的话 GNOME 强调色会盖掉这里的边框和选中底。
  themeDir = pkgs.runCommand "fcitx5-stylix-theme" { } ''
    mkdir -p "$out"
    cp ${themeConf} "$out/theme.conf"
    cp ${pkgs.fcitx5}/share/fcitx5/themes/default/arrow.png "$out/"
    cp ${pkgs.fcitx5}/share/fcitx5/themes/default/next.png "$out/"
    cp ${pkgs.fcitx5}/share/fcitx5/themes/default/prev.png "$out/"
    cp ${pkgs.fcitx5}/share/fcitx5/themes/default/radio.png "$out/"
  '';

  classicui = pkgs.writeText "classicui.conf" ''
    Font="Sarasa Gothic J 14"
    MenuFont="Sarasa Gothic J 14"
    Theme=stylix
    PerScreenDPI=True
    UseAccentColor=False
    UseDarkTheme=False
  '';

  # 选择器要比 stylix 的 .popup-menu-item:active 更具体。
  # 扩展自己的 stylesheet.css 几乎没写颜色，而且后加载；
  # 多一个类名之后，谁后加载都盖不住。
  # 候选行是 St.Label，选中靠 panel.js 加上 :active，不是菜单控件自带的。
  kimpanelCss = pkgs.writeText "kimpanel-candidate.css" ''
    .popup-menu-boxpointer.kimpanel-popup-boxpointer {
      -arrow-background-color: #${bg};
      -arrow-border-color: #${border};
      -arrow-border-width: 2px;
      color: #${text};
    }

    .popup-menu-content.kimpanel-popup-content {
      background-color: #${bg};
      color: #${text};
      border: 2px solid #${border};
    }

    .kimpanel-label {
      color: #${text};
    }

    /* :active 是另一套样式节点，不写的话选中时阴影会丢。 */
    .popup-menu-item.kimpanel-candidate-item,
    .popup-menu-item.kimpanel-candidate-item:hover,
    .popup-menu-item.kimpanel-candidate-item:active,
    .popup-menu-item.kimpanel-candidate-item:active:hover,
    .popup-menu-item.kimpanel-candidate-item:active:focus {
      text-shadow: 0 0 4px #${border};
    }

    .popup-menu-item.kimpanel-candidate-item:hover,
    .popup-menu-item.kimpanel-candidate-item:active,
    .popup-menu-item.kimpanel-candidate-item:active:hover,
    .popup-menu-item.kimpanel-candidate-item:active:focus {
      background-color: #${hi};
      color: #${hiText};
    }
  '';

  # 读 stylix 已经生成的那份 css，再接上上面这段。
  # 不要 mkForce xdg.dataFile 的 source：那会把 stylix 的产物整个换掉，
  # 这里又读不到它，两边就循环了。home.file 这条只盖最终链接的目标。
  stylixShellCss = config.xdg.dataFile."themes/Stylix/gnome-shell/gnome-shell.css".source;
  gnomeShellCss = pkgs.runCommand "gnome-shell-with-kimpanel.css" { } ''
    cat ${stylixShellCss} > "$out"
    printf '\n' >> "$out"
    cat ${kimpanelCss} >> "$out"
  '';
in
{
  home.file.".config/fcitx5/themes/stylix".source = themeDir;
  home.file.".config/fcitx5/conf/classicui.conf".source = classicui;

  home.file."${config.xdg.dataHome}/themes/Stylix/gnome-shell/gnome-shell.css".source =
    lib.mkForce gnomeShellCss;
}

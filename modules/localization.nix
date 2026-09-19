{ pkgs, ... }:

{
  # ============================================
  # 字体（全系统唯一的 fonts 声明处）
  # ============================================
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      sarasa-gothic
    ];

    fontconfig.enable = true;

    # 重要：这里必须写 fontconfig 真正认得的**完整族名**。
    # sarasa-gothic 不提供 "Sarasa Mono" / "Sarasa Gothic" 这种不带地区后缀的
    # 族名，noto-fonts-cjk 也不提供 "Noto Sans CJK" / "Noto Serif CJK"。
    # 写错的话 fontconfig 不会报错，只会静默回退到 Noto Sans——
    # 可以用 `fc-match "族名"` 逐个验证。
    #
    # 本机日语优先，故取 J / JP 变体；若想改成简体中文字形，
    # 把 J -> SC、JP -> SC 即可。
    fontconfig.defaultFonts = {
      monospace = [
        "Sarasa Mono J"
        "Noto Sans Mono CJK JP"
      ];
      sansSerif = [
        "Sarasa Gothic J"
        "Noto Sans CJK JP"
      ];
      serif = [
        "Noto Serif CJK JP"
      ];
    };
  };

  # ============================================
  # 同一套字体再告诉 stylix 一次
  # ============================================
  # 为什么要重复一遍：上面的 fontconfig.defaultFonts 是**系统级的兜底**，
  # 管的是「某个程序说它要 monospace 时，fontconfig 给它哪一个」。
  # 而 stylix 是把族名**直接写进各程序自己的配置文件**
  # （比如 ghostty 的 font-family = ...），走的不是 fontconfig 的解析。
  # 两条路各管各的，不设 stylix.fonts 的话它会用自己的默认值
  # DejaVu Sans Mono —— 那个字体**没有任何 CJK 覆盖**，
  # 终端里的日文中文会变豆腐块。
  #
  # 放在这个文件而不是 modules/stylix.nix，是为了让 README 里
  #「字体是全系统唯一的声明处」这句话继续成立。字体名散到两个文件
  # 才是真正的隐患：改了一处忘了另一处，两边指向不同字体。
  #
  # 族名必须和上面完全一致，而且**必须 fc-match 验证**——
  # 写错 fontconfig 不报错，只会静默回退（见 CLAUDE.md 坑 1）。
  stylix.fonts = {
    monospace = {
      package = pkgs.sarasa-gothic;
      name = "Sarasa Mono J";
    };
    sansSerif = {
      package = pkgs.sarasa-gothic;
      name = "Sarasa Gothic J";
    };
    serif = {
      package = pkgs.noto-fonts-cjk-serif;
      name = "Noto Serif CJK JP";
    };
    # emoji 保持 stylix 默认的 noto-fonts-color-emoji，
    # 本机原本就没有单独指定过 emoji 字体。
  };

  # ============================================
  # 输入法 (fcitx5)
  # ============================================
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-rime
      qt6Packages.fcitx5-chinese-addons
      fcitx5-mozc
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };
}

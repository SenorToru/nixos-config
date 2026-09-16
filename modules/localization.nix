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

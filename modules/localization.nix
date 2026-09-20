{ lib, pkgs, ... }:

let
  # ============================================
  # 白霜拼音（rime-frost）
  # ============================================
  # nixpkgs 里没有这个包（只有它的上游 rime-ice / 雾凇拼音），所以在这里
  # 自己打一个。打包方式照抄 nixpkgs 的 rime-ice：这类方案包不编译任何东西，
  # 只是把一堆 yaml / 词库原样铺进 $out/share/rime-data。
  #
  # 版本升级方式：
  #   1. 看新 tag：curl -s https://api.github.com/repos/gaboolic/rime-frost/releases/latest | jq -r .tag_name
  #   2. 改下面的 version
  #   3. 算新哈希：
  #      nix-prefetch-url --unpack https://github.com/gaboolic/rime-frost/archive/refs/tags/<tag>.tar.gz
  #      再 nix hash convert --hash-algo sha256 --to sri <上一步输出>
  rime-frost = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "rime-frost";
    version = "1.0.4";

    src = pkgs.fetchFromGitHub {
      owner = "gaboolic";
      repo = "rime-frost";
      tag = finalAttrs.version;
      hash = "sha256-1yxbLuVcCqgHGS14AecbVL7AQFGC/wbFO7US3Onz/R0=";
    };

    # 修上游的一个 lua 崩溃（1.0.4 与 master 都有这个问题）。
    #
    # lua/lunar.lua 的 Date2LunarDate() 把字符串拼接和数值比较都放在
    # 长度校验**之前**：
    #   552  Day = tonumber(Gregorian.sub(Gregorian, 7, 8))
    #   553  LunarDate3 = Year .. "年" .. Month .."月".. Day .. "日"
    #   554  if Year > 2100 or ... or string.len(Gregorian) < 8 then 无效日期
    #
    # 而识别器 gregorian_to_lunar 写的是 "^N[0-9]{1,8}"，允许 1 到 8 位。
    # 输入 N 加不足 8 位数字（边打边看时必然经过）就会 tonumber("") 得 nil，
    # 553 行拼接 nil 抛异常，日志刷屏：
    #   LuaTranslation::Next error(2): attempt to concatenate local 'Day'
    # 就算躲过 553，554 行的 Year > 2100 也会「attempt to compare nil」。
    #
    # 输入功能本身不受影响（该 translator 出错就不产候选，其它照常），
    # 但错误日志会把真正有用的信息淹掉，所以修掉。
    #
    # 用两处**单行**替换而不是多行：多行替换写在 nix 缩进字符串里会被
    # nixfmt 重排，缩进一变 --replace-fail 就匹配不上，构建直接失败。
    #   1. 553 行套 tostring()，nil 不再导致拼接异常
    #   2. 554 行条件最前面加 nil 检查，靠 or 短路，避免拿 nil 去比大小
    postPatch = ''
      substituteInPlace lua/lunar.lua \
        --replace-fail 'LunarDate3 = Year .. "年" .. Month .."月".. Day .. "日"' 'LunarDate3 = tostring(Year) .. "年" .. tostring(Month) .."月".. tostring(Day) .. "日"' \
        --replace-fail 'if Year > 2100 or Year < 1899' 'if not Year or not Month or not Day or Year > 2100 or Year < 1899'
    '';

    installPhase = ''
      runHook preInstall

      # others/ 是上游的杂项与文档，不需要进 rime 数据目录
      rm -rf others README.md .git*

      mkdir -p $out/share
      cp -r . $out/share/rime-data

      runHook postInstall
    '';

    meta = {
      description = "白霜拼音 —— 基于 rime-ice 重算词频的 Rime 方案";
      homepage = "https://github.com/gaboolic/rime-frost";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.all;
    };
  });
in
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
      # Rime，数据包只挂白霜拼音，**不带** nixpkgs 的 rime-data。
      #
      # 两者有 15 个文件同名（default.yaml、bopomofo/cangjie5/stroke 的
      # schema、essay.txt、opencc/ 等）。rimeDataPkgs 是用 symlinkJoin
      # 合并的，撞名时先出现的赢、后面的被静默忽略 —— 混挂会得到一份
      # 半新半旧、且取决于列表顺序的数据目录，极难排查。
      #
      # 只挂白霜的另一个好处：它自带的 default.yaml 里 rime_frost 就是
      # schema_list 的第一项，不需要再写 default.custom.yaml 去挂方案。
      #
      # 代价：经典的 luna_pinyin 方案不再存在（白霜只提供
      # luna_pinyin.dict.yaml，没有同名 schema）。原有的
      # luna_pinyin.userdb 会变成孤儿 —— 文件还在，但没有方案会去读它。
      (fcitx5-rime.override { rimeDataPkgs = [ rime-frost ]; })

      qt6Packages.fcitx5-chinese-addons
      # Mozc 换成带 UT 词典的版本。
      #
      # fcitx5-mozc-ut 就是 mozc.override { dictionaries = [ ... ] }，
      # mozc 本体版本完全相同（2.30.5544.102），只是把社区维护的 8 套
      # UT 词典编进系统词典：
      #   jawiki（日文维基词条）      neologd（新语/流行语/网络用语）
      #   sudachidict（大规模形态素） place-names（地名）
      #   personal-names（人名）      edict2
      #   alt-cannadic               skk-jisyo
      #
      # 因为 mozc 本体版本没变，~/.config/mozc/ 下的用户数据格式兼容，
      # 学习记录（.history.db 等）不会丢。
      #
      # 背景：Google 早就不怎么投入 Google 日本語入力的开源版了，
      # Anthy 也名存实亡，日语输入法生态真正活跃的部分就是这些社区词典。
      # 上游的默认词典对专有名词、人名地名、新词覆盖很弱，UT 补的正是这块。
      fcitx5-mozc-ut
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };
}

{
  lib,
  osConfig,
  ...
}:

let
  flakeHost = osConfig.custom.flakeHost;
  mediaKeys = "org/gnome/settings-daemon/plugins/media-keys";
in
{
  # 输入设备、快捷键、电源这几项 GNOME 偏好。由 home/toru.nix 的 imports 拼装。
  #
  # 分两块，判据是「换一台机器还成立吗」：
  #
  #   共用（下面的 mkMerge 第一项）
  #       鼠标手感、窗口贴边、开终端的快捷键。是人的习惯，跟着用户走。
  #
  #   只在 asus 生效（第二项）
  #       内置触摸板禁用、电源与息屏。它们描述的是「这台笔记本怎么用」——
  #       ThinkPad 的 TrackPoint / 触摸板和电源策略不该被 asus 的习惯覆盖。
  #       条件按仓库里的主机标识 custom.flakeHost 判断，不用 hostName。
  #
  # 来源：asus 前身（Bluefin）上的 dconf 原值，逐项抄过来。
  dconf.settings = lib.mkMerge [
    {
      # 鼠标：flat 加速曲线（不要加速度）、自然滚动、速度略降。
      # 只影响外接鼠标，触摸板有自己的一份 peripherals/touchpad。
      "org/gnome/desktop/peripherals/mouse" = {
        accel-profile = "flat";
        natural-scroll = true;
        speed = -0.34;
      };

      # 屏幕边缘贴靠关掉。窗口平铺交给 gTile 扩展，两个同时开会打架。
      "org/gnome/mutter".edge-tiling = false;

      # Ctrl+Alt+T 与 Ctrl+Alt+Return 都开默认终端。
      #
      # 走 xdg-terminal-exec，所以开的是 modules/desktop.nix 里配的 Ghostty，
      # 将来换终端只改那一处。GNOME 50 的 media-keys schema 里已经没有
      # 内建的 terminal 键，只能用自定义快捷键。
      #
      # 注意 custom-keybindings 是**整个列表被覆盖**：要再加一个自定义快捷键，
      # 得同时把路径加进这里，不能只另写一个子节。
      ${mediaKeys}.custom-keybindings = [
        "/${mediaKeys}/custom-keybindings/terminal-t/"
        "/${mediaKeys}/custom-keybindings/terminal-return/"
      ];

      "${mediaKeys}/custom-keybindings/terminal-t" = {
        name = "Terminal";
        command = "xdg-terminal-exec";
        binding = "<Primary><Alt>t";
      };

      "${mediaKeys}/custom-keybindings/terminal-return" = {
        name = "Terminal (Return)";
        command = "xdg-terminal-exec";
        binding = "<Primary><Alt>Return";
      };
    }

    (lib.mkIf (flakeHost == "asus") {
      # 内置触摸板整个禁用（这台平时外接鼠标用）。
      # 想临时用的话改成 "enabled" 或 "disabled-on-external-mouse"。
      "org/gnome/desktop/peripherals/touchpad".send-events = "disabled";

      # 电源：插电永不休眠，电池 900 秒后挂起，不自动息屏。
      #
      # idle-delay 是 uint32，写 0 表示永不。home-manager 的 dconf 模块
      # 里必须用 lib.gvariant.mkUint32，写裸的 0 会变成 int32，
      # GNOME 读到类型不对的值会静默忽略。
      "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;

      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "suspend";
        sleep-inactive-battery-timeout = 900;
      };
    })
  ];
}

{ ... }:

{
  # Steam 客户端，用 NixOS 的 programs.steam，不用 Flatpak 版。
  #
  # 原因：Steam 自己带一层运行时容器（pressure-vessel），装在 Flatpak 里
  # 就是沙箱套沙箱，和显卡驱动、混合显卡的 PRIME offload 配合最容易出问题。
  # programs.steam 用的是系统的 FHS 环境，能直接看到 hardware.graphics
  # 里的驱动。它还会顺手打开 hardware.graphics.enable32Bit，
  # 不需要再单独声明。
  #
  # 只装客户端。游戏库不进这个仓库，也不搬，重新下载。
  #
  # 放 modules/ 而不是 hosts/：任何有显卡的机器都能 import，
  # 但只有想装的机器才在自己的 default.nix 里引入 ——
  # 所以它不进 thinkpad 的 imports（那台 Intel HD 520 打不了游戏）。
  programs.steam.enable = true;
}

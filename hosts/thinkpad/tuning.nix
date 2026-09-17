{ pkgs, ... }:

{
  # ============================================
  # 本机专属调优：ThinkPad X1 Yoga 1st Gen
  # Skylake i7-6500U / 7.6 GiB DDR3 / Intel HD 520 (Gen9) / NVMe
  # ============================================
  #
  # 放在 hosts/thinkpad/ 而不是 modules/，因为这里**每一条都绑死在这台机器的
  # 具体硬件上**，换一台就是错的：
  #
  #   intel-media-driver   AMD / NVIDIA 机器装它纯属浪费，还会选错驱动
  #   vm.swappiness = 100  是按「7.6 GiB 内存 + 有磁盘 swap 兜底」算出来的
  #   thermald             Intel 专用，读的是 DPTF/ACPI
  #
  # 判断标准：换一台机器还成立的放 modules/，只对这台成立的放这里。
  # 将来加 asus / desktop 时，各自建一份自己的 tuning.nix，互不影响。

  # --- zram ---
  # 本机只有 7.6 GiB 内存，GNOME + VS Code + Neovide + 浏览器很容易碰顶。
  # 磁盘 swap 分区（8.8 GiB，priority -1）保留作兜底：zram 的 priority 是 5，
  # 内核会先用 zram，压满了才落到 NVMe 上。
  # memoryPercent 50 / algorithm zstd / priority 5 都是 NixOS 默认值，不重复写。
  zramSwap.enable = true;

  boot.kernel.sysctl = {
    # zram 的换出成本接近一次内存拷贝，比换到 NVMe 便宜一个数量级，
    # 所以可以比默认的 60 更积极。没有拉到社区常见的 180 ——
    # 那个值的前提是 zram 为**唯一** swap；这里背后还挂着磁盘分区，
    # 太激进会在 zram 压满后把压力整个甩给 NVMe。
    "vm.swappiness" = 100;

    # 换入时的预读页数（2^n 页）。对磁盘 swap，多读几页能摊薄寻道成本；
    # 对 zram 则纯属浪费 —— 没有寻道可言，每多读一页就多解压一次。
    "vm.page-cluster" = 0;
  };

  # --- 温控 ---
  # Skylake 移动端 U 在 NixOS 上默认只有内核的被动降频，没有用户态策略。
  # thermald 读 DPTF/ACPI 的温度阈值主动调 RAPL 功耗墙，
  # 表现是持续负载下不会一头撞到 100 ℃ 再猛降频。Intel 专用。
  services.thermald.enable = true;

  # --- 硬件视频解码 ---
  # hardware.graphics.enable 本来就是 true，但 extraPackages 是**空的**，
  # 也就是说现在没有任何 VAAPI 驱动，浏览器和 mpv 放视频全走 CPU 软解 ——
  # 在 6500U 上这是实打实的耗电和发热来源。
  # Skylake 属于 Gen9，主驱动走 iHD（intel-media-driver）；
  # 同时留一份旧的 i965 给个别只认它的老程序作回退。
  #
  # 验证：`nix shell nixpkgs#libva-utils -c vainfo`
  #       应当看到 "iHD" 字样和一串 VAProfile 列表，而不是 "no driver"。
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    intel-vaapi-driver
  ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # ============================================
  # 刻意不在这里出现的几项
  # ============================================
  #
  # services.fwupd.enable
  #   已上移到 modules/common.nix —— 任何带 UEFI 的机器都该开，不绑硬件。
  #
  # 以下三项已经是开着的，重复声明只会制造看不出真假的噪音：
  #   systemd.oomd.enable            NixOS 默认 true
  #   services.power-profiles-daemon GNOME 模块已拉起
  #   services.fstrim.enable         NixOS 默认 true，NVMe 的 TRIM 已经在跑
  #
  # services.tlp.enable **不能**加：TLP 和 power-profiles-daemon 抢同一批
  # sysfs 旋钮，NixOS 会直接抛断言失败。要用 TLP 得先关掉 GNOME 那个，
  # 代价是 GNOME 设置里的「电源模式」下拉框失效，不划算。
  #
  # services.fprintd.enable：本机指纹是 Validity VFS7500（138a:0090），
  # 上游 libfprint 不支持这颗，加了也只会得到一个找不到设备的 fprintd。
  # 详见 Lesson-Learn/000F。
}

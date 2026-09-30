{ lib, pkgs, ... }:

let
  # 两个占位，装机现场必须替换。用 `blkid` 查：
  #   winEspUuid    Samsung 上的 Windows ESP（FAT32，8 位短 UUID，形如 1D5C-9F1B）
  #   shareUuid     Samsung 上 1000 GiB 的共享 NTFS 分区（16 位十六进制）
  #
  # 抄错了配上 nofail 会**静默失败**：不报错、不阻止开机，只是 rEFInd
  # 没写进第二个 ESP，然后你会跑去怀疑 refind 模块。所以下面有个 warning，
  # 占位没换掉的话每次构建都会提示。
  winEspUuid = "0000-0000";
  shareUuid = "0000000000000000";

  # 四个 Btrfs 子卷共用的挂载选项，见下面「文件系统」一节。
  btrfsOptions = [
    "compress=zstd:3"
    "noatime"
  ];
in
{
  # ============================================
  # 本机专属调优：ASUS TX Air (FA401KM)
  # AMD Ryzen AI 7 H 350 / 30 GiB / Radeon 860M + RTX 5060 Laptop / NVMe x2
  # ============================================
  #
  # 判据同 hosts/thinkpad/tuning.nix：换一台机器还成立的放 modules/，
  # 只对这台成立的放这里。这里每一条都绑死在这台硬件上。

  warnings =
    lib.optional (
      winEspUuid == "0000-0000"
    ) "hosts/asus/tuning.nix: winEspUuid 还是占位值，/mnt/winesp 挂不上，rEFInd 不会写进 Windows 的 ESP。"
    ++ lib.optional (
      shareUuid == "0000000000000000"
    ) "hosts/asus/tuning.nix: shareUuid 还是占位值，共享 NTFS 盘挂不上。";

  # --- 显卡：AMD 核显出图，NVIDIA 独显做 PRIME offload ---
  #
  # 形态和 Bluefin 上一致：eDP 和外接显示器都连在核显上，
  # NVIDIA 上没有任何输出，只在需要时被拉起来算。
  # 用法：`nvidia-offload <命令>`，Steam 游戏在启动选项里写
  # `nvidia-offload %command%`。
  #
  # busId 是 lspci 里 0000:66:00.0 / 0000:64:00.0 的**十进制**写法
  # （0x66 = 102，0x64 = 100）。抄错了 X/Wayland 会找不到设备。
  # 换主板或加装显卡后要重新核对。
  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];

  hardware.nvidia = {
    # RTX 50 系（Blackwell）只支持开源内核模块，闭源的不认。
    open = true;
    modesetting.enable = true;
    # 对应 Bluefin 上 NVreg_PreserveVideoMemoryAllocations=1，
    # 挂起/唤醒时保住显存，不然唤醒后独显程序会花屏。
    powerManagement.enable = true;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      amdgpuBusId = "PCI:102:0:0";
      nvidiaBusId = "PCI:100:0:0";
    };
  };

  # 没有加 NVreg_EnableS0ixPowerManagement=1。那是 Bluefin 镜像的默认值，
  # 没有实测过它对这台的续航有没有帮助，先不加，以后需要再补。

  # Wi-Fi 网卡是 Realtek RTL8852CE，驱动 rtw89 在内核里，固件在
  # linux-firmware。没有这一行，网卡能识别但连不上任何网络。
  hardware.enableRedistributableFirmware = true;

  # --- zram ---
  # 30 GiB 内存，而且**没有磁盘 swap 分区**（不做休眠），zram 是唯一的 swap。
  # memoryPercent / algorithm / priority 用 NixOS 默认值。
  zramSwap.enable = true;

  boot.kernel.sysctl = {
    # thinkpad 上写的是 100，那是因为背后还挂着磁盘 swap，太激进会把压力
    # 甩给 NVMe。这台 zram 是唯一 swap，可以用社区常见的 180：
    # 换出到 zram 只是一次内存拷贝，比丢掉文件缓存便宜。
    # **不能抄 thinkpad 的值** —— 那是按 7.6 GiB 内存 + 磁盘 swap 算的。
    "vm.swappiness" = 180;

    # zram 没有寻道，预读纯属浪费。
    "vm.page-cluster" = 0;
  };

  # --- 文件系统 ---
  # 挂载选项里 compress 和 noatime **不会被 nixos-generate-config 记录**，
  # 所以在这里补上（MIGRATION.md 决策点 C）。选项列表会和
  # hardware-configuration.nix 里的 subvol= 合并。
  #
  # 压缩等级用 zstd:3。thinkpad 用的是 zstd:1，那是因为 Skylake 的移动端 U
  # 比较弱；这台是 Ryzen AI 7 H 350，CPU 有富余，多花一点 CPU 换更好的压缩率。
  # 决策依据见 MIGRATION.md 决策点 C。
  #
  # **四个子卷必须写成同一个等级。** Btrfs 的 compress 是整个文件系统
  # 共用的，几个子卷写得不一样，内核只会按其中一个生效，还会打警告。
  # 所以用文件开头 let 里的同一个 btrfsOptions，别各写各的。
  #
  # 只有这块 Btrfs 能压缩。ESP 是 FAT32，共享盘是 NTFS（ntfs3 不支持
  # 写时压缩），压缩不了，也不需要。
  fileSystems."/".options = btrfsOptions;
  fileSystems."/home".options = btrfsOptions;
  fileSystems."/nix".options = btrfsOptions;
  fileSystems."/.snapshots".options = btrfsOptions;

  # Samsung 上 Windows 的 ESP。refind-sync 要往里写一份 rEFInd，所以必须挂着。
  # nofail 不能省：那块盘不在的时候，没有它会卡在开机。
  fileSystems."/mnt/winesp" = {
    device = "/dev/disk/by-uuid/${winEspUuid}";
    fsType = "vfat";
    options = [
      "nofail"
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # Windows 和 NixOS 共享的 NTFS 分区（Samsung 盘尾，1000 GiB）。
  #
  # **Windows 侧必须关掉快速启动和休眠**（powercfg /h off），
  # 否则关机时 NTFS 留在脏状态，这里要么挂不上要么只读，
  # 强行写会损坏文件系统。见 MIGRATION.md 第 4.3 节。
  #
  # 用内核自带的 ntfs3 驱动。uid=1000 gid=100 是 toru:users，
  # 不设的话整个分区归 root，普通用户写不进去。
  fileSystems."/mnt/share" = {
    device = "/dev/disk/by-uuid/${shareUuid}";
    fsType = "ntfs3";
    options = [
      "nofail"
      "uid=1000"
      "gid=100"
      "windows_names"
    ];
  };

  # ============================================
  # 刻意不在这里出现的几项
  # ============================================
  #
  # services.thermald / intel-media-driver
  #   Intel 专用，AMD 机器上纯属浪费。AMD 的视频解码走 mesa 自带的
  #   VAAPI，不需要额外装。
  #
  # services.fprintd
  #   Bluefin 上 lsusb 里没有任何指纹读取器，不配。
  #
  # swap 分区 / 休眠
  #   不要休眠，只用 zram。
  #
  # Secure Boot
  #   固件里关着，保持关。开了的话 rEFInd 和 systemd-boot 都要另外签名。
}

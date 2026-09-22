{ ... }:

{
  # ============================================
  # 虚拟机专属调优
  # ============================================
  # 这里每一条都只对这台（虚拟）机器成立。
  # **不要照抄 hosts/thinkpad/tuning.nix** —— 那里的
  # intel-media-driver、thermald、vm.swappiness 换到这里全是错的。

  # Btrfs 挂载选项。**nixos-generate-config 不记 compress 和 noatime**，
  # 安装时挂载用的那份只作用于安装过程，持久生效必须在这里声明。
  # fileSystems.*.options 是列表，会和 hardware-configuration.nix
  # 里的 subvol= 合并。
  fileSystems."/".options = [
    "compress=zstd:3"
    "noatime"
  ];
  fileSystems."/home".options = [
    "compress=zstd:3"
    "noatime"
  ];
  fileSystems."/nix".options = [
    "compress=zstd:3"
    "noatime"
  ];
  fileSystems."/.snapshots".options = [
    "compress=zstd:3"
    "noatime"
  ];

  fileSystems."/mnt/winesp" = {
    device = "/dev/disk/by-uuid/B0E3-F199";
    fsType = "vfat";
    options = [
      "nofail"
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/mnt/share" = {
    device = "/dev/disk/by-uuid/3233F10134A69176";
    fsType = "ntfs3";
    options = [
      "nofail"
      "uid=1000"
      "gid=100"
      "umask=0022"
    ];
  };

  # 虚拟机客户机支持
  services.qemuGuest.enable = true; # 优雅关机、宿主机能读到 IP
  services.spice-vdagentd.enable = true; # 剪贴板共享、分辨率自适应

  zramSwap.enable = true;
}

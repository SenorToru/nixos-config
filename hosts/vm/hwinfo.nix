# 本文件由 refind-hwinfo 生成。
#
# 重新生成：在仓库根目录跑 refind-hwinfo，然后 nrb，再 sudo refind-sync。
# 换了硬件就重跑一次。探测判断错了可以直接改这个文件 ——
# 它不在开机路径上，错了只是启动画面上一行字不对。
#
# 内核版本不在这里：它跟着 nixpkgs 滚，由 modules/refind.nix 在
# 求值时从 config.boot.kernelPackages 取，永远不会过期。
{
  custom.refind.bootRows = [
    {
      name = "cpu    ";
      value = "AMD RYZEN AI 7 H 350 W/ RADEON 860M ";
      status = "[ ONLINE ]";
    }
    {
      name = "gpu    ";
      value = "RED VIRTIO 1.0 GPU / SHARED ";
      status = "[ ONLINE ]";
    }
    {
      name = "memory ";
      value = "16384M RAM ";
      status = "[ OK ]";
    }
    {
      name = "disk   ";
      value = " 137GB ";
      status = "[ MOUNTED ]";
    }
  ];
}

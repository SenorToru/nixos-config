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
      value = "INTEL CORE I7-6500U ";
      status = "[ ONLINE ]";
    }
    {
      name = "gpu    ";
      value = "INTEL HD GRAPHICS 520 / SHARED ";
      status = "[ ONLINE ]";
    }
    {
      name = "memory ";
      value = "8192M LPDDR3 ";
      status = "[ OK ]";
    }
    {
      name = "disk   ";
      value = "SAMSUNG MZVL81T0HELB 1TB ";
      status = "[ MOUNTED ]";
    }
  ];
}

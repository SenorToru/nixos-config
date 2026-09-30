# 占位。装好 NixOS 之后在仓库根目录跑 `sudo refind-hwinfo` 重新生成，
# 再 nrb、sudo refind-sync。
#
# 生成的内容会整个覆盖这个文件。下面几行是按 Bluefin 上查到的硬件
# 手填的，仅仅为了装机前能把配置构建通过。
{
  custom.refind.bootRows = [
    {
      name = "cpu    ";
      value = "AMD RYZEN AI 7 H 350 ";
      status = "[ ONLINE ]";
    }
    {
      name = "gpu    ";
      value = "RADEON 860M + RTX 5060 ";
      status = "[ ONLINE ]";
    }
    {
      name = "memory ";
      value = "30G ";
      status = "[ OK ]";
    }
    {
      name = "disk   ";
      value = "SAMSUNG 990 PRO 2TB ";
      status = "[ MOUNTED ]";
    }
  ];
}

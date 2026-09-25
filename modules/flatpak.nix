{ ... }:

{
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # 自动添加Flathub源
  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  # 自动安装
  # 这张表是**唯一真相**：不在表里的 Flatpak 换台机器就不会出现。
  #
  # handbrake 就是这么漏掉过一次 —— 装了但没声明，
  # 写 MIGRATION.md 时对比 `ls ~/.var/app` 和这张表才发现。
  # `migration-check` 现在会自动查这种漂移。
  services.flatpak.packages = [
    "com.github.tchx84.Flatseal"
    "com.tencent.WeChat"
    "eu.betterbird.Betterbird"
    "com.baidu.NetDisk"
    "fr.handbrake.ghb"

    # Bruno 用官方 AppImage，不钉 commit。要新版时不用重建：
    #   sudo flatpak update com.usebruno.Bruno
    # 不要为此打开 update.onActivation / update.auto。
    # 那两个开关是全局的，会把这张表里的其它应用一起滚走。
    # Flathub 这份目前只有 x86_64。加 ARM 机器前先确认有对应架构。
    "com.usebruno.Bruno"
  ];
}

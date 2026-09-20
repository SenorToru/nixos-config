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
  ];
}

{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;
  # vm 是演练机，不参与这套文件同步。
  shareFiles = osConfig.custom.flakeHost != "vm";
  trash30 = {
    type = "trashcan";
    params.cleanoutDays = "30";
  };
in
{
  # Syncthing 本体是后台服务，界面是本机网页 http://127.0.0.1:8384/ 。
  # 登录后启动，注销后停。合上盖子只是睡眠，会话还在，同步继续。
  #
  # 不装 Syncthingy，也不开托盘。这台 GNOME 把 AppIndicator 扩展
  # 放在 disabled-extensions 里，托盘图标出不来；Syncthingy 还会
  # 在 Flatpak 里再起一份 Syncthing，和这个服务抢数据库。
  #
  # 换到 Hyprland 之后服务和网页都不用改。若那时 Waybar 有托盘，
  # 再开 services.syncthing.tray（syncthingtray）即可，它只是
  # 同一份服务的遥控器。
  #
  # 下面六个文件夹是家目录规矩里要同步的全部。
  # overrideDevices / overrideFolders 必须是 false：
  # 默认 true 会在下次激活时删掉网页里另加的设备和文件夹。
  #
  # 保险箱（secrets）现在是对等可写。Asus 装成 NixOS 并成为主力之后，
  # 只让 Asus 保持 sendreceive，ThinkPad 和 Mac 把这个文件夹改成
  # receiveonly。笔记、library、照片、音乐、视频始终对等可写。
  #
  # 不同步：整个 Documents、Downloads、桌面、Pictures/Screenshots、
  # ~/Secrets（Cryptomator 解开后的明文）、~/.config、~/.local。
  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
    settings = lib.mkIf shareFiles {
      folders = {
        notes = {
          path = "${home}/Documents/notes";
          label = "笔记";
          versioning = trash30;
        };
        library = {
          path = "${home}/Documents/library";
          label = "档案";
          versioning = trash30;
        };
        secrets = {
          path = "${home}/Documents/secrets";
          label = "保险箱";
        };
        pictures = {
          path = "${home}/Pictures/library";
          label = "照片";
          versioning = trash30;
        };
        music = {
          path = "${home}/Music";
          label = "音乐";
        };
        videos = {
          path = "${home}/Videos";
          label = "视频";
        };
      };
    };
  };

  # syncthing：桌面图标在主包里，活动概览里的「Syncthing Web UI」打开网页。
  # 服务模块自己只把 man 页放进 PATH。
  # cryptomator：保险箱密码只放 Proton Pass。明文解锁到 ~/Secrets，不进同步。
  home.packages = [
    pkgs.syncthing
    pkgs.cryptomator
  ];
}

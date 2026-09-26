{
  # 同步用的端口。网页 8384 只听 127.0.0.1，不放进防火墙。
  #
  # 服务本身在 home/syncthing.nix，以登录用户跑，才能读写家目录。
  # 这里不启用 NixOS 的 services.syncthing：那会再起一份、并且默认
  # 跑在另一个系统用户下。
  #
  # 22000 是设备之间传文件，21027/udp 是局域网发现。
  # 不开的话外网设备仍可能经中继连上，局域网里的直接连接会失败。
  networking.firewall = {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };
}

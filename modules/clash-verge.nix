{
  lib,
  pkgs,
  ...
}:
let
  # 官方 GitHub Release 的 amd64 deb，不是 nixpkgs 里那份源码包。
  # 26.05 的 clash-verge-rev 是 2.4.7，要换版本得同时改 src、pnpm 和
  # Cargo vendor 三份哈希，还连着一份单独编译的服务。deb 只钉版本和一份哈希。
  #
  # 刷新（看 github.com/clash-verge-rev/clash-verge-rev/releases）：
  #
  #   V=2.5.8
  #   H=$(nix hash convert --hash-algo sha256 \
  #     "$(nix-prefetch-url \
  #       "https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v$V/Clash.Verge_${V}_amd64.deb")")
  #   printf '{\n  "version": "%s",\n  "hashes": {\n    "x86_64-linux": "%s"\n  }\n}\n' \
  #     "$V" "$H" > modules/clash-verge-version.json
  #
  # 目前只有 x86_64-linux。加别的平台时补安装包名和哈希，否则求值直接报缺。
  # 应用内「检查更新」下载的包装不进 Nix store，看到提示就关掉，改这个 json。
  pin = lib.importJSON ./clash-verge-version.json;
  system = pkgs.stdenv.hostPlatform.system;
  missing = what: throw "clash-verge-version.json 没有 ${system} 的${what}。目前只准备了 x86_64-linux 的官方 deb。";
  asset =
    {
      x86_64-linux = "Clash.Verge_${pin.version}_amd64.deb";
    }
    .${system} or (missing "安装包名");
  hash = pin.hashes.${system} or (missing "哈希");

  # 服务会核对 verge-mihomo 的摘要。patchelf 或 strip 改一个字节就对不上。
  # 所以只处理图形界面；核心、alpha 和服务本体保持 deb 里的字节。
  # 安装器和卸载器换成下面的脚本：上游那个会 systemctl stop，
  # 再把单元写进 /etc/systemd/system，而这条路径是指向 Nix store 的符号链接。
  # 服务是动态链接的，由下面的单元用 nix-ld 启动，不靠 patchelf。
  # Tauri 的资源目录是可执行文件上两级的 lib/Clash Verge，deb 的布局照搬。
  clash-verge = pkgs.stdenv.mkDerivation {
    pname = "clash-verge";
    version = pin.version;

    src = pkgs.fetchurl {
      url = "https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v${pin.version}/${asset}";
      inherit hash;
    };

    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
      wrapGAppsHook3
      addDriverRunpath
    ];

    buildInputs = with pkgs; [
      gtk3
      gdk-pixbuf
      cairo
      glib
      dbus
      webkitgtk_4_1
      libsoup_3
    ];

    # 托盘图标和 openssl 是运行时 dlopen，不在 NEEDED 里。
    # openssl 的默认输出是 bin，库在 out。写 openssl 会把一个没有 .so 的目录加进 rpath。
    runtimeDependencies = with pkgs; [
      libayatana-appindicator
      openssl.out
    ];

    dontAutoPatchelf = true;
    dontWrapGApps = true;
    dontStrip = true;
    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp -a usr/bin "$out/bin"
      cp -a "usr/lib/Clash Verge" "$out/lib/"
      cp -a usr/share "$out/share"
      mv "$out/share/applications/Clash Verge.desktop" \
        "$out/share/applications/clash-verge.desktop"
      substituteInPlace "$out/share/applications/clash-verge.desktop" \
        --replace-fail "Exec=clash-verge" "Exec=$out/bin/clash-verge"
      rm -f "$out/bin/clash-verge-service-install" \
        "$out/bin/clash-verge-service-uninstall"
      cp ${installWrapper} "$out/bin/clash-verge-service-install"
      cp ${uninstallWrapper} "$out/bin/clash-verge-service-uninstall"
      chmod 0555 "$out/bin/clash-verge-service-install" \
        "$out/bin/clash-verge-service-uninstall"
      runHook postInstall
    '';

    # 先 patchelf 再包一层，包装脚本才能带上 gsettings 和 gdk-pixbuf。
    postFixup = ''
      autoPatchelf "$out/bin/clash-verge"
      addDriverRunpath "$out/bin/clash-verge"
      wrapGApp "$out/bin/clash-verge"
    '';

    meta = {
      description = "Clash Verge Rev";
      homepage = "https://github.com/clash-verge-rev/clash-verge-rev";
      license = lib.licenses.gpl3Only;
      mainProgram = "clash-verge";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };

  # 图形界面认的是 /var/lib/clash-verge-service/cores 里的普通文件。
  # 从文件一直往上到 /，每一级都要 root 所有，且组和其他人不可写。
  # 符号链接会被拒绝；/nix/store 是 1775，放在里面也会被拒绝。
  # 所以上面两个名字必须是 root 拥有的副本，模式 0550，和上游安装器一致。
  publishCores = pkgs.writeShellScript "clash-verge-publish-cores" ''
    set -eu
    bin=$1
    state=/var/lib/clash-verge-service
    dest=$state/cores
    install -d -o root -g root "$state" "$dest"
    chmod 0700 "$state" "$dest"
    chown root:root "$state" "$dest"
    for name in verge-mihomo verge-mihomo-alpha; do
      src=$bin/$name
      target=$dest/$name
      copy=0
      if [ -L "$target" ] || [ ! -f "$target" ]; then
        copy=1
      else
        src_sum=$(sha256sum "$src" | cut -d ' ' -f 1)
        dst_sum=$(sha256sum "$target" | cut -d ' ' -f 1)
        if [ "$src_sum" != "$dst_sum" ]; then
          copy=1
        fi
      fi
      if [ "$copy" = 1 ]; then
        rm -f "$target"
        install -m 0550 -o root -g root "$src" "$target"
      else
        chown root:root "$target"
        chmod 0550 "$target"
      fi
    done
  '';

  # 应用把这个名字当安装器启动，先不提权。脚本自己再 pkexec。
  # 提权之后只复制内核并重启本模块的单元，不写 /etc/systemd/system。
  installWrapper = pkgs.writeShellScript "clash-verge-service-install" ''
    set -eu
    if [ "$(id -u)" -ne 0 ]; then
      exec pkexec "$0" "$@"
    fi
    here=$(readlink -f "$0")
    ${publishCores} "$(dirname "$here")"
    systemctl restart clash-verge-service.service
  '';

  uninstallWrapper = pkgs.writeShellScript "clash-verge-service-uninstall" ''
    echo "Clash Verge 的服务由 NixOS 管理。应用里的卸载会删掉系统单元，已拒绝。" >&2
    exit 1
  '';
in
{
  # 这一项把包放进 systemPackages，并读得到桌面文件。
  # serviceMode 保持关闭：nixpkgs 那个单元的 RuntimeDirectory 是
  # clash-verge-rev，套接字路径和沙箱都是按打过补丁的 2.4.7 服务写的。
  # 这份官方服务的套接字固定在 /run/clash-verge-service/service.sock。
  # tunMode 也保持关闭：它给图形界面加 capabilities，模块自己写了 DNS 会坏。
  # TUN 由下面以 root 跑的服务负责。
  programs.clash-verge = {
    enable = true;
    package = clash-verge;
  };

  # 单元内容和安装器嵌进去的模板一致：root、Group=users、
  # RuntimeDirectory=clash-verge-service、失败就重启。
  # 服务没 patchelf，解释器走 /lib64 的 nix-ld，所以把会话里那两个变量
  # 显式放进单元。静态的 verge-mihomo 不需要它们。
  # 内核必须在服务启动前就放好，否则界面会判服务不可用并弹出 Repair。
  systemd.services.clash-verge-cores = {
    description = "放置 Clash Verge 认可的内核";
    requiredBy = [ "clash-verge-service.service" ];
    before = [ "clash-verge-service.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${publishCores} ${clash-verge}/bin
    '';
  };

  systemd.services.clash-verge-service = {
    description = "Clash Verge 服务模式";
    wantedBy = [ "multi-user.target" ];
    after = [ "clash-verge-cores.service" ];
    requires = [ "clash-verge-cores.service" ];
    serviceConfig = {
      ExecStart = "${clash-verge}/bin/clash-verge-service";
      Group = "users";
      Restart = "always";
      RestartSec = 5;
      RuntimeDirectory = "clash-verge-service";
      RuntimeDirectoryMode = "0755";
    };
    environment = {
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
  };
}

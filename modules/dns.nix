{ lib, pkgs, ... }:

# ============================================
# DNS：加密解析（DNS-over-TLS）
# ============================================
# 为什么存在这个模块，一句话：**明文 DNS 是可以被中间设备伪造的，
# 而伪造得不规范时的症状极难定位。**
#
# 本仓库为此付过一整天：iKuai 路由器勾了「禁止 AAAA 记录（IPv6）解析」，
# 它实现这个禁止的办法是伪造一个畸形的 NODATA 应答顶回去 ——
# SOA 的 MNAME/RNAME 写成根、OPT 记录塞进 authority 段、夹带未初始化内存。
# glibc 宽容就收下了，systemd-resolved 严格就判 invalid-reply，
# 于是「同一个网络里 thinkpad 正常、虚拟机里 Claude Code 连不上」。
# 完整过程见 Lesson-Learn/0014_DNS_HIJACK_AND_DOT.md。
#
# DoT 把查询装进 TLS，中间设备既看不见也改不了，这类问题从结构上不可能发生。
# 这不是「绕过」那次故障 —— 那次的根因已经在路由器上修掉了 ——
# 而是让同一类故障以后不必再查一遍。
#
# 放 modules/ 而不是 hosts/：判据是「换一台机器这条还成立吗」。
# 成立。加密 DNS 和硬件、和这个网络都无关，任何机器都该开。

let
  # ============================================
  # 运行时切换：dns clash / dns plain / dns dot
  # ============================================
  # 严格 DoT 有一个真实的代价：酒店门户、以及境内随身 WiFi，
  # 都会让 853 出不去。没有明文后备时，连认证页都打不开。
  #
  # 一个命令三个模式，空打打印帮助。只改当前连接的运行时状态，
  # 不动配置文件。重连或重启回到加密 DNS。
  #
  #   sudo dns clash   Clash 网关模式已开，解析交给 tun 上的假地址
  #   sudo dns plain   问当前网关的明文 DNS（门户页，或关掉 Clash 后的随身 WiFi）
  #   sudo dns dot     回到 1.1.1.1 / 8.8.8.8 的 853（iPhone 热点这类境外出口）
  #
  # 网卡名和假地址都现查。tun 认内核里的 tun 设备，假地址认
  # 198.18.0.0/15（Clash 已经写在那块网卡上的优先）。
  # 物理网卡认主路由表里「default via … dev …」，跳过 tun。
  # 随身 WiFi 的三大运营商不用分开：命令认的是网关，不是运营商。

  ip = "${pkgs.iproute2}/bin/ip";
  awk = "${pkgs.gawk}/bin/awk";
  resolvectl = "${pkgs.systemd}/bin/resolvectl";

  # 用 writeShellScriptBin 而不是 writeShellApplication：后者构建期跑
  # shellcheck，而 shellcheck 在沙箱的 C locale 下打印不出中文，
  # 一有 warning 就崩在 commitBuffer: invalid argument 上。见 CLAUDE.md。
  # 帮助文本放 store 文件，不在脚本里写 heredoc。
  dnsHelp = pkgs.writeText "dns-help.txt" ''
    dns — 切换这一次连接的 DNS

    不改配置文件。重连网络或重启后，回到加密 DNS。
    三个模式都要 root。不带参数时打印这份说明。

    sudo dns clash
      随身 WiFi 上已经打开 Clash 的网关模式，要让浏览器走代理节点。
      中国移动、联通、电信是同一条命令：解析交给 Clash 的 tun
      （通常叫 Meta）上的假地址，并关掉这条链路的加密 DNS。
      物理网卡上的网关 DNS 会清掉，避免查询绕过 tun。
      先打开网关模式再跑。找不到 tun 就拒绝。
      成功时 google.com 应落在 198.18.0.0/15。

    sudo dns plain
      问当前网关的明文 DNS。两种场景都用它：
        酒店、机场、咖啡馆的认证页。853 被拦住时，先跑这个才能打开门户。
        关掉 Clash 网关模式之后，只用随身 WiFi 自己的中国网络。
      Clash 的 tun 还在就拒绝，避免你以为已经直连、流量仍进代理。

    sudo dns dot
      回到加密 DNS（1.1.1.1 和 8.8.8.8 的 853 端口）。
      用于 iPhone 热点这类境外出口。认证页过完之后也用它。
      Clash 的 tun 还在就拒绝。先退出网关模式，再跑。
  '';

  dnsCmd = pkgs.writeShellScriptBin "dns" ''
    set -eu
    mode=''${1:-}
    case "$mode" in
      "" | -h | --help | help)
        cat ${dnsHelp}
        exit 0
        ;;
      clash | plain | dot) ;;
      *)
        cat ${dnsHelp} >&2
        exit 1
        ;;
    esac
    if [ "$(id -u)" -ne 0 ]; then
      echo "需要 root：sudo dns $mode" >&2
      exit 1
    fi

    tun=$(${ip} -d link show | ${awk} '
      /^[0-9]+:/ { name = $2; sub(/:$/, "", name) }
      $1 == "tun" && name == "Meta" { meta = name }
      $1 == "tun" && first == "" { first = name }
      END { if (meta != "") print meta; else if (first != "") print first }
    ')

    phys=$(${ip} -4 route show default | ${awk} -v tun="$tun" '
      $1 == "default" && $2 == "via" && $4 == "dev" && $5 != tun {
        print $5, $3
        exit
      }
    ')
    phys_link=''${phys%% *}
    phys_gw=''${phys#* }

    fake_of() {
      ${resolvectl} dns "$1" 2>/dev/null | ${awk} '
        {
          for (i = 1; i <= NF; i++) {
            split($i, a, ".")
            if (a[1] == "198" && (a[2] == "18" || a[2] == "19")) {
              print $i
              exit
            }
          }
        }
      '
    }

    case "$mode" in
      clash)
        if [ -z "$tun" ]; then
          echo "找不到 Clash 的 tun。先打开网关模式，再跑 sudo dns clash。" >&2
          exit 1
        fi
        fake=$(fake_of "$tun")
        if [ -z "$fake" ]; then
          fake=198.18.0.2
          echo "tun $tun 上还没有 198.18.0.0/15 的地址，用 Clash 的默认假地址 $fake。"
        fi
        if [ -n "$phys_link" ]; then
          ${resolvectl} revert "$phys_link"
        fi
        ${resolvectl} dns "$tun" "$fake"
        ${resolvectl} domain "$tun" '~.'
        ${resolvectl} dnsovertls "$tun" no
        ${resolvectl} flush-caches
        echo "解析交给 $tun 的 $fake，加密 DNS 在这条链路上已关掉。"
        ${resolvectl} query google.com || true
        ;;
      plain)
        if [ -n "$tun" ]; then
          echo "Clash 的 tun（$tun）还在。先关掉网关模式或退出 Clash，再跑 sudo dns plain。" >&2
          echo "现在切过去的话，你会以为已经在用随身 WiFi 的直连，流量仍可能进代理。" >&2
          exit 1
        fi
        if [ -z "$phys_link" ] || [ -z "$phys_gw" ] || [ "$phys_link" = "$phys_gw" ]; then
          echo "找不到默认网关。先确认网络连上了。" >&2
          exit 1
        fi
        ${resolvectl} dns "$phys_link" "$phys_gw"
        ${resolvectl} domain "$phys_link" '~.'
        ${resolvectl} dnsovertls "$phys_link" no
        ${resolvectl} flush-caches
        echo "链路 $phys_link 改问网关 $phys_gw 的明文 DNS。"
        echo "门户页过完，或回到境外网络后，跑：sudo dns dot"
        ;;
      dot)
        if [ -n "$tun" ]; then
          echo "Clash 的 tun（$tun）还在。先退出网关模式，再跑 sudo dns dot。" >&2
          echo "tun 还在时，Clash 会把解析指回假地址，加密 DNS 不会生效。" >&2
          exit 1
        fi
        ${ip} -o link show | ${awk} '{ name = $2; sub(/:$/, "", name); if (name != "lo") print name; }' |
          while read -r link; do
            ${resolvectl} revert "$link" || true
          done
        ${resolvectl} flush-caches
        echo "已回到全局加密 DNS。"
        ${resolvectl} status | ${pkgs.gnugrep}/bin/grep -E 'DNS Servers|DNSOverTLS|Current DNS' || true
        ;;
    esac
  '';
in
{
  services.resolved = {
    enable = true;

    # 这个 nixpkgs 里扁平的 dnsovertls / dnssec / fallbackDns 已经被
    # mkRenamedOptionModule 挪到 settings.Resolve 下面了，继续用旧名字
    # 会在每次构建时打弃用警告。
    settings.Resolve = {
      # 严格模式。"opportunistic" 会在对端不支持时**静默退回明文**，
      # 而中间设备只要把 853 端口一堵就能触发这个退回 ——
      # 那等于把防护做成了一个可以被攻击者关掉的开关，没有意义。
      DNSOverTLS = "true";

      # 关掉客户端侧的 DNSSEC 校验，这是**故意**的，不是偷懒：
      #
      #   DoT 保证的是「我确实在跟 Cloudflare 说话，中间没人动过报文」
      #   DNSSEC 保证的是「Cloudflare 给我的记录确实来自域名所有者」
      #
      # 而 Cloudflare 和 Google 自己就在做 DNSSEC 校验，校验失败的记录
      # 根本不会返回给我们。再在客户端做一遍，收益是防住「上游解析器
      # 说谎」这一种情况，代价是 systemd-resolved 的 DNSSEC 实现历来
      # 会在一些配置错误的域名上误判 Bogus 导致整个域名解析不了。
      #
      # 不写 "allow-downgrade"：那个模式在探测失败时会退回不校验，
      # 和上面 opportunistic 是同一类问题 —— 看起来开了，实际能被关掉。
      DNSSEC = "false";

      # 清空 systemd 编译进去的后备服务器（Cloudflare / Google 的明文地址）。
      #
      # 留着的话，一旦上面的 DNS 全部连不上，resolved 会**悄悄**用明文
      # 去问后备服务器 —— 于是「我开了加密 DNS」这句话在最需要它的时候
      # 恰好不成立，而且没有任何提示。宁可 fail closed：没有加密就没有解析，
      # 至少你会立刻发现，然后 `sudo dns plain` 显式地降级。
      FallbackDNS = "";

      # resolved 自己缓存。这一条是纯收益：本仓库这轮排查里
      # thinkpad「9 毫秒解析任何域名」其实是路由器在代答，
      # 代理关掉之后真实耗时是 280~360 毫秒。缓存把重复查询拉回毫秒级。
      Cache = "yes";
    };
  };

  # 服务器选择的依据是**在这个位置实测的**，不是抄来的默认值。
  # 2026-09 从日本用随机子域名（强制完整递归）测三次取平均：
  #
  #   1.1.1.1            93 ms      9.9.9.9            317 ms
  #   1.0.0.1           106 ms      149.112.112.112    191 ms
  #   8.8.8.8           130 ms
  #
  # Quad9 明显慢，所以不用。两家而不是一家：一家出问题另一家还在，
  # 而同一家的两个地址往往一起挂。
  #
  # `#` 后面是证书校验用的主机名。**不能省** —— DoT 是 TLS，
  # 没有主机名就只能拿 IP 去对证书，而那要求证书里有 iPAddress SAN。
  # 写上是明确的，省掉是碰运气。
  networking.nameservers = [
    "1.1.1.1#cloudflare-dns.com"
    "1.0.0.1#cloudflare-dns.com"
    "8.8.8.8#dns.google"
    "8.8.4.4#dns.google"
  ];

  # ============================================
  # 不让 NetworkManager 把 DHCP 的 DNS 推给 resolved
  # ============================================
  # 这一段前后写错过两次，所以把两条弯路都留在这里。
  #
  # 要挡的是什么：NetworkManager 默认会通过 D-Bus 把 DHCP 下发的 DNS
  # 注册成 resolved 的**链路级**服务器，而链路级优先于 resolved.conf 的
  # 全局设置。于是实际解析走的是路由器给的那两个，不是下面配的四个。
  # 它们不支持 DoT 就整机解析失败；**恰好支持的话更糟** ——
  # 看着一切正常，实际没做证书主机名校验，换个网络就坏。
  #
  # 关键在于 NetworkManager 这里是**两个独立的开关**，我先后拧错了两个：
  #
  #   dns=                 管「NM 写不写 /etc/resolv.conf」
  #   systemd-resolved=    管「NM 推不推给 systemd-resolved 的 D-Bus」
  #
  # 弯路一：`networking.networkmanager.dns = "none"`。只关了第一个，
  # D-Bus 照推，resolved 日志里明明白白：
  #     wlp4s0: Bus client set DNS server list to: 9.9.9.9, 8.8.8.8
  #
  # 弯路二：把 `ipv4.ignore-auto-dns` 写进 connectionConfig。
  # **那个属性不在 NM 的 `[connection]` 默认值支持列表里**，
  # 写进去不报错、也不生效 —— `nmcli con show <名字>` 里
  # 仍然是 `ipv4.ignore-auto-dns: no`。它只能配在具体连接上。
  # 见 https://www.networkmanager.dev/docs/api/latest/NetworkManager.conf.html
  #
  # 两个开关一起关才行。
  #
  # 代价说清楚：**DHCP 下发的内网域名也一并不要了。** 接入靠内网 DNS
  # 解析主机名的网络（公司内网、某些 VPN）时那些名字会失败，
  # 用 `sudo dns plain` 临时切回去。对「笔记本 + 家用网络」划算，
  # 换成办公环境就未必。
  #
  # 验证只有一个地方作数：`resolvectl status` 里**每个 Link 段的
  # DNS Servers 必须是空的**。光看 Global 段看不出问题 ——
  # Global 一直显示得好好的，而解析走的是链路级。
  networking.networkmanager = {
    dns = lib.mkForce "none";
    settings.main.systemd-resolved = false;
  };

  environment.systemPackages = [ dnsCmd ];
}

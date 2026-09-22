# 0014 — 路由器伪造 AAAA 应答，与改用加密 DNS

一个「虚拟机里 Claude Code 登录不了」的故障，根因是路由器上的一个勾选框。
从现象到根因走了七轮，其中**四轮我的假设是错的**。
修完之后在实施和验收上又错了三次 —— 都写在第五节里，
因为它们的性质不同：不是诊断时猜错，是**「能用」被当成了「按设计在用」**。

> 本文有意写得啰嗦。前半部分不预设网络知识，
> 每个概念用到时现场解释；**「给专业读者的速读版」在最后**，
> 已经熟悉 DNS 的人可以直接跳过去。
>
> 最终的配置在 [`modules/dns.nix`](../modules/dns.nix)，
> 日常用法在 [README.md](../README.md) 的「DNS」一节。

---

## 零、先把名词说清楚

后面每一段都要用到这四个概念。已经懂的请直接跳到第一节。

### DNS 是什么

你在浏览器里输入 `claude.ai`，但网络上传输数据只认数字地址
（`160.79.104.10` 这样的）。把名字翻译成数字的那套系统就是 DNS，
可以理解成**电话簿**。

每次打开一个没访问过的网站，你的电脑都要先查一次这本电话簿。

### A 记录和 AAAA 记录

互联网现在有两套地址体系并存：

| | 长什么样 | 查询类型叫 |
|---|---|---|
| IPv4 | `160.79.104.10` | **A** |
| IPv6 | `2600:3c03::f03c:93ff:febd:80f5` | **AAAA** |

IPv4 地址不够用了，IPv6 是接班人。现在两套并行，
所以**查一个域名，电脑通常会同时问两次**：「它的 IPv4 地址是？」
「它的 IPv6 地址是？」

这个「同时问两次、两个都有结果才算完」的行为，是本文故障的关键前提。

### NODATA 是什么

如果一个域名确实没有 IPv6 地址，正确的回答不是「不知道」，
而是一个叫 **NODATA** 的标准答复，意思是
「这个名字我认识，但它没有你要的这种记录」。

NODATA 是一个**有格式规定**的应答包，里面要带一条叫 SOA 的记录，
说明这个域名的管理信息。格式不对就是坏包。

### 这本电话簿是明文的

这是最要命的一点。**传统 DNS 查询是不加密的明文**，
路上任何设备（你的路由器、公共 WiFi 的接入点、运营商）
都能看见你在查什么，**也都能伪造一个假答案塞给你**，
而你的电脑没有任何办法分辨真假。

本文的故障就是这么来的。

---

## 一、问题症状

虚拟机里跑 `claude` 想登录，报：

```
Unable to connect to Anthropic services.
Connection to platform.claude.com timed out after 10 seconds.
```

但同一台虚拟机里：

```
curl https://platform.claude.com/   →  HTTP 200，1.1 秒
ssh -T git@github.com               →  正常
git pull                            →  正常
```

**网络明明是通的。**

更让人迷惑的是，同一个局域网里的 thinkpad 完全正常，
解析任何域名只要 9 毫秒。

---

## 二、诊断过程：四个错误假设

这一节保留了走错的路。**错误假设本身就是本文最有价值的部分** ——
它们每一个当时看都很合理，而正是「看起来合理」让人不去验证。

### 假设 1：网络路径有问题（错）

第一反应是虚拟机的网络出了问题。测下来：

```
platform.claude.com   tcp=0.25s  tls=0.37s  total=1.10s  code=200
```

它是所有测试站点里**最快**的一个。TLS 握手 0.12 秒完成。

**这个假设死了。** 但它留下一个新事实：curl 通，Claude Code 不通。

### 假设 2：是 Anthropic 的服务有问题（错）

既然网络通、站点通，那是不是服务端的事？

用 Node 测（Claude Code 是 Node 写的）：

```
node fetch https://platform.claude.com/  →  UND_ERR_CONNECT_TIMEOUT
```

再扩大范围：

```
github.com             FAIL  UND_ERR_CONNECT_TIMEOUT  10562ms
cache.nixos.org        FAIL  UND_ERR_CONNECT_TIMEOUT  10502ms
platform.claude.com    FAIL  UND_ERR_CONNECT_TIMEOUT  10499ms
api.anthropic.com      FAIL  UND_ERR_CONNECT_TIMEOUT  10497ms
```

**四个全挂，包括 GitHub。** 和 Anthropic 无关。

而且注意那个数字：每一个都是 **10.5 秒**。
整齐得不像网络延迟 —— 网络延迟不会四个站点分毫不差。
那是某个**超时设定**，不是某段路慢。

### 假设 3：是 IPv6 / Happy Eyeballs（错）

「curl 通、Node 不通」的经典成因是 Happy Eyeballs：
Node 优先试 IPv6，而虚拟机的网络只有 IPv4，于是 SYN 发出去石沉大海。

查了一下：

```
dns.lookup("platform.claude.com")  →  [ { address: '160.79.104.10', family: 4 } ]
```

**只有 IPv4，没有 IPv6。** 假设又死了。

但这一步意外带出了真正的线索 —— **那条查询本身花了 20 秒**。

### 假设 4：是 glibc 解析器的超时（错）

5 秒是 glibc 解析器的默认单次超时（`timeout:5`）。
20 秒 = 4 次。看起来严丝合缝。

于是用 `RES_OPTIONS` 把超时压到 1 秒来验证：

```
默认                          5.008 秒
RES_OPTIONS="timeout:1 ..."   5.007 秒      ← 完全没变
```

**没变。** 说明压根没走到解析器那一层。

同时 `dig` 直接问同一个 DNS 服务器，只要 218 毫秒。

> **这里我犯了一个真正的错误，值得单独记一笔。**
> 我让跑的两条 `dig` 都没指定记录类型，默认查的是 A。
> 也就是说我**测了两次 A**，然后拿它下了「DNS 服务器没问题」的结论。
> AAAA 从头到尾没测过 —— 而那才是坏的那一个。
>
> 教训：**对照实验要控制变量。** 换了域名、换了记录类型、
> 换了工具，任何一个没对齐，结论就不成立。

### 转折：逐个 NSS 模块试

Linux 解析主机名要走一条叫 NSS 的流水线，顺序写在
`/etc/nsswitch.conf` 里，这台机器上是：

```
hosts:  mymachines  files  myhostname  dns
```

`getent` 可以**指定只用其中一个**，于是四个分别计时：

```
只用 mymachines    0.002 秒
只用 files         0.002 秒
只用 myhostname    0.003 秒
只用 dns          15.019 秒      ← 就是它
```

到这里终于锁定：**慢在真正去问 DNS 服务器这一步**。

### 决定性证据：strace

不再猜，直接看那 15 秒停在哪个系统调用上：

```
32.026314  sendmmsg   一个 socket 上并发两个查询：A(\0\1) 和 AAAA(\0\34)
32.239117  recvfrom   A 的应答回来了                        212ms
32.239291  poll       继续等 AAAA ……                       超时 4.79s
37.030167  sendto     重发 A     → 0.4ms 就回来了
37.030634  sendto     重发 AAAA  →                          超时 5.00s
42.035965  sendto     再发 A     → 0.9ms 就回来了
42.037123  sendto     再发 AAAA  →                          超时 5.00s
           最终返回 A 记录 23.133.40.12，总计 15 秒
```

**A 查询每次都在 1 毫秒内应答，AAAA 查询一次都没被应答过。**

这也顺带解释了「curl 通、Node 不通」：
curl 拿到 A 记录就够了；而 Linux 标准的 `getaddrinfo`
在没指定协议族时**必须等 A 和 AAAA 都有结果**才返回。
Claude Code 走的是后者，10 秒超时到了，AAAA 还在等。

---

## 三、根本原因

### 抓包看到了什么

在上游那台机器（Bluefin）上抓 DNS 包，把 A 和 AAAA 的应答并排看：

| 查询 | IP TTL | 应答内容 |
|---|---|---|
| `A? claude.ai` | **64** | `1/0/0  claude.ai. A 160.79.104.10` ← 正常 |
| `A? fedoraproject.org` | **64** | `9/0/0` 九条 A 记录，全部正常 |
| `AAAA? claude.ai` | **255** | `0/1/0  ns: claude.ai. SOA . .` |
| `AAAA? rawtext.club` | **255** | `0/1/0  ns: rawtext.club. SOA . .` |
| `AAAA? fedoraproject.org` | **255** | `0/1/0  ns: SOA 44517 comment=^J^@^@^@^@` |
| `AAAA? neocities.org` | **255** | `0/1/0  ns: . OPT UDPsize=1232` |

两件事同时成立，相关性是百分之百：

**一、IP TTL 露馅了。**
TTL（Time To Live）是 IP 包上的一个计数器，每经过一台路由器减一，
初值通常是 64 或 255。真正从 Quad9 回来的包要跨十几跳，
到达时只可能是五六十 —— 表里 A 应答的 `64` 就是这个量级。

而 AAAA 应答的 **TTL 是 255，一跳都没减过**。
**这个包是从一跳之外发出的，也就是你自己的路由器。**

**二、内容是畸形的。**
那几条伪造的 NODATA 应答里：

- `SOA . .` —— SOA 记录的两个必填字段都写成了根，等于空白
- `ns: . OPT` —— OPT 记录被放进了 authority 段，
  而协议规定 OPT **只能**出现在 additional 段
- `comment=^J^@^@^@^@` —— 未初始化的内存被当成数据发了出来

### 两条判决性测试

**测试一：问一个根本不存在的 DNS 服务器。**

`192.0.2.1` 是 RFC 5737 定义的 TEST-NET-1，全球不可路由，
文档专用，**不可能有任何人在那里应答**。

```
故障时：  A    @192.0.2.1  →  NOERROR  8 msec     ← 有东西替它答了
         AAAA  @192.0.2.1  →  NOERROR  2 msec
修复后：  A/AAAA @192.0.2.1 →  timed out           ← 正确行为
```

能拿到应答，说明**查询压根没出门**，被中间设备截下自己答了。

**测试二：改走 TCP。**

DNS 默认走 UDP，但也支持 TCP。拦截设备通常只处理 UDP：

```
AAAA over UDP  →  ANSWER: 0，伪造的 NODATA
AAAA over TCP  →  ANSWER: 1，lwn.net. AAAA 2600:3c03::f03c:93ff:febd:80f5
```

**同一个域名、同一个服务器、同一秒，UDP 拿到假的，TCP 拿到真的。**

### 就是路由器上的一个勾选框

路由器是 **iKuai（爱快）**。官方文档，**网络设置 → DNS 设置**：

> **【禁止AAAA记录（IPv6）解析】**
> 勾选后，IPv6 的域名解析被禁止（3.7.7 及以上版本支持）

以及同一页的：

> **【强制客户端DNS代理】**
> 无论客户机设置什么 DNS 地址，都会强制使用此页面配置的 DNS 代理进行解析

两条合起来解释了全部现象。

### 完整的因果链

```
路由器勾了「禁止 AAAA 记录解析」
        │
        ├─ 它的实现方式不是「透传上游的 NODATA」，
        │  而是**自己拼一个 NODATA 包顶回去**，且拼得不合规范
        │
        └─ 配合「强制客户端 DNS 代理」，这个行为对整个局域网生效，
           而且**换任何 DNS 服务器都没用** —— 查询根本到不了那些服务器
        │
        ▼
    A 查询如实转发（所以看起来一切正常）
    AAAA 查询被伪造应答顶回（所以只有 IPv6 解析坏掉）
        │
        ├──▶ thinkpad：glibc 宽容，收下畸形包当作「没有 IPv6」，
        │              一跳就回来，9 毫秒。**一直在被欺骗，只是不吭声。**
        │
        └──▶ Bluefin：systemd-resolved 严格，校验不过，判 <invalid-reply>
             丢弃并回 SERVFAIL
                  │
                  ▼
             虚拟机的 dnsmasq 拿到 SERVFAIL，不转发
                  │
                  ▼
             虚拟机里的 glibc 等 AAAA 等到天荒地老，5 秒一轮重试三轮
                  │
                  ▼
             Claude Code 的 10 秒预检超时 → 「连不上 Anthropic」
```

**一个勾选框，五层传递，最后表现成一个和 DNS 毫无字面关联的报错。**

### 谁的锅

严格说是 **iKuai 的实现 bug**。「不给 IPv6 解析」这个需求本身合理，
但正确做法是返回一个**合规的** NODATA，而不是拼一个畸形包。

systemd-resolved 拒收是**对的** —— 它在做它该做的校验。
glibc 收下才是隐患：它让这套欺骗在 thinkpad 上悄无声息地生效了几个月。

---

## 四、已实施的修复

### 第一层：关掉路由器上那两个开关（根因）

iKuai → **网络设置 → DNS 设置**：

- 取消勾选 **【禁止AAAA记录（IPv6）解析】**
- 关闭 **【强制客户端DNS代理】**

改完当场验证通过：

```
问黑洞 192.0.2.1   A/AAAA 双双 timed out              ← 拦截没了
AAAA over UDP      2600:3c03::f03c:93ff:febd:80f5     ← 真记录
```

> **一个意外收获：** 关掉强制代理之后，解析新域名从「9 毫秒」变成
> 280~360 毫秒。之前那个 9 毫秒是**路由器在本地代答**，不是真的快。
> 路由器 DHCP 下发的 DNS 是 `114.114.114.114` / `223.5.5.5`，
> 从日本过去往返 95 毫秒 —— 代理关掉之后这个代价就真的要付了。
> 顺手把路由器 DHCP 里的 DNS 换成了 `1.1.1.1` / `8.8.8.8`。

### 第二层：仓库改用加密 DNS（防同类问题）

新增 [`modules/dns.nix`](../modules/dns.nix)：systemd-resolved +
**DNS-over-TLS 严格模式**。

```nix
services.resolved.settings.Resolve = {
  DNSOverTLS = "true";
  DNSSEC = "false";
  FallbackDNS = "";
  Cache = "yes";
};
networking.nameservers = [
  "1.1.1.1#cloudflare-dns.com"
  "1.0.0.1#cloudflare-dns.com"
  "8.8.8.8#dns.google"
  "8.8.4.4#dns.google"
];
networking.networkmanager = {
  dns = lib.mkForce "none";              # 不写 /etc/resolv.conf
  settings.main.systemd-resolved = false; # 不推给 resolved 的 D-Bus
};
```

DoT 把 DNS 查询装进 TLS 加密通道（853 端口）。
中间设备既看不见你在查什么，**也没法伪造应答** ——
它改一个字节，TLS 的完整性校验就会失败。

同时提供两条逃生命令，见下面第六节。

---

## 五、为什么这样解决

### 为什么根因修了还要加 DoT

因为**下次换个网络还会遇到**。酒店、机场、别人家的 WiFi、
运营商的透明缓存 —— 明文 DNS 在任何一段路上都可能被改。

这次花了七轮才定位，而 DoT 让这一整类问题**从结构上不可能发生**。
不是绕过这次的故障，是让同类故障不必再查一遍。

### 为什么是严格模式，不是 opportunistic

`DNSOverTLS=opportunistic` 会在对端不支持加密时**静默退回明文**。

听起来是「兼容性更好」，实际是**把防护做成了一个攻击者能关掉的开关** ——
中间设备只要把 853 端口一堵，就触发了这个退回，
然后一切照旧被伪造，而你不会收到任何提示。

同理 `DNSSEC` 不写 `allow-downgrade`。
**「看起来开了、实际能被对端关掉」的安全措施等于没有。**

### 为什么 `FallbackDNS` 要清空

systemd 编译进去了一组后备 DNS 服务器的**明文**地址。
留着的话，加密服务器一连不上，resolved 就会悄悄用明文去问后备 ——
「我开了加密 DNS」这句话恰好在最需要它的时候不成立。

宁可 fail closed：没有加密就没有解析。至少你会**立刻发现**，
然后用 `sudo dns-plain` 显式地降级，而不是被蒙在鼓里。

### 为什么关掉客户端的 DNSSEC 校验

这两件事保证的不是同一回事，容易混：

| | 保证什么 |
|---|---|
| **DoT** | 我确实在跟 Cloudflare 说话，中间没人动过报文 |
| **DNSSEC** | Cloudflare 给我的记录确实来自域名所有者 |

而 Cloudflare 和 Google **自己就在做 DNSSEC 校验**，
校验失败的记录根本不会返回给我们。再在客户端做一遍，
收益是防住「上游解析器说谎」这一种情况，
代价是 systemd-resolved 的 DNSSEC 实现历来会在一些配置错误的域名上
误判 Bogus，导致整个域名解析不了。

用 DoT 确保「我信任的那个解析器没被冒充」，然后信任它的校验结果 ——
这是标准做法。

### 为什么要挡住 DHCP 下发的 DNS —— 以及我在这里连错三次

这是整个模块里最容易漏、漏了就**静默失效**的一条。
我前后写错两版才改对，验收判据还写错了第三次，三条弯路一起记下来。

**要挡的是什么。** NetworkManager 默认会把 DHCP 下发的 DNS 服务器
注册成 resolved 的**链路级**服务器，而链路级优先于 `resolved.conf`
里的全局设置。于是：

```
实际解析走的是路由器给的那两个，不是配置里那四个带主机名的
  ├─ 它们不支持 DoT  →  TLS 握手全失败  →  整机解析不了任何域名
  └─ 它们恰好支持 DoT →  看着一切正常，实际上没做证书主机名校验，
                         而且换一个网络就会坏
```

**关键在于 NetworkManager 这里是两个独立的开关**，而我先后拧错了两个：

| 开关 | 管什么 |
|---|---|
| `dns=` | NM 写不写 `/etc/resolv.conf` |
| `systemd-resolved=` | NM 推不推给 systemd-resolved 的 D-Bus |

**弯路一：只写 `networking.networkmanager.dns = lib.mkForce "none"`。**
只关了第一个开关。切换之后 `resolvectl status` 里赫然还是：

```
Link 3 (wlp4s0)
Current DNS Server: 9.9.9.9
       DNS Servers: 9.9.9.9 8.8.8.8
```

而 resolved 的日志写得明明白白：

```
wlp4s0: Bus client set DNS server list to: 9.9.9.9, 8.8.8.8
```

**弯路二：把 `ipv4.ignore-auto-dns` 写进 `connectionConfig`。**
看起来更对症 —— 让 NM 根本不接收 DHCP 的 DNS，它就没东西可推。
但 **NM 的 `[connection]` 默认值段根本不支持这个属性**。
写进去不报错、生成的 `NetworkManager.conf` 里也确实有那两行，
可 `nmcli con show <连接名>` 里仍然是：

```
ipv4.ignore-auto-dns:    no
```

`ignore-auto-dns` 只能配在**具体的连接**上（`nmcli con mod ...`），
而 WiFi 连接本身是非声明式的运行时状态（里面存着 PSK，属于 C 类），
所以那条路在这个仓库里本来也走不通。

**正确写法是两个开关一起关：**

```nix
networking.networkmanager = {
  dns = lib.mkForce "none";
  settings.main.systemd-resolved = false;
};
```

**而这两次错误能被发现，都是因为验证时多看了一段输出。**
第一次时那台机器**解析完全正常** —— 因为路由器的 DHCP 恰好发的是
9.9.9.9 和 8.8.8.8，这两个都支持 DoT。`resolvectl query` 成功、
`Global` 段显示得好好的，只有 `Link` 段露了馅 —— 那里赫然列着
`DNS Servers: 9.9.9.9 8.8.8.8`。

教训：**验证要看完整输出，别只看你预期会变的那部分。**
「能用」不等于「按设计在用」。
还有一条：**改完配置要重连网络再验** ——
已经激活的连接不会自动重新应用。

**还有第三次错误，这次错在「判据」本身。**

修好之后我告诉 Toru 用两条判据验收：Link 段的 `DNS Servers` 为空，
以及 `resolvectl query` 末尾那句 `-- link: <网卡>` 消失。
他报告两条都满足，我就把第二条写进了文档。

**第二条是错的。** 后来在已经配置正确的 thinkpad 上查一个全新域名：

```
tildeverse.org IN AAAA 2a01:4f8:252:3e22::50    -- link: wlp4s0
-- Data was acquired via local or encrypted transport: yes
-- Data from: network
```

同一台机器的 Link 段是干净的（`Current Scopes` 里没有 `DNS`，
也没有 `DNS Servers:` 行），`-- link:` 却照样出现。

**`-- link:` 标的是这次查询的出口网卡，不是链路级 DNS 服务器的信号。**
走全局 DNS 时它一样会出现；只有答案来自 resolved 的缓存、根本没走网络时
才没有。Toru 当时查的 `lwn.net` 多半正是命中了缓存。

所以这又是同一个毛病：**对照实验没控制变量。**
一次是换了记录类型（A 对 AAAA），一次是换了缓存状态（冷查对热查）。
两次都得出了自信但错误的结论，而且第二次还写进了文档 ——
文档里的错误判据比没有判据更糟，它会让下一个人把正常状态误判成故障。

**正确的判据只有一条：`resolvectl status` 里每个 Link 段的
`Current Scopes` 不含 `DNS`、且没有 `DNS Servers:` 那一行。**

### 为什么选 Cloudflare 和 Google，不选 Quad9

**在这个位置实测的**，不是抄的默认值。
2026-09 从日本用随机子域名（强制完整递归，避开一切缓存）测三次取平均：

```
1.1.1.1            93 ms      9.9.9.9            317 ms
1.0.0.1           106 ms      149.112.112.112    191 ms
8.8.8.8           130 ms
```

Quad9 明显慢。用两家而不是一家：一家出问题另一家还在，
而同一家的两个地址往往一起挂。

> `#` 后面的主机名**不能省**。DoT 是 TLS，要验证证书；
> 没有主机名就只能拿 IP 去对，那要求证书里带 iPAddress SAN。
> 写上是明确的，省掉是碰运气。

---

## 六、后续注意事项

### 排查 DNS 问题时，先跑这一条

```bash
nix shell nixpkgs#dnsutils -c dig +time=3 +tries=1 A example.org @192.0.2.1
```

`192.0.2.1` 全球不可路由，**正常必须超时**。
能拿到应答就说明有中间设备在截 UDP/53。

**十秒钟排除一整类原因。** 这次绕了四个错误假设，
就是因为没有先跑它。

### captive portal 要手动降级

酒店 / 机场 / 咖啡馆的认证页面会拦掉 853 端口。这时候 DNS 全挂、
连认证页面都打不开。两条命令（定义在 `modules/dns.nix`）：

```bash
sudo dns-plain    # 临时切回网关的明文 DNS，去过认证
sudo dns-dot      # 认证完切回加密
```

只改运行时状态，不动配置文件 —— 忘了切回来的话，
重连网络或重启就自动回到 DoT。

### 改 `modules/dns.nix` 之前先确认 853 端口通

否则切换完就是整机没有 DNS（`FallbackDNS` 是空的）。
服务器列表里的每一个都要过：

```bash
nix shell nixpkgs#dnsutils -c dig +tls +tls-hostname=cloudflare-dns.com \
  +time=5 +tries=1 A example.org @1.1.1.1

nix shell nixpkgs#openssl -c openssl s_client -connect 1.1.1.1:853 \
  -servername cloudflare-dns.com -verify_return_error </dev/null 2>&1 \
  | grep 'Verify return code'
```

证书也要验 —— `DNSOverTLS=true` 会因为证书不过而拒绝连接。

### 日常验证

```bash
resolvectl status | head -20          # DNS Servers 是那四个带 # 主机名的
resolvectl statistics                 # Cache Hits 在涨
resolvectl query --type=AAAA lwn.net  # 拿到地址，不是 SERVFAIL
sudo ss -tnp 'dport = :853'           # 有到 1.1.1.1:853 的连接
```

### 这个网络还没有 IPv6

`ip -6 addr show scope global` 在 thinkpad 上没有任何输出 ——
这个网络目前根本没跑通 IPv6。AAAA 现在能正确解析了，
但程序拿到 IPv6 地址后连不上、要回落到 IPv4。

现代的 Happy Eyeballs 回落只有几百毫秒，比之前动辄 5~20 秒好得多，
但**这是一件独立的、还没做的事**：iKuai 的 IPv6 配置。

---

## 七、给专业读者的速读版

**故障**：libvirt 虚拟机内 `getaddrinfo` 对每个未缓存域名耗时 5 秒的整数倍，
Node/undici 的 10 秒 `connectTimeout` 因此必然触发，
表现为 Claude Code `UND_ERR_CONNECT_TIMEOUT`。curl 不受影响。

**根因**：iKuai 路由器启用了「禁止 AAAA 记录解析」+「强制客户端 DNS 代理」，
透明劫持 LAN 内全部 UDP/53，对 A 查询如实转发、对 AAAA 查询注入伪造的
NODATA 应答。伪造包不合规（SOA 的 MNAME/RNAME 为根、OPT RR 出现在
authority 段、rdata 含未初始化内存），IP TTL=255 暴露了它是本地注入。

**为什么表现不一致**：
`glibc` 的 `dns_packet` 处理宽松，接受该包并视作 NODATA；
`systemd-resolved` 的 `dns_packet_validate_reply()` 判定
`DNS_TRANSACTION_INVALID_REPLY` 并回 SERVFAIL。
虚拟机的链路是 guest → libvirt dnsmasq → host resolved → 路由器，
resolved 的 SERVFAIL 导致 dnsmasq 不应答，guest 侧表现为查询丢失，
glibc 按 `timeout:5 attempts:2` 重试。

**关键诊断手段**：

| 手段 | 排除/确认了什么 |
|---|---|
| `getent -s <service> ahosts` | 定位到是 `dns` 这个 NSS 模块，而非 `mymachines` / `files` |
| `strace -tt -T -e trace=network` | A 应答 <1ms、AAAA 应答从未到达 |
| `dig @192.0.2.1`（TEST-NET-1） | 能应答 = 存在透明拦截 |
| `dig +tcp` vs UDP | 同名同服务器结果相反 = 只劫持 UDP |
| `tcpdump` 看 IP TTL | 255 = 本地注入，64 = 真实上游 |
| `resolvectl log-level debug` | `now complete with <invalid-reply>` |

**修复**：路由器侧取消两个勾选（根因）；仓库侧 `modules/dns.nix`
启用 systemd-resolved + 严格 DoT（`DNSOverTLS=true`、`FallbackDNS=` 清空、
`DNSSEC=false` 依赖上游校验、NetworkManager 的 `dns=none` 加 `systemd-resolved=false`（两个独立开关）
以阻止 DHCP 下发的非 DoT 服务器成为链路级服务器）。

**四个被推翻的假设**（按顺序）：网络路径 → Anthropic 服务端 →
Happy Eyeballs/IPv6 → glibc 解析器超时。
外加实施后验证时发现的第五、第六个：先是以为 `networkmanager.dns = "none"` 能挡住
DHCP 下发的 DNS（它只管 resolv.conf），又以为 `ipv4.ignore-auto-dns` 能写进
`connectionConfig`（NM 的 `[connection]` 段不支持这个属性）。
其中第三、第四个被 `dns.lookup` 返回 `family: 4` 和
`RES_OPTIONS` 无效各自证伪。

**两个方法论错误**：一、用两次 A 查询的 `dig` 结果去论证「DNS 服务器没问题」，
而故障在 AAAA —— 对照实验换了变量结论就不成立。二、只看 `resolvectl status` 的
Global 段就认定配置生效，而解析实际走的是 Link 段 —— 验证要看完整输出。
（判据是 Link 段有没有 `DNS Servers:` 行；`resolvectl query` 末尾的
`-- link: <网卡>` 标的是出口网卡，走全局 DNS 时照样出现，不能当判据 ——
这一条我也先写错过，见第五节。）

---

## 相关文档

- [`modules/dns.nix`](../modules/dns.nix) —— 最终配置，注释里写了每个选项的取舍
- [README.md](../README.md) 的「DNS」一节 —— 日常用法与验证
- [CLAUDE.md](../CLAUDE.md) 的「DNS」一节 —— 改这块之前必须知道的四件事
- [MIGRATION.md](../MIGRATION.md) 第 8 节 —— 新机器的 DNS 验证清单
- [`0013`](0013_REFIND_BOOT.md) —— 同样是「构建通过 ≠ 实机可用」的一轮
- iKuai 官方 DNS 设置文档：<https://www.ikuai8.com/support/ymgn/lyym/wlsz/dns.html>

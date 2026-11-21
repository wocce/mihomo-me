# 四种典型组合

> 下面所有命令都在 **root** 下执行；`mlr` 指 `/usr/local/bin/mlr`。

## 组合 A：v6 直连入口 + 本机出网（最快上手）

适用：客户端自己有 IPv6（手机蜂窝、部分家宽），只想把线路做成一个可用代理。

```bash
sudo mlr            # 首次向导
# 入口 -> 1. IPv6 公网直连
# 出口 -> 1. 本机直出
# 协议 -> 默认 SS2022
sudo mlr --info     # 抄 ss:// 链接
```

服务端配置长这样：

```yaml
listeners:
  - name: in-ss
    type: shadowsocks
    port: 35688
    listen: "::"
    cipher: 2022-blake3-aes-256-gcm
    password: "<base64 密钥>"
    udp: true
rules:
  - MATCH,DIRECT      # 本机就是出口
```

放行：

```bash
ip6tables -I INPUT -p tcp --dport 35688 -j ACCEPT
ip6tables -I INPUT -p udp --dport 35688 -j ACCEPT
```

## 组合 B：v6 直连入口 + 日本落地

适用：要日本 IP（流媒体、AI 服务），或者不想让目标站看到国内线路 IP。

```bash
# ① 先在落地机上装同一套，做成「本机直出」
#    落地机 -> mlr -> 2. 本机直出 -> 协议 SS2022 -> mlr --info 抄参数
# ② 回到线路机
sudo mlr
# 入口 -> 1. IPv6 公网直连
# 出口 -> 2. 指定落地机 -> 填 落地IP:端口 + cipher + password
# 分流 -> 1. 全部走出口（或 2. 国内直连）
```

生成的出口段：

```yaml
proxies:
  - name: LandingNode
    type: ss
    server: 203.0.113.10
    port: 35688
    cipher: 2022-blake3-aes-256-gcm
    password: "<落地机密钥>"
    udp: true
    ip-version: ipv6      # 落地机只能走 v6 连时才需要
rules:
  - MATCH,Landing
```

延迟增量 ≈ 线路机→落地机的 RTT。联通 v6 到东京一般 +30~50ms。

## 组合 C：商家 IPv4 NAT 入口

适用：商家给的是 `1.2.3.4:20000 → 内网 10.3.0.50:20000` 这种 NAT 映射，家里没有 IPv6。

```bash
sudo mlr
# 入口 -> 2. 供应商 IPv4 NAT 入口
#   公网 IPv4: 1.2.3.4
#   公网端口: 20000
#   映射到本机端口: 20000
```

若内部端口和监听端口（默认 35688）不同，脚本会自己加：

```bash
iptables -t nat -A PREROUTING -p tcp --dport <内部端口> -j REDIRECT --to-ports 35688
iptables -t nat -A PREROUTING -p udp --dport <内部端口> -j REDIRECT --to-ports 35688
# 装了 iptables-persistent 才会自动持久化，否则重启失效，记得 apt install iptables-persistent
```

链接里会自动用 `1.2.3.4:20000`，不用手改。

## 组合 D：自有公网 v4 机器做中转

### D1 · Realm（中转机有 IPv6）

链路：客户端 → 中转机(v4) → 线路机(v6)。

中转机上：

```bash
curl -fL -o /tmp/realm.tar.gz \
  https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-musl.tar.gz
tar -xzf /tmp/realm.tar.gz -C /usr/local/bin --strip-components=1 && chmod +x /usr/local/bin/realm

cat > /etc/realm/config.toml <<'TOML'
[network]
no_tcp = false
use_udp = true

[[endpoints]]
listen = "0.0.0.0:35688"
remote = "[2408:xxxx:xxxx::1]:35688"
TOML
```

`mlr` 的「入口 → 3 → 1」会把这段完整打印出来，含 systemd 单元和放行命令。

### D2 · WireGuard（中转机没有 IPv6）

链路：线路机**主动**经 NAT v4 拨到中转机，建隧道；客户端连中转机的 v4 端口，被 DNAT 进隧道。

中转机 `wg0.conf` 关键行：

```ini
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = <srv 私钥>
PostUp = iptables -t nat -A PREROUTING -p tcp --dport 35688 -j DNAT --to-destination 10.66.66.2:35688
PostUp = iptables -t nat -A PREROUTING -p udp --dport 35688 -j DNAT --to-destination 10.66.66.2:35688
PostUp = iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -j MASQUERADE

[Peer]
PublicKey = <线路机 公钥>
AllowedIPs = 10.66.66.2/32
```

线路机（本机）：

```ini
[Interface]
Address = 10.66.66.2/24
PrivateKey = <线路机 私钥>
Table = off

[Peer]
PublicKey = <中转机 公钥>
Endpoint = 中转机v4:51820
AllowedIPs = 10.66.66.1/32
PersistentKeepalive = 25
```

`Table = off` 是刻意的：只加一条到 10.66.66.0/24 的路由，不动默认路由，
避免把线路机自己的出网也推进隧道。mihomo 监听 `::`，会顺带覆盖 `10.66.66.2`。

前提：线路机 NAT v4 能出网（`mlr --detect` 里 `v4 出网` 有值）。完全没有 v4 出网时只能用 D1。

## 判断自己属于哪种

```bash
sudo mlr --detect
```

- `IPv6: 2408:...`、`v4 出网: 不可用`、`内网 IPv4: 10.x` → 典型 v6-only 线路机，走 A/B。
- 有 `v4 出网` 但没有公网 v4 → C 或 D2。
- 有公网 v4 → D1 最省事（一跳转发，无隧道开销）。

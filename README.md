# mihomo-relay · mlr

把「只有 IPv6 的国内线路机」变成一个能用的入口（中转），出口可以是本机，也可以是境外落地机。
一个脚本、一个菜单，全部走 CLI，没有任何 Web 面板。

针对的典型机型：**IPv6 公网 + 内网 IPv4**（利群 cnc／各类 v6-only 小鸡）。
家宽没有 IPv6 也能用——用商家的 IPv4 NAT 入口，或自己有公网 v4 的机器做中转。

```
客户端 ──┬─ IPv6 直连 ─────────────────┐
         ├─ 商家 v4 NAT ───────────────┤
         └─ 自有 v4 中转(Realm/WG) ────┤
                                       ▼
                              ┌────────────────┐
                              │  线路机 (mlr)   │  SS2022 / Reality / VLESS-Enc
                              └───────┬────────┘
                                      │ 选择出口
                        ┌─────────────┴──────────────┐
                        ▼                            ▼
                  本机直出                     落地机 (日本/新加坡…)
                  (换入口用)                  (换 IP、解锁、隐私)
```

## 快速开始

```bash
# 1) 装到 /usr/local/bin/mlr
curl -fsSL https://raw.githubusercontent.com/yourname/mihomo-relay/main/install.sh | bash
# 或仓库内：sudo bash install.sh

# 2) 跑起来
sudo mlr
```

首次运行会走三步向导：入口 → 出口 → 生成协议并启动。之后每次进主菜单。

## 三种入口（决定客户端怎么连进来）

| 入口 | 适用 | 脚本做的事 |
|---|---|---|
| **IPv6 公网直连** | 客户端自己有 IPv6；不想折腾 | 自动填链接里的地址，只提示防火墙放行 |
| **商家 IPv4 NAT** | 商家给了 `公网v4:端口 → 内网v4:端口` | 记录映射；内部端口与监听端口不一致时自动加 iptables 重定向并持久化 |
| **自有公网 v4 中转** | 自己另有一台带 v4 的机器 | 生成 **Realm**（中转机需有 v6）或 **WireGuard**（中转机无 v6 也行）双端配置，可直接粘 |

WireGuard 方案是在**本机主动拨出**去连中转机：即使本机只有内网 v4，只要 NAT 能出网就能用；
中转机把 `公网端口` DNAT 到隧道里的 `10.66.66.2:监听端口`，回程 MASQUERADE。

## 两种出口

- **本机直出**：协议直接跑在本机，出网 IP 就是本机。适合只想要一个稳定入口、或用它当落地机。
- **指定落地机**：填落地机的 `IP/域名 + 端口 + 协议 + 凭据`，流量经落地机出网。
  落地机若也用本脚本部署，直接把它「6. 查看链接」里的客户端片段抄过来即可。

支持落地协议：Shadowsocks(2022)、VLESS Reality、Trojan、VLESS Encryption(PQ)。
落地机只能走 IPv6 连时，选 `ipver=ipv6`，会强制出站走 AAAA。

## 三种入口协议

- **Shadowsocks 2022**（`2022-blake3-aes-256-gcm`）：默认，UDP 全支持，客户端兼容性最好，抗主动探测。
- **VLESS Reality**：TLS 伪装，`www.microsoft.com` 之类做 SNI，TCP 单栈。
- **VLESS Encryption (PQ)**：`mlkem768x25519plus` 后量子加密，密钥由 `mihomo generate vless-x25519` 生成，需要较新客户端。

端口、密钥、UUID、short-id 全部本地随机生成，不上传任何地方。

## 菜单一览

```
 1. 入口配置      IPv6直连 / IPv4 NAT / 自有v4中转
 2. 出口配置      本机直出 / 指定落地机
 3. 协议配置      SS2022 / VLESS Reality / VLESS Enc PQ
 4. 分流配置      全部走出口 / 国内直连
 5. 应用并重启    生成 → mihomo -t 校验 → 重启 → 失败自动回滚
 6. 查看链接      ss:// vless:// + mihomo 客户端 YAML 片段
 7. 状态/自检     监听、出口 IP、放行命令、最近日志
 8. GEO 更新
 9. 备份/还原/卸载
10. 更新脚本
```

命令行：

```bash
mlr --info       # 打印当前入口/出口/链接
mlr --status     # 状态与自检
mlr --apply      # 按当前状态重新生成并重启
mlr --detect     # 网络环境探测（v6 / 内网 v4 / v4 出网）
mlr --selftest   # 配置矩阵自检（27 份配置全部过 mihomo -t）
mlr --uninstall
mlr --update
```

## 设计上的几个取舍

- **配置由脚本整份生成**，不做零散 sed 修改：`/etc/mihomo/config.yaml` 头注释会写明。
  想改细节就改脚本，或者改完用「9 → 1」备份。
- **改配置前一定先 `mihomo -t`**，不通过就不重启；重启后起不来会自动回滚到上一份备份。
- **状态存在 `/etc/mihomo/mlr.state`**（600 权限），卸载不删配置，重装后状态还在。
- **不依赖 jq / unzip**：只用了 curl、openssl（可选）和 mihomo 自身。
- 上线前建议先跑 `mlr --selftest`，它会在临时目录里渲染全部分支配置并逐个校验。

## 目录

```
mlr                主脚本（单文件，约 1.2k 行）
install.sh         安装器（本地/远程两种模式）
docs/topology.md   四种典型组合的完整说明
.github/workflows   CI：bash -n + shellcheck + selftest
```

## 安全提醒

- 入口端口会暴露在公网（尤其走商家 NAT），默认就用 SS-2022，别用 `aes-256-gcm` 弱口令。
- 本机出口模式记得把分流设成 `MATCH,出口`；如果误留 `DIRECT` 兜底，客户端会漏真实 IP。
- Reality 的 `dest` 要挑一个真实存在、支持 TLS1.3 的站点，别用会被墙的域名。

## License

MIT

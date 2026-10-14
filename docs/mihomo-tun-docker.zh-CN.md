# Mihomo TUN 与 Docker 容器共存方案

## 目标

让 Rakazo Computer 容器通过宿主机的 Mihomo TUN 访问公网，同时保持 Rakazo 服务、PostgreSQL 和 Computer 控制连接在 Docker 私网中正常通信。

## 现状与原因

- Computer 容器使用独立的 Docker 网桥，不会继承宿主机终端的代理环境变量。宿主机的代理只监听回环地址时，容器也无法直接使用它。
- Mihomo 的 `auto-route` 将流量路由到 TUN；`auto-redirect` 还会安装 TCP 重定向规则。Docker 网桥流量可能经过这些宿主机规则。
- 先前的启动故障发生在 Mihomo 已退出、重定向规则仍留在宿主机时：容器到 PostgreSQL 的连接被送往失效端口。
- 修改前的 `clashctl` 用 `SIGKILL` 停止 Mihomo，进程没有机会清理 TUN 路由和防火墙规则。
- 若订阅配置把 `dns.direct-nameserver` 设为 `system`，系统 DNS 在 TUN 的 Fake IP 模式下可能返回 `198.18.0.0/15` 的虚拟地址，导致判为直连的模型接口连接超时。

Mihomo 对 `auto-route`、`auto-redirect` 和 `route-exclude-address` 的定义见[官方 TUN 文档](https://wiki.metacubex.one/en/config/inbound/tun/)。

## 实际故障：开启 TUN 后 Chief 提示 Connection error

开启 TUN 后，Computer 容器访问 Google 返回 HTTP 200，Rakazo `/ready` 返回 `{"ok":true,"degraded":false}`，但 worker 访问模型接口时 TLS 连接失败。这将故障定位到模型调用链路。

Mihomo 日志显示该模型域名命中 `GeoIP/cn` 直连规则，随后尝试拨号到 `198.18.0.0/15` 内的 Fake IP 并超时。运行配置中的 `dns.direct-nameserver` 来自订阅，值为 `system`；在当前 TUN 环境里，直连时重新解析仍得到了 Fake IP。[Mihomo DNS 解析流程](https://wiki.metacubex.one/en/config/dns/diagram/)说明了直连出口重新解析的步骤。

修复是在 Mixin 中覆盖订阅的直连 DNS：

```yaml
dns:
  direct-nameserver:
    - https://223.5.5.5/dns-query
```

重新生成运行配置后，通过 Mihomo 控制接口热加载，返回 HTTP 204；**无需重启 TUN**。复测时，worker 对模型接口的匿名 HTTPS 请求返回预期的 HTTP 401，说明网络和 TLS 已通，401 仅表示该探测请求未携带模型凭据。Computer 访问 Google 仍返回 200，Rakazo `/ready` 仍正常。该复测没有代替一次已登录的 Chief 对话；最终应在界面重试模型调用。

## 修改方案

1. 保留 `tun.auto-route: true`，设置 `tun.auto-redirect: false`，避免安装曾影响容器连接的 TCP 重定向规则。公网目的地址仍可通过 TUN 路由。
2. 在 `tun.route-exclude-address` 中加入 `172.16.0.0/12`，让当前使用 `172.18.0.0/16` 和 `172.19.0.0/16` 的 Docker 私网目的地址绕过 TUN。若 Docker 日后改用其他网段，应按实际网段更新该列表。不要按来源网桥排除所有 Computer 流量，否则它访问公网也不会走 TUN。
3. 将 `clashctl` 所有停止 Mihomo 的路径改为发送 `SIGTERM` 并等待退出；超时则报错，不在未清理规则时直接启动另一个实例。TUN 实例由具有相应权限的路径停止。
4. 在切换 TUN 模式或重启内核时，先让旧进程退出，再启动新进程；关闭 TUN 时更新配置并启动普通代理。
5. 将 `dns.direct-nameserver` 指向独立的 DoH 服务器，让直连连接重新解析为真实地址，避免经 `system` DNS 再次取得 Fake IP。该地址应按部署地的可达性选择；修改后可热加载运行配置，无需切换 TUN。

## 验证

先检查配置与脚本语法，再在维护窗口中执行 `clashtun on`。开启后检查：

```bash
curl --noproxy '*' http://127.0.0.1:3100/ready
COMPUTER_CONTAINER=$(docker ps --filter label=rakazo.managed=true --format '{{.Names}}' | head -n 1)
docker exec "$COMPUTER_CONTAINER" curl -L -sS -o /dev/null -w '%{http_code}\n' --max-time 15 https://www.google.com
```

第一项应返回就绪状态，第二项应返回 HTTP 状态码。还应实际打开 Computer 浏览器访问 Google，并检查 Chief 的一次模型调用；若模型域名按直连规则处理，Mihomo 的实际拨号目标不应仍是 `198.18.0.0/15` 的 Fake IP。执行 `clashtun off` 后再次检查就绪状态，并确认宿主机没有残留的 Mihomo 路由和重定向入口：

```bash
ip rule show
sudo iptables -t nat -S PREROUTING
```

如果 Computer 无法访问 Google，应检查实际生成的策略路由和容器 DNS；如果内部连接失败，应检查其目的地址是否属于排除网段，以及宿主机是否留有旧规则。不要直接清空 Docker 或其他程序的防火墙规则。

修改停止逻辑不会自动清理此前由强制终止留下的旧规则。若开启前已经存在与当前 Mihomo 进程不匹配的规则，应先确认规则归属，再单独清理。

## 回退

执行 `clashtun off`，确认 Rakazo 就绪和 Mihomo 规则已清理。需要恢复原 TUN 行为时，移除新增的私网排除项并恢复 `auto-redirect`，然后重新生成 Mihomo 运行配置。`clashctl` 的正常退出逻辑应保留。

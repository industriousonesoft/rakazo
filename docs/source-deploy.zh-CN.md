# 本机源码部署 Rakazo

本教程从仓库源码构建并运行 Rakazo 的完整 Docker Compose 服务：PostgreSQL、API、Worker、Web 和本地 Docker 电脑。服务只监听本机回环地址 `127.0.0.1`，适合个人设备上的常驻实例。公网部署、HTTPS 和多用户运维请看[自托管指南](./self-host.md#public-single-vm-deployment)。

运行 Rakazo 不要求在本机推理大语言模型。首次登录后可以在界面中连接模型服务；外部应用集成也都是可选项。

## 1. 检查运行环境

需要 64 位 Linux、Docker Engine、Docker Compose 插件、Git 和 OpenSSL。Docker Engine 建议 26 或更新版本；本流程在容器中构建应用，宿主机不需要安装 Node.js 或 pnpm。构建过程需要下载基础镜像和依赖。每个启动的 Docker 电脑默认最多使用 2 GiB 内存、2 个 CPU；多电脑并发要预留更多资源。

### 在 Ubuntu 20.04 上安装 Docker Engine、Compose 与 Buildx

以下步骤适用于 Ubuntu 20.04 的 `arm64` 或 `amd64` 设备。Docker 当前的[官方 Ubuntu 安装指南](https://docs.docker.com/engine/install/ubuntu/)已不列出 20.04，因此这里使用 Ubuntu 的 `docker.io` 软件包和 Docker 官方发布的 CLI 插件，不添加面向较新 Ubuntu 版本的 Docker APT 软件源。**已有 Docker Engine 时跳过安装 `docker.io` 的命令**，保留原有镜像、容器和数据卷。Rakazo 本地 Docker 电脑需要 Engine 26+；若软件源提供的版本较低，应先升级操作系统或另行取得受维护的兼容 Engine，再继续部署。

```bash
# 确认当前系统版本和架构。
. /etc/os-release && printf '%s %s\n' "$NAME" "$VERSION_ID"
uname -m
```

尚未安装 Docker Engine 时，运行：

```bash
# 使用 Ubuntu 软件包安装 Docker 及教程所需的基础工具。
sudo apt update
sudo apt install docker.io ca-certificates curl git openssl
```

已有 Engine 可跳过安装，继续运行：

```bash
# 启动 Docker，并确认版本至少为 26。
sudo systemctl start docker
docker --version

# 验证守护进程能运行容器；此命令会拉取一次性测试镜像。
sudo docker run --rm hello-world
```

若已有 Engine，直接从启动及版本检查开始。`docker.io` 是 Ubuntu 维护的 Docker 软件包；不要为了补装 Compose 而卸载现有 Engine。特别是在装有 NVIDIA 容器组件的设备上，`apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` 会将现有的 `docker.io`、`containerd` 和 `runc` 换成另一套软件包，不能当作“只安装插件”的命令。Ubuntu 20.04 的软件源可能不提供当前的 Compose / Buildx 插件包，因此使用 [Docker 官方 Compose 手动安装方式](https://docs.docker.com/compose/install/linux/)和官方发布文件安装到当前用户的 CLI 插件目录。以下示例固定 Compose `v5.6.0` 与 Buildx `v0.37.1`；手动安装不会随 APT 自动更新。

```bash
# 创建当前用户的 Docker CLI 插件目录。
mkdir -p "$HOME/.docker/cli-plugins"

# 根据 CPU 架构选择官方发布文件；Ubuntu arm64 的 uname 名称为 aarch64。
case "$(uname -m)" in
  aarch64) compose_arch=aarch64; buildx_arch=arm64 ;;
  x86_64) compose_arch=x86_64; buildx_arch=amd64 ;;
  *) echo "不支持的 CPU 架构" >&2; exit 1 ;;
esac

# 从 Docker Compose 官方仓库下载插件并赋予执行权限。
curl -fL "https://github.com/docker/compose/releases/download/v5.6.0/docker-compose-linux-${compose_arch}" \
  -o "$HOME/.docker/cli-plugins/docker-compose"
chmod +x "$HOME/.docker/cli-plugins/docker-compose"

# 从 Docker Buildx 官方仓库下载构建插件并赋予执行权限。
curl -fL "https://github.com/docker/buildx/releases/download/v0.37.1/buildx-v0.37.1.linux-${buildx_arch}" \
  -o "$HOME/.docker/cli-plugins/docker-buildx"
chmod +x "$HOME/.docker/cli-plugins/docker-buildx"

# 两个版本命令都应成功输出版本号。
docker compose version
docker buildx version
```

如果选择不加入 `docker` 组，需要让 root 用户的 Docker CLI 也能发现这两个插件：

```bash
# 把已下载的插件安装到 Docker 的系统级 CLI 插件目录。
sudo install -m 0755 -d /usr/local/lib/docker/cli-plugins
sudo install -m 0755 "$HOME/.docker/cli-plugins/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose
sudo install -m 0755 "$HOME/.docker/cli-plugins/docker-buildx" /usr/local/lib/docker/cli-plugins/docker-buildx

# 确认 sudo 运行的 Docker CLI 也能发现两个插件。
sudo docker compose version
sudo docker buildx version
```

若普通用户运行 `docker compose version` 正常，但 `sudo docker compose --env-file ...` 报 `unknown flag: --env-file`，说明 root 用户没有找到 Compose 插件；执行上面的系统级安装命令后，再用 `sudo docker compose version` 验证。

更新手动安装的插件时，到 [Compose](https://github.com/docker/compose/releases) 和 [Buildx](https://github.com/docker/buildx/releases) 官方发布页核对版本与对应架构的文件名，再替换插件文件。`docker-compose` 旧版独立命令不等同于 `docker compose` 插件。

如果下载时报 443 连接错误，先用当前用户执行 `curl -I https://github.com` 检查网络。通过代理联网的设备应让下载命令继承当前用户的代理配置；不要改用 `sudo curl`，因为 `sudo` 可能清除代理环境变量。本节的插件下载写入用户目录，不需要 `sudo`。Ubuntu 20.04 本流程也不需要下载 `https://download.docker.com/linux/ubuntu/gpg`。

### 当前用户是否需要加入 docker 组？

**可选。**在可信的个人设备上，如果希望以下部署命令无需逐条加 `sudo`，可将当前用户加入 `docker` 组。该组成员可以控制 Docker 守护进程，实际拥有宿主机的 root 级权限；这不是降低权限的做法。在共享主机上，或不希望登录会话中的所有进程都能访问 Docker 时，不要加入该组，改为在本教程的 `docker` 命令前使用 `sudo`。

```bash
# 创建 docker 组（若已存在则保持不变），并加入当前登录用户。
sudo groupadd --force docker
sudo usermod -aG docker "$USER"
```

**完全退出当前登录会话并重新登录**，然后运行：

```bash
# 确认当前登录用户已属于 docker 组。
id -nG

# 验证无需 sudo 即可访问 Docker。
docker info
```

重新登录前，`usermod` 不会改变当前终端的组身份；也可用 `newgrp docker` 临时开启一个已更新组身份的 shell。详见 [Docker 官方安装后设置说明](https://docs.docker.com/engine/install/linux-postinstall/)。

```bash
# 查看 Docker Engine 版本；本地 Docker 电脑需要 Engine 26+。
docker --version

# 确认 Compose 与 Buildx 插件可用；命令应输出版本号。
docker compose version
docker buildx version

# 确认 Docker 守护进程正在运行，且当前用户可以连接。
docker info

# 检查源码、镜像、数据卷可用的磁盘空间。
df -h .
```

在使用 systemd 的 Linux 上，如果 Docker 已安装但未运行，可启动服务：

```bash
# 启动 Docker 守护进程；需要管理员权限。
sudo systemctl start docker

# 再次确认连接正常。
docker info
```

若未加入 `docker` 组，下面的 Docker 命令需要以 `sudo docker ...` 执行，并按上面的步骤安装系统级插件。不要把 Docker 套接字暴露到公网。

## 2. 准备源码和配置

若尚未获取源码：

```bash
# 下载 Rakazo 源码。
git clone https://github.com/elie222/rakazo.git

# 进入仓库根目录；后续命令都在此目录执行。
cd rakazo
```

若已在仓库根目录，直接从这里继续：

```bash
# 首次部署才复制配置模板；已有 .env 时不要覆盖。
test -e .env || cp .env.example .env

# 仅允许当前用户读写包含密钥的配置文件。
chmod 600 .env
```

打开 `.env`，分别设置以下五个值。每个值都要单独生成，不能复用。`POSTGRES_PASSWORD` 使用十六进制，便于安全地拼入数据库 URL：

```bash
# 生成 POSTGRES_PASSWORD：16 字节随机值，输出为 32 位十六进制。
openssl rand -hex 16

# 分别执行四次，每次使用新的输出值填写一个密钥。
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
```

将结果分别填入 `POSTGRES_PASSWORD`、`BETTER_AUTH_SECRET`、`ENCRYPTION_KEY`、`SCREEN_PROXY_SECRET` 和 `SANDBOX_SUPERVISOR_TOKEN`。其中 `ENCRYPTION_KEY` 需要 64 位十六进制字符。`.env.example` 中的 `DATABASE_URL` 是供宿主机开发工具使用的示例地址；如果将来要使用宿主机数据库工具，再把其中的密码改成同一个 `POSTGRES_PASSWORD`。本教程的容器内部数据库连接由 Compose 根据 `POSTGRES_PASSWORD` 配置，不使用示例 `DATABASE_URL`。

保留模板中的本地地址和 `SANDBOX_PROVIDER=docker`。不要提交 `.env`，也不要把密钥粘贴到议题、拉取请求或日志中。可选的模型密钥可以留空，在首次登录后通过连接设置添加模型。

## 3. 从源码构建并启动

配置好 `.env` 且当前用户能够运行 Docker 后，可在仓库根目录使用一键脚本。首次 `start` 会构建缺少的源码镜像；之后的 `start` 复用已有镜像，启动服务并等待 API 和 Web 就绪。源码更新后使用 `rebuild` 重新构建。`stop` 停止服务和当前仓库的机器人电脑，保留数据库和机器人文件。

```bash
# 首次自动构建；日常启动复用镜像。
./scripts/local-ubuntu.sh start

# 源码或 Dockerfile 更新后，重新构建并启动。
./scripts/local-ubuntu.sh rebuild

# 查看所有 Compose 服务状态。
./scripts/local-ubuntu.sh status

# 停止服务，保留 PostgreSQL 数据卷和 data/ 中的机器人文件。
./scripts/local-ubuntu.sh stop
```

脚本不会自动使用 `sudo` 或启动 Docker 守护进程。若 `docker info` 无法连接，请先按第 1 节启动 Docker，并确认当前登录会话已有 Docker 权限。`rebuild` 和首次构建时继承宿主机代理变量；启动容器时清除宿主机的 HTTP(S) 代理变量，避免回环代理地址在容器内失效。日常 `start` 不检查源码是否变化，需要更新应用时请运行 `rebuild`。

也可以逐条运行下面的 Compose 命令：

```bash
# 检查 Compose 配置能否解析；缺少必填值时会立即报错。
docker compose --env-file .env -f infra/compose/docker-compose.yml config --quiet

# 从当前源码构建镜像并在后台启动完整服务。
docker compose --env-file .env -f infra/compose/docker-compose.yml up -d --build

# 查看各服务状态；computer 和 data-init 是一次性任务，完成后退出是正常的。
docker compose --env-file .env -f infra/compose/docker-compose.yml ps -a

# 检查 API 存活状态；预期返回 {"ok":true}。
curl --fail --silent --show-error http://127.0.0.1:3100/health
```

如果宿主机终端的 `HTTP_PROXY` / `HTTPS_PROXY` 指向 `127.0.0.1` 或 `localhost`，Compose 会把它们传入 API 和 Worker；容器中的回环地址指向容器自身，无法连接宿主机代理。需要代理下载依赖时，先在原终端执行 `docker compose --env-file .env -f infra/compose/docker-compose.yml build`；构建完成后，用以下命令启动，避免把宿主机回环代理传入运行中的服务：

```bash
# 仅对本次 Compose 启动清除宿主机代理变量，使用已构建镜像。
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  docker compose --env-file .env -f infra/compose/docker-compose.yml up -d --no-build
```

如果运行中的机器人需要通过代理访问外网，应改用容器能够连接的代理地址，不能使用宿主机的 `127.0.0.1`。

浏览器打开 [http://127.0.0.1:5173](http://127.0.0.1:5173)，创建首个账户，然后连接模型并创建机器人。API 的 `3100` 端口和 Web 的 `5173` 端口仅绑定本机回环地址；PostgreSQL 不映射到宿主机端口。

### 通过 FRP 访问 5173

若 FRP 在宿主机上将外部域名或 IP 转发到 `127.0.0.1:5173`，需要在 `.env` 中设置浏览器实际访问的来源。已有 `.env` 若没有 `RAKAZO_HOST`，请新增这一行；缺省时 Compose 使用 `localhost`。以下示例假设外部 HTTPS 已在代理端终止；使用非标准端口时，也要写入三个 URL。`RAKAZO_HOST` 只填域名或 IP，不含协议或端口。

```dotenv
RAKAZO_HOST=rakazo.example.com
BETTER_AUTH_URL=https://rakazo.example.com
WEB_ORIGIN=https://rakazo.example.com
API_URL=https://rakazo.example.com
```

保存 `.env` 后重新创建 API、Worker 和 Web 容器，使运行时配置生效；仅修改配置不需要重建镜像：

```bash
# 检查配置，然后重建使用这些环境变量的容器；不触碰数据库容器和数据卷。
docker compose --env-file .env -f infra/compose/docker-compose.yml config --quiet
docker compose --env-file .env -f infra/compose/docker-compose.yml \
  up -d --no-build --no-deps --force-recreate api worker web
```

外部地址的协议、主机名和端口必须与浏览器地址一致。若仍显示 `invalid origin`，检查浏览器开发者工具中失败请求的 `Origin` 是否与 `WEB_ORIGIN` 完全一致。若首页直接提示 `Blocked request. This host ... is not allowed`，检查 `RAKAZO_HOST`。不要通过放开全部来源或伪造 `Origin` 请求头来绕过校验。FRP 客户端若运行在另一个容器内，其 `127.0.0.1` 指向该容器，需改用它能访问到的 Web 服务地址。

如果启动失败，可查看服务状态及相关日志：

```bash
# 查看所有服务状态。
docker compose --env-file .env -f infra/compose/docker-compose.yml ps -a

# 查看 API、Worker、Web 和本地电脑监督进程的最近日志。
docker compose --env-file .env -f infra/compose/docker-compose.yml logs --tail=100 api worker web supervisor
```

首次构建可能耗时较长。构建中出现内存不足时，先关闭其他高内存程序，再重试；多次失败则需要增加物理内存或在资源更多的设备上构建。若基础镜像或依赖无法下载，先检查网络；镜像和代理配置可参考[受限网络指南](./self-host-restricted-network.md)。

## 4. 停止、重启与更新

```bash
# 停止并移除服务容器；保留 PostgreSQL 数据卷和本地 data 目录。
docker compose --env-file .env -f infra/compose/docker-compose.yml down

# 使用现有源码和配置重新启动服务。
docker compose --env-file .env -f infra/compose/docker-compose.yml up -d
```

更新源码前，先备份数据库和 `data/`，参见[备份说明](./self-host.md#backup)。确认工作区没有待保留的本地改动后，可按以下顺序更新：

```bash
# 快进到远端版本；不会自动创建合并提交。
git pull --ff-only

# 从更新后的源码重新构建并重建服务；API 启动时会执行数据库迁移。
docker compose --env-file .env -f infra/compose/docker-compose.yml up -d --build

# 检查服务状态和 API。
docker compose --env-file .env -f infra/compose/docker-compose.yml ps -a
curl --fail --silent --show-error http://127.0.0.1:3100/health
```

不要使用 `docker compose down -v` 作为日常停止命令：`-v` 会删除 PostgreSQL 数据卷。已有数据卷首次初始化时的数据库用户名和密码会一直保留；修改 `.env` 不会自动修改已有数据库用户。密钥用途和恢复注意事项见[自托管密钥清单](./self-host-secrets.md)。

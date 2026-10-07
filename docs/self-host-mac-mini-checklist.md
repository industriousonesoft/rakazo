# Mac mini M4：Rakazo 源码部署清单

这份清单适用于 32 GB 内存的 Apple M4 Mac mini。第一轮只部署 Rakazo，不下载或运行本地模型。Rakazo 的 API、Worker 和 Web 直接运行在 macOS；Colima 承载 PostgreSQL 和机器人的 Docker 电脑。首次部署仅监听 `127.0.0.1`。模型连接可在服务验收后，通过 **Settings → Models** 单独配置。

`.env`、数据库、日志和本机服务配置不要加入 Git。保留现有数据库卷与密钥；不要执行 `docker compose down -v`。另见[自托管密钥说明](./self-host-secrets.md)和[源码部署指南](./self-host.md#local-source-checkout)。

## 第一阶段：检查环境

- [x] 确认是 Apple Silicon Mac、内存和磁盘空间足够；确认 Node.js 24、pnpm 9、Docker CLI、Compose、Buildx 和 Colima 已安装。
- [x] 检查 Git 工作区与 `.env` 状态；`.env` 受 Git 忽略，且部署前不存在。保留已有文档改动。
- [x] 检查 `3100`、`5173`、`5433`、`7091` 端口；没有其他监听进程。

```bash
node --version
corepack pnpm --version
docker compose version
docker buildx version
colima version
git status --short
git check-ignore .env
lsof -nP -iTCP:3100 -iTCP:5173 -iTCP:5433 -iTCP:7091 -sTCP:LISTEN
```

## 第二阶段：准备 Docker 与配置

- [x] 使用 Docker 运行时启动 Colima，初始分配 4 核 CPU、4 GiB 内存和 100 GiB 虚拟磁盘。这里的内存是虚拟机额度，不是 PostgreSQL 的固定消耗；多个机器人电脑同时运行或出现内存不足时，再评估增至 6–8 GiB。确认 Docker context 指向 Colima，且 `docker info` 成功。
- [x] 仅在 `.env` 不存在时复制 `.env.example`。为 `POSTGRES_PASSWORD`、`BETTER_AUTH_SECRET`、`ENCRYPTION_KEY`、`SCREEN_PROXY_SECRET` 和 `SANDBOX_SUPERVISOR_TOKEN` 分别生成随机值；数据库密码也写入 `DATABASE_URL`。不要显示或提交密钥。
- [x] 保持 `API_HOST`、`BETTER_AUTH_URL`、`WEB_ORIGIN` 为本机回环地址。设置 `SANDBOX_PROVIDER=docker`、`SANDBOX_CONTROL_VIA_LOOPBACK=true`，并把 Colima Docker socket URL 写入 `DOCKER_HOST`。本阶段无需模型密钥。
- [x] 使用本机端口覆盖文件启动 PostgreSQL，等待健康检查完成。默认仅在 `127.0.0.1:5433` 发布端口。

```bash
colima start --runtime docker --vm-type vz --cpu 4 --memory 4 --disk 100
docker context use colima
docker info
docker context inspect colima --format '{{.Endpoints.docker.Host}}'
docker compose --env-file .env \
  -f infra/compose/docker-compose.yml \
  -f infra/compose/docker-compose.postgres-host.yml \
  up postgres -d --wait
```

已有 Colima 配置时先检查，再调整 CPU 和内存。数据库卷已存在时，`.env` 必须沿用原有数据库凭据；不要通过删除卷来解决登录失败。

## 第三阶段：安装、构建并启动源码服务

- [x] 安装依赖、生成 Prisma 客户端、执行数据库迁移并构建 Web。
- [x] 用 Buildx 构建 ARM64 机器人电脑镜像，并以无网络容器执行最小命令确认镜像可运行。旧版 Docker 构建器不会提供镜像构建所需的 `TARGETARCH` 参数。
- [x] 分别启动 Supervisor、API、Worker 和 Web，确认四项都能从当前仓库运行。手动运行时使用 `scripts/local-mac.sh` 管理整套服务。

```bash
corepack pnpm install --frozen-lockfile
corepack pnpm db:generate
corepack pnpm db:migrate
corepack pnpm --filter @rakazo/web build
corepack pnpm sandbox:build
```

| 服务 | 从仓库根目录运行的命令 |
| --- | --- |
| Supervisor | `corepack pnpm --filter @rakazo/sandbox-supervisor start` |
| API | `corepack pnpm --filter @rakazo/api start` |
| Worker | `corepack pnpm --filter @rakazo/worker start` |
| Web | `corepack pnpm --filter @rakazo/web preview --host 127.0.0.1 --port 5173 --strictPort` |

## 第四阶段：验收与手动运行

- [x] `curl -fsS http://127.0.0.1:3100/internal/health` 返回 `ok: true` 和 `sandbox: "docker"`；Web 页面可通过 `http://127.0.0.1:5173` 打开。
- [ ] 创建第一个本机账户，确认 API、Worker、Supervisor 和 Web 持续运行。未连接模型前，对话推理不可验收；这不影响服务部署验收。
- [ ] 验证 Docker 电脑可创建、读取文件并执行无害命令；不依赖本地模型时，可在连接任一可用模型后完成此项。
- [x] 取消登录自启动。使用 `scripts/local-mac.sh start`、`stop`、`status` 手动管理 Colima、PostgreSQL 和四个服务；关闭时保留数据库卷与机器人文件。
- [x] 检查停止后端口不再监听、登录启动项不再存在；再次手动启动并复查健康接口、Web 和监听地址。
- [ ] 检查 `git status --short` 与 diff，确认没有密钥、日志或模型缓存进入 Git。

日常从仓库根目录运行：

```bash
./scripts/local-mac.sh start
./scripts/local-mac.sh status
./scripts/local-mac.sh stop
```

脚本仅为当前登录会话加载服务，不在下次登录时自动启动。停止时只停止当前仓库的机器人电脑容器；若 Colima 原本已在运行或有其他容器仍在运行，脚本会保留 Colima。服务日志写入 `~/.local/state/rakazo/logs`。

升级时先手动停止，再在当前仓库安装依赖、运行迁移和构建。完成后手动启动：

```bash
./scripts/local-mac.sh stop
pnpm install --frozen-lockfile
pnpm db:generate
pnpm db:migrate
pnpm --filter @rakazo/web build
pnpm sandbox:build
./scripts/local-mac.sh start
```

需要本地模型时，再单独评估模型、推理服务和内存预算；它不是本清单的部署前提。

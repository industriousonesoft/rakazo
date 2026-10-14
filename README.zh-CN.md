# Rakazo

[English](./README.md) | [简体中文](./README.zh-CN.md)

[![GitHub stars](https://img.shields.io/github/stars/elie222/rakazo?labelColor=black&style=for-the-badge&color=2563EB)](https://github.com/elie222/rakazo/stargazers)
[![Discord](https://img.shields.io/badge/Discord-加入社区-5865F2?labelColor=black&style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/RWwKa2Sn7h)

![Rakazo——由你掌控的 AI 队友](./docs/readme-hero.png)

Rakazo 是开源 AI 智能体产品，让你拥有能长期协作的 AI 队友，也是一款可在自己的设备上运行的自托管 AI 助手。它提供 Web、Electron 桌面和 Expo 移动端。你可以自行选择模型和电脑运行环境，也可以在本地运行完整服务。

Rakazo 是 Grok Bot、Meta Muse、OpenAI Dots、Instinct、OpenClaw、Hermes Agent 和 Hark Pro 的开源自托管替代方案。

Rakazo 目前处于测试阶段。更多信息见 [rakazo.com](https://rakazo.com)。

## Rakazo 与其他产品的比较

Rakazo 启动后，使用方式就像 Grok Bot 一样，以聊天为中心：你在对话中创建和管理机器人。Muse、Dots、Instinct 和 Hark Pro 是托管式助手。OpenClaw 和 Hermes Agent 也是可自行运行的开源智能体；它们的文档介绍了安装器、配置文件和网关。Hermes Desktop 无需命令行即可开始首次聊天；消息网关则是一个独立进程。

- [Grok Bot](https://rakazo.com/grok-bot-alternative/)
- [Muse](https://rakazo.com/muse-alternative/)
- [Dots](https://rakazo.com/dots-alternative/)
- [Instinct](https://rakazo.com/instinct-alternative/)：可通过消息或电话联系的个人助手
- [OpenClaw](https://rakazo.com/openclaw-alternative/)
- [Hermes Agent](https://rakazo.com/hermes-alternative/)：Nous Research 的开源智能体
- [Hark Pro](https://rakazo.com/hark-alternative/)：hark.com 的个人智能体
- [全部对比文章](https://rakazo.com/alternatives/)
- [自托管指南](https://rakazo.com/self-hosted-ai-agent/)

## 功能

- 持久化机器人，各自拥有对话、记忆、定期任务和历史记录
- 语音模式：朗读回复、语音输入，以及与机器人通话；可使用自己的 ElevenLabs、OpenAI、Cartesia 或 Fish Audio 密钥
- 共享的团队电脑和相互隔离的私人电脑
- 浏览器、终端、文件和图形桌面操作
- 机器人可将任务委派给其他机器人或临时子智能体
- 通过 Pi 接入自己的模型凭据
- 通过 Composio 或 Pipedream Connect 连接应用，也可由用户安装 Treg、远程 MCP 和 OpenAPI 工具源
- 支持 Docker、E2B、Daytona、CreateOS、Box，以及可信的本机电脑

## 演示

https://github.com/user-attachments/assets/dccdeddb-2134-4a56-8eed-b2e591736b1c

## 技术栈

- TypeScript
- React 19、Vite 和 Tailwind CSS
- Electron 和 Expo
- Hono 和 oRPC
- PostgreSQL 和 Prisma
- Better Auth
- Graphile Worker
- Pi
- Docker、E2B、Daytona、CreateOS 和 Box
- Composio、Pipedream Connect、MCP 和 OpenAPI 集成

## 快速开始（已发布镜像）

需要 Docker Engine、Docker Compose 插件、curl 和 OpenSSL；无需克隆仓库或安装 Node.js。

```bash
mkdir -p rakazo && cd rakazo &&
curl -fsSLO https://raw.githubusercontent.com/elie222/rakazo/main/infra/compose/install-images.sh &&
bash install-images.sh
```

安装器会下载 Compose 文件，生成包含随机密钥的 `.env`，并启动 Rakazo。再次运行时会保留已有的 `.env`。

打开 [http://127.0.0.1:5173](http://127.0.0.1:5173)，创建账户并连接模型。默认启用本地 Docker 电脑。也可以配置 `e2b`、`daytona`、`createos` 或 `box` 作为远程电脑运行环境，并提供相应的 API 密钥。

默认镜像标签为 `edge`（main 分支构建，支持 `linux/amd64` 和 `linux/arm64`）。标签详情见[自托管文档](./docs/self-host.md#published-images-no-checkout)。

如果网络受限，可通过 `RAKAZO_DOWNLOAD_BASE` 更换安装器的下载地址，通过 `--local` / `RAKAZO_DOWNLOAD_SKIP_EXISTING` 跳过已有的 Compose 文件，或从镜像地址获取引导脚本。详见[受限网络与镜像下载](./docs/self-host.md#restricted-networks--mirror-downloads)。

如需让智能体协助安装，可使用 [SETUP_PROMPT.md](./SETUP_PROMPT.md)。

## 在服务器上运行

后端运行在服务器上时，机器人可以持续工作。可在 VPS 上使用同一安装器，再通过桌面应用、移动应用或浏览器连接。

```bash
bash install-images.sh --prepare-only
# 编辑 .env：设置 SANDBOX_PROVIDER=box（或 e2b / daytona / createos）及相应 API 密钥，并设置 RAKAZO_HOST=your.domain
bash install-images.sh
```

在 5173 端口前配置 HTTPS；[docs/self-host.md](./docs/self-host.md#public-single-vm-deployment) 介绍了 Caddy 配置和主机加固。在桌面应用中选择 **Existing instance（现有实例）**，输入 `https://` 地址。

## 本地开发（源码检出）

需要 Node.js 22.22.2 或更新的 22.x 版本、Node.js 24.x 或 Node.js 26+，以及 pnpm 9 和 Docker。不支持 Node.js 23.x 和 25.x。

```bash
git clone https://github.com/elie222/rakazo.git
cd rakazo
cp .env.example .env
```

设置 `POSTGRES_PASSWORD`（例如使用 `openssl rand -hex 16` 生成），并将同一值写入 `DATABASE_URL`。分别为 `BETTER_AUTH_SECRET`、`ENCRYPTION_KEY` 和 `SCREEN_PROXY_SECRET` 设置独立、足够长的随机值。Docker 沙箱还需要专用的 `SANDBOX_SUPERVISOR_TOKEN`。你也可以设置 `OPENROUTER_API_KEY`，或在首次使用时连接受支持的模型服务商。

在使用 Docker Desktop 的宿主机开发时，在 `.env` 中设置 `SANDBOX_CONTROL_VIA_LOOPBACK=true`。监督进程会自动发现 Docker Desktop 的用户套接字；使用其他 Docker 运行环境时，可通过 `DOCKER_HOST` 或 `DOCKER_SOCKET` 覆盖。

托管应用目录是可选的。使用 Composio 时设置 `COMPOSIO_API_KEY`；使用 Pipedream Connect 时设置 `PIPEDREAM_CLIENT_ID`、`PIPEDREAM_CLIENT_SECRET` 和 `PIPEDREAM_PROJECT_ID`。不启用这两种托管目录，用户仍可在 **Integrations（集成）** 中添加 HTTPS MCP 服务器、Treg 端点或 OpenAPI JSON 文档。连接器凭据在服务端加密，API 不会返回这些凭据。

Treg 按用量计费。自托管者需要提供自己的 Treg 令牌；在托管产品中集成 Treg 的运营方应查看 [Treg 集成条款](https://treg.to/integrate.md)，其中要求托管转售事先取得书面协议。

```bash
docker compose --env-file .env \
  -f infra/compose/docker-compose.yml \
  -f infra/compose/docker-compose.postgres-host.yml \
  up postgres -d
pnpm install
pnpm db:generate
pnpm db:migrate
pnpm sandbox:build
pnpm dev
```

默认 Compose 文件将 Postgres 留在内部网络中，与已发布镜像的部署方式一致。`postgres-host` 叠加文件将数据库映射到本机回环地址 `127.0.0.1:5433`，供宿主机上的 `pnpm` 和数据库工具使用。如果该端口已被占用，请同时修改 `.env` 中的 `POSTGRES_HOST_PORT` 和 `DATABASE_URL` 端口。

不使用叠加文件时，可运行 `docker compose --env-file .env -f infra/compose/docker-compose.yml exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` 进入数据库。`POSTGRES_PASSWORD` 应使用适合 URI 的字符（例如 `openssl rand -hex 16` 的输出）。已有的 `pgdata` 数据卷会保留首次初始化时的用户名、密码和数据库名，因此应保留 `.env` 中的对应值，或通过 `ALTER ROLE` / 重命名就地修改。只有备份后（或数据可以丢弃时）才重建数据卷；`docker compose down -v` 会删除全部 Postgres 数据。

打开 [http://127.0.0.1:5173](http://127.0.0.1:5173)，创建账户、连接模型并创建第一个机器人。

关于部署、运行环境选择、备份和升级，参见[自托管指南](./docs/self-host.md)。另有一份附中文命令注释的[本机源码部署教程](./docs/source-deploy.zh-CN.md)。

使用 CreateOS 时，设置 `SANDBOX_PROVIDER=createos` 和 `CREATEOS_SANDBOX_API_KEY`。可选的 `CREATEOS_SANDBOX_BASE_URL`、`CREATEOS_SANDBOX_SHAPE` 和 `CREATEOS_SANDBOX_ROOTFS` 默认分别为 `https://api.sb.createos.sh`、`s-2vcpu-2gb` 和 `desktop:1`。

## 桌面端和移动端

Electron 和 Expo 应用都是 Rakazo API 的客户端，Web 应用也使用同一个 API。

开发环境运行后，可用以下命令启动 Electron：

```bash
pnpm --filter @rakazo/desktop dev
```

首次启动时，桌面应用会询问是在这台电脑上运行 Rakazo，还是连接现有服务器。选择 **This computer（这台电脑）** 时，应用会在其数据目录下通过 Docker Compose 安装并启动已发布镜像（与 `infra/compose/install-images.sh` 使用相同文件），因此需要安装 Docker Desktop、OrbStack 或 Docker Engine；如果未安装，应用会提供相关链接。已安装的应用会将镜像标签固定为自身版本；未打包的构建会拉取 `edge`。运行 `pnpm dev` 的开发者应选择 **Existing instance（现有实例）**，地址为 `http://127.0.0.1:5173`。公网服务器必须使用 HTTPS；HTTP 仅允许回环地址和私有局域网地址（不包括链路本地地址）。应用会先检查 Rakazo 健康端点，确认可用后再保存地址；以后启动时会直接连接该实例。退出桌面应用后，服务仍会运行；应用菜单中的 **Stop Local Stack（停止本地服务）** 可将其关闭。

使用应用菜单中的 **Change Rakazo Server…（更换 Rakazo 服务器）** 可重新连接。关闭该窗口而不保存，会返回之前的实例。开发自动化可设置 `RAKAZO_WEB_URL` 临时指向其他地址，而不修改保存的实例；设置 `RAKAZO_FORCE_SETUP=1` 可重新运行设置向导。

移动端的构建与发布说明见 [docs/mobile-release.md](./docs/mobile-release.md)。

## 界面语言

Web（以及承载 Web 界面的 Electron）在 **Settings → Language** 中支持 English、Deutsch、한국어、Türkçe、हिन्दी、Português (Brasil)、简体中文、Español 和 Русский。Expo 应用包含 English、简体中文、Русский 和 Deutsch 语言目录；**Account → Language** 提供 English 和简体中文，其他语言目录依据设备语言或 `EXPO_PUBLIC_DEFAULT_UI_LOCALE` 选择。营销首页（`apps/www`）可通过页脚语言链接访问 en/de/ko/zh 版本（`/`、`/de/`、`/ko/`、`/zh/`）；其他营销页面仍为英文。俄语营销首页以及 Electron 原生设置界面和菜单的本地化仍待后续完成。

## 开发

```text
apps/       Web、API、Worker、桌面端、移动端和公开网站
packages/   领域逻辑、契约、持久化、适配器、UI 和测试工具
infra/      本地服务和电脑镜像
docs/       架构、运维和发布指南
```

常用检查命令：

```bash
pnpm lint
pnpm check
pnpm test
pnpm test:integration
pnpm test:e2e
```

开发流程和测试矩阵见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 文档

- [本机源码部署（中文）](./docs/source-deploy.zh-CN.md)
- [自托管](./docs/self-host.md)
- [自托管密钥](./docs/self-host-secrets.md)
- [电脑运行环境与隔离](./docs/computer-runtime.md)
- [桌面端发布](./docs/desktop-release.md)
- [移动端发布](./docs/mobile-release.md)
- [性能测试](./docs/performance.md)

## 参与贡献

欢迎贡献！提交拉取请求前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。如需报告安全漏洞，请遵循 [SECURITY.md](./SECURITY.md)，不要提交公开议题。

Rakazo 使用 [Apache License 2.0](./LICENSE) 授权。

欢迎在 [Rakazo Discord 社区](https://discord.gg/RWwKa2Sn7h)交流问题和想法。

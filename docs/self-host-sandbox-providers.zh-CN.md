# 自托管沙箱 / Computer 提供方

`SANDBOX_PROVIDER` 用于选择 bot 的 Computer 在哪里运行。默认情况下，工作空间中的 bot 共享一台 Team Computer，也可以选择使用 Private Computer。共享与持久化契约见 [Computer 运行环境与隔离](./computer-runtime.zh-CN.md)。

## 快速选择

| 目标 | 配置 | 其他要求 |
| --- | --- | --- |
| 本地 Docker Computer | `SANDBOX_PROVIDER=docker` | `SANDBOX_SUPERVISOR_TOKEN`、Computer 镜像，以及供 supervisor 使用的 Docker 套接字 |
| 仅运行界面，不提供 Computer | `SANDBOX_PROVIDER=none` | 无需提供方凭据；使用已发布镜像的 Compose 部署仍需要 `SANDBOX_SUPERVISOR_TOKEN` |
| 托管远程桌面 | `e2b` / `daytona` / `box` | `SANDBOX_SUPERVISOR_TOKEN`（使用已发布镜像的 Compose 部署）、对应的 API Key，以及 Daytona/Box 可选的 URL 配置 |

使用已发布镜像的 [Compose 配置](../infra/compose/docker-compose.images.yml)默认选择 **`docker`**。
它始终启动 supervisor，并要求设置 `SANDBOX_SUPERVISOR_TOKEN`，即使选择 `none` 或远程提供方也是如此。这个部署栈凭据不能替代远程提供方的 API Key。

## `docker`（部署栈内的 supervisor）

Compose 会在内部网络中启动一个**沙箱监管服务（sandbox supervisor）**，使用应用镜像运行；在已发布镜像的部署中，其端口为 `7091`。它根据 `RAKAZO_COMPUTER_IMAGE` 和 `RAKAZO_COMPUTER_IMAGE_TAG` 创建与自身并列的 **Computer 容器**。

要求：

- 非空的 `SANDBOX_SUPERVISOR_TOKEN`，且应与身份验证、屏幕和加密密钥分别设置。
- 可获取的 Computer 镜像，默认来自 GHCR，也可以使用自己的镜像源；在 arm64 上，应为应用和 Computer 都指定支持多架构的镜像标签。
- supervisor 能访问 Docker Engine；Compose 部署通过挂载套接字实现。

验证：

```bash
curl -fsS http://127.0.0.1:3100/internal/health
# 预期返回 sandbox: docker
```

缺少 supervisor 令牌属于**配置失败**：在此部署方式下，不要将 `sandbox: "none"` 视为成功。

注册和本地 Docker Computer **无需** E2B 或其他远程服务账号即可使用。

## `none`

运行 API 和 Web，但不为 bot 创建 Computer。

## 远程提供方

将 `SANDBOX_PROVIDER` 设置为以下某一个值：

| 值 | 凭据 | 说明 |
| --- | --- | --- |
| `e2b` | `E2B_API_KEY` | 托管沙箱 |
| `daytona` | `DAYTONA_API_KEY` | 可选配置：`DAYTONA_API_URL`、`DAYTONA_TARGET`、`DAYTONA_SNAPSHOT` |
| `box` | `BOX_API_KEY` | 可选配置：`BOX_API_URL`（见 `.env.example`） |

使用远程提供方仍需要正常运行的 API 和 worker；它们不能替代 Postgres 或 Web 界面，并且需要能够向提供方发起出站连接。对于隔离网络中的主机，优先使用预先加载镜像的 `docker`，或选择 `none`。

## 验证提供方变更

修改提供方或密钥后，在存放 `docker-compose.images.yml` 和 `.env` 的已发布镜像部署目录中运行：

```bash
docker compose --env-file .env -f docker-compose.images.yml up -d
curl -fsS http://127.0.0.1:3100/internal/health
```

确认 `sandbox` 等于预期的提供方（`e2b`、`daytona` 或 `box`）。
仅返回 HTTP 200 并不能验证远程提供方是否可用：缺少 API Key 时会回退到 `sandbox: "none"`。
如果 API Key 已设置但无效，仍会报告所选的提供方。打开一个 bot 的 Computer，验证机器创建和桌面访问是否正常。

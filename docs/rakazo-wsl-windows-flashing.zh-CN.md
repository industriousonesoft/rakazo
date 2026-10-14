# Windows + WSL 源码部署 Rakazo 与固定工位烧录

本教程适用于一台 Windows 电脑：在 WSL 2 的 Ubuntu 中保存 Rakazo 源码，选择 Docker Desktop 或直接安装在 Ubuntu 中的 Docker Engine，从源码构建并运行完整 Compose 服务；Windows 上运行从源码构建的 Electron 客户端。烧录试点先由 Rakazo 整理待执行烧录单，工程师在固定工位手动执行。文末说明后续如何接入受控烧录工具；该工具目前尚未实现。

## 1. 先确认运行边界

```text
Windows：Electron 客户端、USB 外设
  └─ WSL Ubuntu：Rakazo 源码、配置、数据目录、可选的工位烧录脚本
       ├─ 路径 A：连接 Docker Desktop 的 Engine（Engine 位于其专用 WSL 发行版）
       └─ 路径 B：在 Ubuntu 内运行 Docker Engine
            ↓ 二选一，运行相同的 Compose 服务
          PostgreSQL、API、Worker、Web、Supervisor
            └─ Rakazo 电脑容器：Bot 的 Shell、Chromium 和图形桌面
```

WSL 2 是运行 Linux 内核的受管理环境。路径 A 中，Docker Desktop 在自己的 `docker-desktop` WSL 发行版运行 Engine，Ubuntu 通过集成向它发命令；路径 B 中，Engine 直接运行在 Ubuntu。两条路径的 Bot 电脑仍是独立 Docker 容器。Windows 或 WSL 能看到 USB，不表示 Bot 容器也能看到它。[Docker Desktop 的 WSL 2 架构](https://docs.docker.com/desktop/features/wsl/)和 [Rakazo 的电脑运行机制](./computer-runtime.md)分别说明了相关边界。

本教程保持 `SANDBOX_PROVIDER=docker`。Bot 可以操作电脑容器内的 Shell 与 Chromium；不能直接把其 `shell` 当作 WSL Ubuntu 的终端，也不能直接操作 Windows 中已经打开的 Chrome。Rakazo 的宿主机电脑提供方能在 API/Worker 所在环境执行命令，但没有真实的宿主机浏览器图形控制；全 Compose 部署中的 API/Worker 本身也在容器内。见[电脑提供方说明](./self-host.md#choosing-a-computer-provider)。

## 2. 安装 WSL 2，并选择 Docker Engine 的运行位置

建议使用 **Ubuntu 24.04 LTS** 制作新的 WSL 环境和第 8 节的预制镜像。在管理员 PowerShell 中先检查可用发行版与 WSL 版本，再明确安装 `Ubuntu-24.04`，按提示重启、创建 Linux 用户：

```powershell
wsl --list --online
wsl --version
wsl --install -d Ubuntu-24.04
wsl --list --verbose
```

确认 `Ubuntu-24.04` 的 WSL 版本为 `2`，并在发行版中用 `cat /etc/os-release` 核对系统版本。Canonical 的 [Ubuntu 24.04 WSL 安装说明](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/)指出：当前 24.04 的新版 tar 格式要求 WSL 2.4.10 或更新版本；若 `wsl --version` 不可用或版本过旧，先在 Windows PowerShell 运行 `wsl --update`，重启后再安装。WSL 的通用安装步骤见[微软文档](https://learn.microsoft.com/en-us/windows/wsl/install)。以下路径二选一；Docker Desktop 不兼容当前 Windows 版本、但 WSL 2 已能正常运行时，可选路径 B。路径 B 不能绕过 WSL 2 本身的系统要求。

### 路径 A：Docker Desktop 提供 Engine

安装并启动 [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)，选择 WSL 2 后端和 Linux containers，然后在 **Settings → Resources → WSL Integration** 中启用 Ubuntu。不要在启用 Docker Desktop 集成的 Ubuntu 中另装 Docker Engine；[Docker 官方说明](https://docs.docker.com/desktop/features/wsl/)提示两套安装可能冲突。

### 路径 B：在 WSL Ubuntu 内安装 Docker Engine

此路径不安装 Docker Desktop，也不启用它的 Ubuntu 集成。在 Ubuntu 终端先检查 systemd：

```bash
ps -p 1 -o comm=
```

若输出不是 `systemd`，先在 **Windows PowerShell** 确认 `wsl --version` 可用且 WSL 版本至少为 0.67.6；在 Ubuntu 中用 `sudo nano /etc/wsl.conf` 按[微软的 systemd 指南](https://learn.microsoft.com/en-us/windows/wsl/systemd/)加入以下内容，然后在 Windows PowerShell 运行 `wsl --shutdown`，重新打开 Ubuntu。该命令会关闭当前所有 WSL 发行版，执行前保存其中的工作。

```ini
[boot]
systemd=true
```

在 Ubuntu 中按 [Docker 官方 Ubuntu 安装指南](https://docs.docker.com/engine/install/ubuntu/)配置 apt 仓库，再安装 Engine、Compose 和 Buildx：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

若曾在 Ubuntu 中安装 `docker.io`、旧版 Compose、`containerd` 或 `runc`，先按官方指南卸载冲突包；不要删除已有的 `/var/lib/docker` 数据。为使用下文不带 `sudo` 的 Compose 命令，可将当前 Ubuntu 用户加入 `docker` 组，随后退出并重新登录 Ubuntu：

```bash
sudo usermod -aG docker "$USER"
```

`docker` 组成员可以控制 Docker 守护进程，权限等同于宿主机 root；只对可信用户授权。[Docker 安装后步骤](https://docs.docker.com/engine/install/linux-postinstall/)解释了这一权限边界。WSL 的 systemd 服务本身不会让发行版一直保持运行；Windows 重启或 WSL 关闭后，先启动 Ubuntu，再检查 `docker info` 和 Rakazo 服务。[WSL systemd 说明](https://learn.microsoft.com/en-us/windows/wsl/systemd/)

### 两条路径共用的检查

在 Ubuntu 终端检查 Docker CLI、Compose、Buildx 与 Engine：

```bash
docker version
docker compose version
docker buildx version
docker info
```

Rakazo 的本地 Docker 电脑需要 Docker Engine 26 或更新版本。若 Ubuntu 中无法运行 `docker info`，路径 A 检查 Docker Desktop 是否已启动、处于 Linux containers 模式并启用了 Ubuntu 集成；路径 B 检查 `systemctl status docker`、当前用户是否已重新登录并取得 `docker` 组权限。两条路径都不要求在 Ubuntu 中安装 Node.js 或 pnpm。

## 3. 在 WSL 中准备源码与 `.env`

在 Ubuntu 的 Linux 文件系统中检出源码，例如 `~/rakazo`；不要将源码和 `data/` 放在 `/mnt/c`。这也符合[项目的 WSL 源码开发说明](./self-host.md#local-source-checkout)。

```bash
sudo apt update
sudo apt install -y git curl openssl
cd ~
git clone https://github.com/elie222/rakazo.git
cd rakazo
test -e .env || cp .env.example .env
chmod 600 .env
```

编辑 `.env`，分别生成并填写以下五个值，不复用密钥：

```bash
openssl rand -hex 16  # POSTGRES_PASSWORD
openssl rand -hex 32  # BETTER_AUTH_SECRET
openssl rand -hex 32  # ENCRYPTION_KEY
openssl rand -hex 32  # SCREEN_PROXY_SECRET
openssl rand -hex 32  # SANDBOX_SUPERVISOR_TOKEN
```

将 `DATABASE_URL` 示例中的密码改成同一个 `POSTGRES_PASSWORD`，以备以后使用宿主机开发工具；本教程中的 Compose 服务使用由 `POSTGRES_PASSWORD` 生成的容器内数据库连接。保留模板中的本机 URL、`SANDBOX_PROVIDER=docker` 和 `SANDBOX_COMPUTER_EGRESS=open`。后一个值是现有默认配置；若需要限制 Bot 电脑出站访问，参见[受限出站说明](./self-host.md#restricted-computer-egress)，不要直接套用宿主机网络规则。`SANDBOX_CONTROL_VIA_LOOPBACK` 只用于宿主机运行的 Supervisor，此处保持未设置。

`.env` 含有密钥，不要加入 Git。模型连接可以在首次登录后配置。若已有 Rakazo 数据库卷，不要仅改 `.env` 中的数据库密码：PostgreSQL 卷保留首次初始化的用户和密码。参见[现有源码部署指南](./source-deploy.zh-CN.md)。

## 4. 从 WSL 源码构建并启动 Compose

以下命令均在 Ubuntu 的仓库根目录执行：

```bash
docker compose --env-file .env -f infra/compose/docker-compose.yml config --quiet
docker compose --env-file .env -f infra/compose/docker-compose.yml up -d --build
docker compose --env-file .env -f infra/compose/docker-compose.yml ps -a
curl -fsS http://127.0.0.1:3100/ready
curl -fsS -o /dev/null http://127.0.0.1:5173/
```

首次构建需要下载镜像和依赖。`computer` 与 `data-init` 是一次性任务，在 `ps -a` 中显示 `Exited (0)` 表示已正常完成。随后在 Windows 浏览器打开 <http://127.0.0.1:5173>，创建首个账户、连接模型并创建 Bot。Windows 访问 WSL/容器服务若失败，先分别在 Ubuntu 和 Windows PowerShell 检查 Web：

```bash
curl -fsS -o /dev/null http://127.0.0.1:5173/
```

```powershell
curl.exe -f http://127.0.0.1:5173/
```

如果服务未就绪，检查服务状态和日志：

```bash
docker compose --env-file .env -f infra/compose/docker-compose.yml ps -a
docker compose --env-file .env -f infra/compose/docker-compose.yml \
  logs --tail=100 postgres api worker web supervisor
```

若构建需要使用宿主机代理，而 `HTTP_PROXY` 或 `HTTPS_PROXY` 指向宿主机的 `127.0.0.1`，应先构建、再清除本次启动的代理变量；容器中的回环地址指向容器自身：

```bash
docker compose --env-file .env -f infra/compose/docker-compose.yml build
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  docker compose --env-file .env -f infra/compose/docker-compose.yml up -d --no-build
```

平时在同一目录启动和停止服务：

```bash
docker compose --env-file .env -f infra/compose/docker-compose.yml up -d
docker compose --env-file .env -f infra/compose/docker-compose.yml down
```

源码更新后使用 `up -d --build` 重新构建。`down` 保留数据库卷和仓库内的 `data/`；不要将 `down -v` 用作日常停止命令，它会删除 PostgreSQL 数据卷。完整的备份与升级步骤见[自托管指南](./self-host.md#backup)。

## 5. 在 Windows 从源码运行 Electron 客户端

在 Windows 安装 [Git](https://git-scm.com/install/windows) 和仓库支持的 [Node.js](https://nodejs.org/en/download)：22.22.2 及以上的 22.x、24.x，或 26.x 及以上；安装 `pnpm@9.15.0`。用 Windows PowerShell 在**独立目录**检出同一版本的源码，不与 WSL 共用 `node_modules`：

```powershell
npm install -g pnpm@9.15.0
git clone -c core.autocrlf=false https://github.com/elie222/rakazo.git rakazo-desktop
cd rakazo-desktop
pnpm install --frozen-lockfile
pnpm --filter @rakazo/desktop dev
```

首次启动选择 **Existing instance**，输入 `http://127.0.0.1:5173`。**This computer** 会由 Electron 另起一套已发布镜像，不能用它连接第 4 步构建的源码服务。如果需要 Windows 安装包，在 Windows 源码目录执行：

```powershell
pnpm --filter @rakazo/web build
pnpm --filter @rakazo/desktop build
pnpm --filter @rakazo/desktop exec electron-builder --win --x64 --publish never
```

本地构建产物位于 `apps/desktop/out/`。正式发布的 Windows 安装包还涉及代码签名，见[桌面发布说明](./desktop-release.md)。若两份源码在不同时间检出，可分别运行 `git rev-parse HEAD` 核对版本；需要精确对应时，在 Windows 检出与 WSL 相同的提交。

## 6. 将工位 USB 设备接入 WSL，并由工程师烧录

本节只使 **Ubuntu 中的工位程序**有机会访问设备，不给 Rakazo 电脑容器透传 USB。先在 Windows 安装 [usbipd-win](https://github.com/dorssel/usbipd-win)。[微软的 WSL USB 指南](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)要求 WSL 内核版本至少为 5.10.60.1；可在 Ubuntu 运行 `uname -r` 检查，过旧时在 Windows PowerShell 执行 `wsl --update`。以下命令适用于该指南所述的当前 usbipd-win 版本；设备号 `<BUSID>` 来自本机 `usbipd list`，不能照抄示例值。

在**管理员 PowerShell** 中查看并共享设备，`bind` 只需在首次共享时执行：

```powershell
usbipd list
usbipd bind --busid <BUSID>
```

保持一个 WSL 终端打开，在 PowerShell 中接入设备；该命令通常不需要管理员权限：

```powershell
usbipd attach --wsl --busid <BUSID>
```

在 Ubuntu 中确认设备及对应驱动。如果没有 `lsusb`，先安装 Ubuntu 的 `usbutils` 软件包：

```bash
sudo apt install -y usbutils
lsusb
ls -l /dev/serial/by-id/ 2>/dev/null || true
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true
```

不同设备可能显示为串口节点，也可能通过其他 USB 接口工作；节点名称、驱动、权限和烧录命令以设备供应商及工位脚本为准。先由工程师在 Ubuntu 手动验证设备识别、固件校验、烧录和烧录后测试。USB 接入 WSL 时，Windows 通常不能同时使用该设备；设备拔插或重置后可能需要重新 `attach`。操作结束可在 PowerShell 中运行 `usbipd detach --busid <BUSID>`。[微软的 WSL USB 操作指南](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)说明了这些步骤及权限要求。

当前试点可让 Rakazo 在对话中整理一份**待执行烧录单**，工程师确认后手动运行现有工位脚本。建议烧录单至少包含：需求或变更编号、固件版本、构建产物标识与 SHA-256、目标设备型号与设备标识、工位、预期验证项目、执行人及批准状态。脚本命令和固件路径应由实际工位流程确定，不在公共教程中编造。执行后回填开始与结束时间、脚本退出码、设备回读版本、验证结果和日志位置；失败时保留失败记录并停止交付。

## 7. 后续接入受控烧录工具

**Rakazo 当前没有内置 WSL 烧录工具；本节是实施方案，不是可直接执行的配置步骤。**现有全 Compose 部署的 Bot `shell` 仍在 Docker 电脑容器中，不能仅通过 `usbipd attach --wsl` 获得串口。路径 A 中，Docker Desktop [不支持直接 USB 设备透传](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/general/)；其 [USB/IP 指南](https://docs.docker.com/desktop/features/usbip/)列出的 Windows 适用范围是 Hyper-V 后端，不是本教程采用的 WSL 2 后端。路径 B 中，设备接入 WSL 后也不会自动出现在 Docker 电脑容器内，仍需另行设计设备授权和透传。

后续可以在固定工位实现只接受结构化请求的服务，再通过 Rakazo 的可选工具集成接入。建议工具仅接受已经登记的烧录单 ID；工位服务从可信记录中读取固件与设备参数，检查批准状态、产物校验值和设备标识，调用预设脚本，并返回可核验的执行状态与记录。Bot 只负责发起请求和读取结果，不能传入任意 Shell 命令、脚本路径、固件路径或设备节点。工位服务的认证、网络可达性和故障恢复都需要在实现时验证；容器中的 `127.0.0.1` 不是 WSL 工位的回环地址。

```text
Bot 在 Docker 电脑中完成浏览器工作
  → 提交待执行烧录单
  → 工程师确认固件、设备和批准状态
  → 工位服务执行固定脚本并保存结果（未来接入）
  → Bot 读取结果并整理交付记录
```

第一阶段停在人工执行：确认 Rakazo 能输出完整烧录单，工程师能按单完成烧录，并且版本、校验值、设备和验证结果可以相互追溯。只有这些记录稳定后，才把执行步骤接到受控工具上。

## 8. 批量交付：预制 WSL 发行版

若要给多台 Windows 电脑部署相同环境，可以在一台制作机上准备**专用、干净的** WSL 2 Ubuntu，再用 `wsl --export` 导出 tar；其他电脑用 `wsl --import` 导入。这能省去每台电脑重复安装 Docker Engine、Compose 和系统依赖的步骤，但目标电脑仍须满足 WSL 2 的系统要求。以下采用第 2 节的**路径 B**，不依赖 Docker Desktop。[微软的导出与导入命令](https://learn.microsoft.com/en-us/windows/wsl/basic-commands/)说明了这种分发方式。

### 制作基础镜像

在专门用于制作镜像的 Ubuntu 发行版中完成第 2 节路径 B 的安装，固定并检出要交付的 Rakazo 版本。可以预置源码和构建依赖；若预置 Docker 镜像，也会增加导出包体积。**不要先按第 3、4 节创建业务实例再直接导出**：WSL 导出的是整个发行版文件系统，不仅是程序。交付前应检查以下内容不会进入镜像：

- `.env`、模型密钥、登录凭据、SSH 密钥、浏览器配置、Shell 历史及个人代理配置；
- Rakazo 的 `data/`、数据库卷、Docker 容器与卷中的业务数据，以及构建缓存里可能留下的私有内容；
- 真实设备标识、固件、客户数据和工位日志。

最稳妥的做法是从全新发行版制作基础镜像，只安装公开软件与公开源码，**不启动 Rakazo、不创建数据库和账户**。不要把一台已经投入使用的 WSL 发行版仅靠删除几个文件就当作公共模板。导出前在 Windows PowerShell 关闭发行版，再导出；下面的 `RakazoSeed` 是制作发行版的示例名称：

```powershell
wsl --terminate RakazoSeed
wsl --export RakazoSeed .\rakazo-wsl.tar
Get-FileHash .\rakazo-wsl.tar -Algorithm SHA256
```

记录交付包的版本、架构和 SHA-256，供接收方核对。导出包包含 Linux 文件系统，应按安装包而非源码文件管理；不要把它提交到公共 Git 仓库。

### 在用户电脑导入并首次初始化

先确认 Windows 已启用并能运行 WSL 2，再把 tar 放到本地目录。在 Windows PowerShell 中导入；`RakazoData` 是该用户电脑上的发行版数据目录示例：

```powershell
Get-FileHash .\rakazo-wsl.tar -Algorithm SHA256
New-Item -ItemType Directory -Force .\RakazoData
wsl --import Rakazo .\RakazoData .\rakazo-wsl.tar --version 2
wsl --list --verbose
wsl -d Rakazo
```

`wsl --import` 导入的普通发行版默认以 `root` 启动。首次初始化需要为每台电脑创建自己的普通 Linux 用户并设为默认用户，确认该用户有 Docker 权限，然后**在目标电脑上**生成第 3 节的随机密钥、创建 `.env`，按第 4 节启动 Compose 和检查就绪。不要在镜像中预置共享的 Linux 密码、Rakazo 管理员账户或 `.env`。用户创建与默认用户设置可参考[微软的自定义发行版指南](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro/)；若以后要做正式安装包，可以用[WSL 的首次运行配置](https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro/)自动完成用户创建。当前仓库尚未提供这样的导入与首次初始化脚本。

Windows Electron 客户端仍需单独安装或按第 5 节构建，并选择 **Existing instance** 连接 `http://127.0.0.1:5173`。现有 **This computer** 流程不会导入 WSL 镜像，也不会调用 WSL 内的 Docker Engine。Windows 重启后，启动器还需唤起该 WSL 发行版并检查 Docker 与 Rakazo；systemd 服务自身[不会让 WSL 一直保持运行](https://learn.microsoft.com/en-us/windows/wsl/systemd/)。USB 设备仍按第 6 节在每台工位分别接入，镜像不会复制 Windows 驱动或设备授权。

要把这些步骤做成真正的一键交付，后续 Windows 启动器应依次完成：WSL 2 预检、安装包校验、发行版导入、目标机独立密钥与用户初始化、Compose 启动、就绪检查，以及桌面端连接。上述命令是当前可手工验证的分发路径，不代表这些自动化能力已经实现。

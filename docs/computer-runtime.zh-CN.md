# Computer 运行环境

Rakazo 将智能体运行环境与 Computer 运行环境分开：

```text
聊天/API -> 单个 Pi 智能体会话 -> Rakazo Computer 工具 -> SandboxProvider -> E2B / Daytona / Box
                                                        |-> Docker
                                                        |-> desktop/fake

SandboxProvider 工作区 <-> AgentHomeStore <-> Rakazo 自有的 DATA_DIR
```

Pi 在 Rakazo 的 API/worker 进程中运行，不会安装在 E2B 中，也不会在 E2B 中执行。内置工具是普通的 Pi 工具，并非 Claude 或 MCP 专用，因此任何通过 Pi 接入的模型都可以调用。操作屏幕仍要求模型能够接收工具返回的图片，并根据截图进行推理。

## Computer 契约

默认情况下，每个工作空间有一台 Team Computer。Bot 共享它的文件和已安装工具。每个 Team bot 从 `bots/<bot-id>/` 开始工作，刻意共享的内容放在 `shared/`。这些目录只用于组织文件，并非安全边界：每个 Team bot 都能访问整个 Team 工作区。Bot 也可以改用 Private Computer，此时整个工作区就是它的主目录。

每个活跃的 Team bot 都有自己的 X 显示器和 Chrome 进程，并使用按 bot 身份关联的持久化 Chrome 配置文件。登录状态、Cookie 和浏览历史互不干扰。释放桌面时，不会复制其他 bot 的配置文件、合并配置文件，也不会删除配置文件。不同 bot 各自保留自己的更改；即使重新打开时分配到不同的显示器槽位，bot 仍使用原来的配置文件。Team 运行使用按 bot 划分、带隔离栅栏的数据库租约：不同 bot 可以并行操作，而同一个 bot 同一时间只能有一个 Computer 驱动者。

Docker、E2B、Daytona 和 Box 使用相同的 Linux 桌面生命周期命令。远程适配器共享分配、观察、操作和控制处理逻辑；提供方代码负责命令执行、持久化工作区路径和屏幕 URL。Box 通过受保护的 `host <port> --private` 路由暴露共享运行环境，而不使用其默认桌面 API。观看和控制分别使用可撤销的 WebSocket 权限凭证；拆除桌面时，会先断开客户端连接，再复用显示器槽位。如果拆除失败，该槽位会保留，等待重试。

Bot 使用图形工具时才会按需启动桌面组件。默认没有配置桌面数量上限；一台 Computer 可以保存 100 个以上的 bot 配置文件，而同时运行的桌面数量受其内存、CPU、进程容量和可用本地调试端口限制。Docker 管理员可以设置正数的 `SANDBOX_TEAM_SCREEN_LIMIT`，限制活跃桌面数量（`0` 表示不设置上限）。超过显式上限的请求会返回 `MULTI_SCREEN_UNAVAILABLE`；shell 和文件工具仍可使用。所有桌面共享一个受令牌保护的屏幕网关，因此增加桌面不需要开放更多端口。每个观看/控制权限凭证都指向唯一的本地 Unix 套接字；复用显示器不会把旧连接重定向到下一个 bot。非活跃 bot 不会各自运行 Chrome。关闭观看窗口不会关闭桌面。运行结束时释放该 bot 的桌面；整台 Computer 空闲关机时会停止剩余进程，但保留工作区。桌面本身没有单独的空闲计时器。持久化配置文件占用磁盘空间，但不需要 Chrome 进程持续运行。

`SandboxProvider` 是提供方边界。后端必须实现：

- 生命周期：创建或重连、停止和销毁；
- 桌面：观察、按顺序批量执行操作、用户输入和实时屏幕会话；
- 执行：在 Computer 内运行命令；
- 文件：列出、读取、写入文件，以及完整工作区的导入和导出。

在支持图形界面的 Computer 上，模型可以使用 `browser_navigate`、`browser_snapshot` 和 `browser_act` 获取页面文本与元素引用。默认的 `computer` 浏览器提供方通过沙箱可选的 `pageBrowser` 契约操作可见的 Chromium 标签页。Docker 通过与桌面控制相同的托管屏幕和租约检查实现该契约；需要更新 Computer 镜像以安装辅助程序。其他提供方在实现该契约之前，继续使用现有的桌面工具。无需托管浏览器服务或 API Key。

Computer 容器是安全边界。Team bot 共享操作系统用户、工作区、浏览器配置文件以及 shell/X11 访问权限；屏幕租约协调工具调用，不能隔离同一台 Computer 内互不信任的进程。CDP 只绑定到容器的回环接口，不作为宿主机端口发布。需要隔离工作负载时，应使用不同的 Computer。

辅助程序使用隔离的脚本执行环境、遮蔽密码值，并拒绝过期的元素引用，而不会将其重新指向替代元素。快照包含限量的页面文本和最多 80 个可交互元素。操作页面框架和不受支持的交互需要桌面工具。操作失败时会报告已确认的进度，以及结果是否不确定：继续前先检查当前状态，绝不要自动重放已完成或结果不确定的操作。对于没有视觉能力的模型，如果页面工具无法操作，应请求用户接管。

虚拟 Computer 和显式设置的 `BROWSER_PROVIDER=fake|emulator` 使用进程内会话进行测试。这些会话不是实时的、已登录的浏览器。浏览器修改操作沿用现有的教学模式防护和工作区检查点流程。是否提供 `computer_observe`、批量 `computer_act`、`open_path`、`launch_app`、`shell` 和文件工具，取决于 Computer 与模型的能力。连续出现相同的桌面画面时，工具结果保留元数据，但不再向模型上下文重复发送图片字节，并说明上一张截图仍然有效。如果重复执行同一个视觉操作后画面仍不变，`computer_act` 会拒绝再次执行该操作，并引导智能体使用页面文本工具。

用户和智能体可以同时在不同的 Team 屏幕上输入。“接管”会授予用户该 bot 屏幕的独占控制租约，使嵌入式观看窗口能够接收输入。对于 Team bot，如果该 bot 持有有效的 Computer 执行租约或存在活跃运行，接管会被拒绝并返回 HTTP 409（“先停止 bot”）；例外是运行处于 `waiting_takeover` 状态，即 bot 请求用户输入受保护信息。应先停止 bot，再接管；用户释放控制权后，智能体可以继续。模型明确需要受保护输入或人工判断时，仍可使用 `request_takeover`。

## 终端和文件

在 Web 和桌面端的 Computer 视图中，可以通过屏幕上的程序坞打开终端和文件浏览器。程序坞的浏览器按钮会隐藏这些窗口，同时保留它们的会话，让整块屏幕重新可见。

**终端**

- “活动”视图始终显示 bot 在其 Computer 上所做的操作，包括实时操作和历史记录。每个操作都记录为 `computer.command` 事件：
  - `shell` 命令，包括脱敏后的命令和输出末尾部分；
  - `write_file`、`attach_file`、`open_path` 和 `launch_app` 各占一行；写入操作显示大小，失败操作显示错误。

  只读工具（`read_file`、`list_files`）不会出现在这里。用户持有控制权期间，bot 仍可以运行命令，因此活动记录始终可用。
- 用户没有控制权时（例如控制权已释放或过期），“打开 shell”按钮会重新取得控制权并切换到 shell。
- 持有控制权的用户还可以使用带交互式 shell 的 Shell 标签页。它在首次使用时启动，切换标签页后保持连接；如果连接中断，则重新连接到一个新的 shell。`computer.terminalUrl` 会在 Computer 内、屏幕网关旁启动一个小型 PTY 服务器。
  - 它绑定到显示器的控制令牌，并通过与控制屏幕相同的封装权限凭证和网关访问。同一租约下后续建立的会话（另一个标签页或重新打开的窗口）会以各自的 shell 加入该服务器，因此已打开的 shell 可以继续运行。
  - 它以 Computer 的工作区用户身份运行（绝不使用 root），环境与 bot 的 `shell` 工具相同。Docker exec 继承容器的非 root 用户；E2B、Daytona 和 Box 使用与 `shell` 相同的命令运行器。当 Computer 使用宿主机 UID 运行、但该 UID 没有 passwd 条目时（macOS 上的 Docker），终端会在自己的会话中通过 nss_wrapper 将该用户命名为 `rakazo`，使提示符和 `whoami` 正常工作；`/etc/passwd` 保持不变。
  - 释放控制权、租约过期或拆除屏幕时，服务器会停止、断开所有 shell 并删除会话文件。
- 提供方通过 `SandboxProvider.connectTerminal` 选择支持该功能。Docker、E2B、Daytona 和 Box 均支持。宿主机（`desktop`）Computer 从不向浏览器暴露 shell；其他不支持该功能的 Computer 只显示“活动”视图。
- 虚拟提供方通过回环 WebSocket 网关提供模拟 shell，使用相同的帧协议。测试因此可以经封装权限凭证和 Web 代理操作浏览器终端，而不会暴露宿主机 shell。

**文件**

- Computer 停止后，仍可通过已存储的工作区浏览文件和预览文本。
- “文件”窗口可见时，打开的文件夹每隔几秒以及每次 bot 执行命令后都会刷新，因此 shell 或 bot 所做的更改无需重新打开窗口即可看到。
- 下载文件需要 Computer 处于运行状态。
- 上传文件还需要控制权。上传的文件会放到 bot 的工作区路径下，并受附件大小上限约束。

## 屏幕连接诊断

Web 服务会记录 `screen.proxy.target_rejected`、`screen.proxy.http_failed`、`screen.proxy.http_upstream_response`、`screen.proxy.websocket_handshake_failed`、`screen.proxy.websocket_error`、`screen.proxy.websocket_upgraded`、`screen.proxy.websocket_closed` 和撤销事件。每个事件都包含随机的 `screen.connection_id` 以及观看/控制策略。WebSocket 关闭事件还包含上游握手是否完成、连接持续时间，以及发起关闭的一方（`client`、`upstream` 或 `revoked`）。日志不包含权限凭证 URL、套接字令牌、提供方主机名、Cookie 或请求头。

屏幕显示连接错误时，先查看 API 日志中的 `computer.screenUrl` 是否成功，再检查同一时间附近 Web 服务的 `screen.proxy.*` 事件。遇到 `screen.proxy.target_rejected` 时，查看 `reason`：`invalid_path` 表示路径不是会话路径（尚未联系 API）；`authority_rejected` 表示 API 返回非成功响应（过期、已撤销或 API 错误）；`invalid_authority_response` 表示 API 返回成功响应，但目标响应体无效或格式错误；`authority_unavailable` 表示请求、连接或超时故障。上游错误或非 101 握手响应指向提供方的屏幕网关。连接升级成功却很快关闭，说明握手之后传输中断。如果 API 已签发 URL，但 Web 服务中没有对应事件，请检查浏览器“网络”面板及其 WebSocket 请求。不要将完整的权限凭证 URL 粘贴到 issue 或日志中。

## E2B 后端

E2B 适配器使用 `@e2b/desktop` 管理机器生命周期、shell 命令、文件和端口 URL。每个 bot 桌面（包括第一个 bot）都使用共享的 Linux 运行环境。它的 X 显示器、截图、输入和观看/控制传输遵循与其他托管提供方相同的生命周期。

## Daytona 后端

数据库保存提供方类型和不透明的 `providerRef`。该引用只用于加速重连，不是持久数据。它只会传回相同类型的提供方。如果机器不存在或提供方类型改变，系统会创建替代机器，并通过提供方无关的契约恢复其工作区。

## Box 后端

Box 适配器使用 ASCII 官方 TypeScript SDK 管理生命周期、命令和文件操作。按第三方提供 API Key 时的要求，它使用 `noEnv: true` 创建和恢复 Box，并在 Computer 活跃期间不断刷新两小时的存活时间。共享运行环境为每个 bot 创建显示器和 noVNC 传输，并通过受保护的 Box 端口托管服务暴露。Rakazo 的加密屏幕权限代理绑定观看/控制策略，避免提供方凭据出现在浏览器可见的 URL 中。观察和操作均指向分配给该 bot 的显示器。

停止 Box 会归档机器；恢复时使用同一个不透明 Box ID 重新连接。每个 bot 的 Chrome 配置文件位于可迁移工作区中，并包含在检查点/导出中。Box 模拟器使用与其他托管提供方模拟器相同的多屏幕契约。

## 持久化

可迁移的 Computer 工作区是持久化边界。E2B 使用 `/home/user/rakazo-home`；Docker 和本地提供方暴露等效的主目录。在 E2B 上，浏览器配置文件位于该工作区的 `.browser-profiles` 目录下。运行完成或失败后、显式停止前以及空闲挂起前，Rakazo 会将迁移出的工作区保存到 `AgentHomeStore` 检查点。Docker 直接挂载 Rakazo 自有的主目录，只在这些边界推进版本标记。新机器或替代机器使用前，会导入最新保存的工作区。

`LocalAgentHomeStore` 目前将最新工作区保存在 `DATA_DIR/homes/<computer-home-key>` 下，并将检查点元数据另存于 `DATA_DIR/home-revisions`。替换当前副本前会先暂存新副本；每台 Computer 的检查点操作按顺序执行。当前实现只保留最新版本，不是不可变的版本归档。生产部署必须把 `DATA_DIR` 放在 Rakazo 自有的持久卷上，对该卷进行静态加密，并将其纳入异地备份。存储接口刻意与 E2B 解耦，因此可以用对象存储实现替换本地卷，而无需更改智能体工具或沙箱提供方。

导出远程工作区前，远程后端会让桌面浏览器停止活动，以一致地复制配置文件数据库和登录状态。如果其他 bot 持有执行租约或用户控制租约，运行检查点会延后；最后一个结束的运行或空闲任务会保存共享工作区。空闲关机任务会在导出前占用 Computer，防止快照期间启动新的 bot。导出时只排除 `.browser-profiles` 内的临时缓存/锁文件；项目中名称相似的文件仍会持久保存。

可丢弃的操作系统镜像不是可迁移的磁盘快照。切换提供方时，安装在工作区之外的系统软件包会丢失；持久的机器定制应通过可复现的镜像或安装流程表达。这样将来才能切换后端，而不必转换各提供方特有的虚拟机快照。

Docker Computer 包含 `uv`，可在无需 root 权限的情况下安装 Python 命令行工具。运行 `uv tool install <package>`；工具环境、命令入口、受管理的 Python 版本及缓存都会保存在持久化主目录下。这只能安装 Python 命令行工具，不能安装 `apt` 依赖等系统软件包。镜像也自带 GitHub 的 `gh` CLI；bot 通过设备授权流程为 CLI 登录，`gh` 将凭据保存在持久化主目录中。可使用 `pdftotext`、`pandoc` 和 `openpyxl` 从 PDF、文档和电子表格中提取文本。

## 验证

[智能体验证指南](agent-verification.md)还介绍了通过真实 Pi 重放联系人导出任务的确定性测试，可以使用有状态的虚拟 Computer，也可以使用真实的 Docker Chromium。该测试无需模型推理，与下方的视觉能力验收测试互为补充。

离线测试覆盖工具返回的图片、操作解析、提供方契约符合性（包括页面浏览器适配器和 `computer_act` 回退）、工作区检查点与恢复、提供方 SDK 转换、生命周期集成，以及多屏幕托管提供方模拟器。这些测试不会调用模型或真实沙箱。

显式运行的验收测试需要 Docker（用于临时 Postgres）、`E2B_API_KEY`、`OPENROUTER_API_KEY` 和具备视觉能力的 OpenRouter 模型 ID：

```bash
COMPUTER_E2E_MODEL=<vision-capable-openrouter-model-id> pnpm test:computer
```

测试会启动完整 API、创建真实 E2B 桌面、在沙箱内提供确定性的页面，并让真实模型观察页面、点击按钮。按钮会创建服务端标记；随后测试要求模型使用终端和文件工具，并验证标记与记录下来的工具调用。最后，测试会销毁提供方机器，通过过期的提供方引用启动替代机器，验证外部检查点恢复了模型创建的文件。该命令需要显式选择运行；除非明确调用，否则 `pnpm test` 和 CI 都不会运行它。

### Docker 桌面生命周期回归测试

先构建 Computer 镜像，再运行 `VERIFY_DOCKER_TEAM_SCREENS=1 pnpm exec vitest run infra/sandboxes/supervisor/src/team-desktops.docker.test.ts`。可设置 `RAKAZO_COMPUTER_IMAGE` 选择预构建镜像。测试使用禁用网络的隔离 Docker 容器和虚拟浏览器状态，验证并行 Chrome 桌面访问本地测试站点、Cookie 相互独立、释放后配置文件保持持久、传输通道拆除，以及槽位复用后旧观看/控制令牌被拒绝。测试同时覆盖 Docker 监管逻辑和远程提供方使用的命令路径。默认单元测试无需 Docker，即可离线测试配置文件持久化、分配和租约隔离。

## Computer 维护

更新和恢复作为持久化后台任务运行。操作在保存和替换工作区期间会占用整台 Computer，阻止新的执行租约、停止、接管、空闲挂起和 Computer 模式更改。进度与 Computer 的创建隔离栅栏分开存储。Web 和 Electron 显示对话框或紧凑的后台提示；移动端使用原生底部弹层。重新打开应用时，会从 API 恢复活跃操作和故障状态。

更新会明确使用已配置的提供方/镜像重新构建；`canUpdate` 表示 Computer 支持该操作，不代表检测到了更新的镜像。此界面不提供提供方迁移或镜像版本发现。更新会在拆除前保存进行中的工作。恢复可以退回到上次保存的工作区，因此恢复失败时的操作会提示用户：未保存的工作可能丢失。

协调器会在入队遗漏后重新发布排队中的操作。已被领取的任务绝不会以可能造成破坏的方式重放。Worker 停止发送心跳十分钟后，操作会被标记为中断，并继续占用 Computer，直到其提供方调用结束；之后才允许恢复。如果 Worker 已永久消失，管理员必须先停止受影响的 Worker，并确认提供方操作已停止，才能在中断对话框中使用仅服务器所有者可用的 **释放 Computer** 操作。确认时必须明确声明 Worker 和提供方操作都已停止，之后才会开放正常恢复。对应的 RPC 为 `computer/releaseInterrupted`，参数是 `{ id, workersStopped: true }`；它只接受所有者当前工作空间中已中断的操作。仅凭心跳过期绝不会授权接管。进度报告的是实际生命周期阶段，而非估算百分比；工作区文件和浏览器配置文件可迁移，工作区外的系统软件包则不可迁移。

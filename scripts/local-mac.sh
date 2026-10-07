#!/usr/bin/env bash
# 在当前 macOS 用户会话中，手动启动、停止或查看当前源码仓库的 Rakazo 服务。
# 用法：bash scripts/local-mac.sh {start|stop|status}
# 通过 launchd 托管进程；配置不放入登录自启动目录，不注册开机自启动。
set -euo pipefail

# 从脚本位置定位仓库，避免依赖调用时的工作目录；状态文件和日志存放在用户目录。
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="${HOME}/.local/state/rakazo/manual"
agent_dir="${state_dir}/agents"
log_dir="${HOME}/.local/state/rakazo/logs"
# 标记 Colima 是否由本脚本启动，供停止时判断是否可以一并关闭。
colima_marker="${state_dir}/started-colima"
domain="gui/$(id -u)"
services=(supervisor api worker web)

# 后续 Docker 命令统一连接 Colima，避免操作其他 Docker 环境。
export DOCKER_CONTEXT=colima

# 输出可用子命令；参数缺失或无效时以退出码 2 结束。
usage() {
  printf 'Usage: %s {start|stop|status}\n' "$0" >&2
  exit 2
}

# 统一调用 Compose：读取仓库 .env，并叠加 PostgreSQL 的本机端口映射配置。
# 将函数收到的参数原样传给 docker compose，例如 up、stop 或 ps。
compose() {
  docker compose --env-file "${root_dir}/.env" \
    -f "${root_dir}/infra/compose/docker-compose.yml" \
    -f "${root_dir}/infra/compose/docker-compose.postgres-host.yml" "$@"
}

# 检查指定服务（第一个参数）是否已注册到当前用户的 launchd 会话。
# 仅通过退出码返回结果：已注册不代表进程正在运行，也不代表服务健康。
agent_loaded() {
  launchctl print "${domain}/local.rakazo.$1" >/dev/null 2>&1
}

# 为四个本机服务生成 launchd plist，记录启动命令、工作目录和日志位置。
# 此函数只生成配置；实际加载由 start 完成。找不到 pnpm 时返回失败。
write_agents() {
  local pnpm_bin
  pnpm_bin="$(command -v pnpm)" || {
    echo 'pnpm is unavailable; enable Corepack and retry.' >&2
    return 1
  }
  export RAKAZO_LOCAL_ROOT="${root_dir}"
  export RAKAZO_LOCAL_AGENT_DIR="${agent_dir}"
  export RAKAZO_LOCAL_LOG_DIR="${log_dir}"
  export RAKAZO_LOCAL_PNPM="${pnpm_bin}"
  python3 - <<'PY'
import os
import plistlib
from pathlib import Path

root = Path(os.environ["RAKAZO_LOCAL_ROOT"])
agents = Path(os.environ["RAKAZO_LOCAL_AGENT_DIR"])
logs = Path(os.environ["RAKAZO_LOCAL_LOG_DIR"])
pnpm = os.environ["RAKAZO_LOCAL_PNPM"]
path = os.environ["PATH"]
# Supervisor 管理机器人电脑，API 处理接口，Worker 执行后台任务，Web 提供界面。
commands = {
    "supervisor": [pnpm, "--filter", "@rakazo/sandbox-supervisor", "start"],
    "api": [pnpm, "--filter", "@rakazo/api", "start"],
    "worker": [pnpm, "--filter", "@rakazo/worker", "start"],
    "web": [pnpm, "--filter", "@rakazo/web", "preview", "--host", "127.0.0.1", "--port", "5173", "--strictPort"],
}
for name, command in commands.items():
    label = f"local.rakazo.{name}"
    config = {
        "Label": label,
        "ProgramArguments": command,
        "WorkingDirectory": str(root),
        "EnvironmentVariables": {"PATH": path},
        # 手动加载后立即启动，进程退出后自动拉起；stop 会卸载这些任务。
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 15,
        "StandardOutPath": str(logs / f"{name}.out.log"),
        "StandardErrorPath": str(logs / f"{name}.err.log"),
    }
    target = agents / f"{label}.plist"
    with target.open("wb") as handle:
        plistlib.dump(config, handle)
    target.chmod(0o600)
PY
}

# 检查配置、依赖和构建产物，按需启动 Colima、数据库及四个本机服务。
# 跳过已注册的 launchd 服务，因此再次执行 start 不等于重启或重新加载配置。
# 最后探测 API 和 Web；失败返回非零，不自动回滚此前已启动的组件。
start() {
  [[ -f "${root_dir}/.env" ]] || { echo 'Missing .env in the repository root.' >&2; return 1; }
  [[ -d "${root_dir}/node_modules" ]] || { echo 'Install dependencies before starting.' >&2; return 1; }
  [[ -f "${root_dir}/apps/web/dist/index.html" ]] || { echo 'Build the web app before starting.' >&2; return 1; }
  command -v docker >/dev/null || { echo 'Docker CLI is unavailable.' >&2; return 1; }
  command -v colima >/dev/null || { echo 'Colima is unavailable.' >&2; return 1; }
  umask 077
  mkdir -p "${agent_dir}" "${log_dir}"

  if ! colima status >/dev/null 2>&1; then
    # 使用 macOS 虚拟化框架，配置 4 核 CPU、4 GiB 内存和 100 GiB 虚拟磁盘。
    colima start --runtime docker --vm-type vz --cpu 4 --memory 4 --disk 100
    touch "${colima_marker}"
  fi
  docker info >/dev/null
  compose up postgres -d --wait
  docker image inspect rakazo/computer:local >/dev/null || {
    echo 'Build the bot computer image with pnpm sandbox:build before starting.' >&2
    return 1
  }

  write_agents
  local name
  for name in "${services[@]}"; do
    if ! agent_loaded "${name}"; then
      launchctl bootstrap "${domain}" "${agent_dir}/local.rakazo.${name}.plist"
    fi
  done

  # 最多探测 45 轮，失败后间隔 1 秒；curl 未设超时，总耗时可能超过 45 秒。
  local attempt
  for attempt in {1..45}; do
    if curl -fsS http://127.0.0.1:3100/internal/health >/dev/null 2>&1 &&
       curl -fsS http://127.0.0.1:5173/ >/dev/null 2>&1; then
      echo 'Rakazo is ready at http://127.0.0.1:5173'
      return 0
    fi
    sleep 1
  done
  echo "Rakazo did not become ready; inspect logs under ${log_dir}." >&2
  return 1
}

# 遍历运行中的 Rakazo 托管容器，以挂载路径判断是否属于当前仓库。
# 只停止挂载了当前仓库 data/homes/ 路径的容器，不删除容器或机器人文件。
stop_owned_computers() {
  local container_id mounts
  while IFS= read -r container_id; do
    [[ -n "${container_id}" ]] || continue
    mounts="$(docker inspect --format '{{range .Mounts}}{{.Source}}{{println}}{{end}}' "${container_id}")"
    if [[ "${mounts}" == *"${root_dir}/data/homes/"* ]]; then
      docker stop "${container_id}" >/dev/null
    fi
  done < <(docker ps -q --filter label=rakazo.managed=true)
}

# 依次卸载 Web、Worker、API、Supervisor，再停止当前仓库的电脑容器和数据库。
# 只有存在本脚本的启动标记、且没有任何运行中容器时，才一并关闭 Colima。
# 保留 PostgreSQL 数据卷、机器人文件及日志，方便下次启动继续使用。
stop() {
  local name
  for name in web worker api supervisor; do
    if agent_loaded "${name}"; then
      launchctl bootout "${domain}" "${agent_dir}/local.rakazo.${name}.plist"
    fi
  done
  if colima status >/dev/null 2>&1; then
    stop_owned_computers
    compose stop postgres
    if [[ -f "${colima_marker}" ]]; then
      if [[ -z "$(docker ps -q)" ]]; then
        colima stop
        rm -f "${colima_marker}"
      else
        echo 'Colima remains running because other containers are active.'
      fi
    fi
  fi
  echo 'Rakazo stopped; PostgreSQL data and bot homes were retained.'
}

# 显示四个 launchd 服务的进程状态，以及 Colima 和 PostgreSQL 容器状态。
# 仅查看状态，不启动或停止服务；这里的 running 不代表接口健康检查通过。
status() {
  local name state
  for name in "${services[@]}"; do
    state='stopped'
    if agent_loaded "${name}" &&
       launchctl print "${domain}/local.rakazo.${name}" | grep -q 'state = running'; then
      state='running'
    fi
    printf '%-12s %s\n' "${name}" "${state}"
  done
  if colima status >/dev/null 2>&1; then
    printf '%-12s running\n' colima
    compose ps postgres
  else
    printf '%-12s stopped\n' colima
  fi
}

# 根据第一个命令行参数分派操作；未提供参数时按空字符串处理。
case "${1:-}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) usage ;;
esac

#!/usr/bin/env bash
# 在 Ubuntu 上从当前源码构建并手动管理 Rakazo Docker Compose 服务。
# 用法：bash scripts/local-ubuntu.sh {start|rebuild|stop|status}
set -euo pipefail

# 从脚本位置定位仓库，避免依赖调用时的工作目录。
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${root_dir}/infra/compose/docker-compose.yml"
env_file="${root_dir}/.env"

usage() {
  printf '用法：%s {start|rebuild|stop|status}\n' "$0" >&2
  exit 2
}

# 使用仓库中的配置和项目默认名称，确保与部署教程中的 Compose 命令管理同一组容器。
compose() {
  docker compose --env-file "${env_file}" -f "${compose_file}" "$@"
}

# 运行服务时移除宿主机的回环代理；容器中的 127.0.0.1 不指向宿主机。
# 镜像构建仍继承代理，以便下载依赖。
compose_runtime() {
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    docker compose --env-file "${env_file}" -f "${compose_file}" "$@"
}

check_requirements() {
  [[ -f "${env_file}" ]] || { echo '仓库根目录缺少 .env，请先按部署教程配置。' >&2; return 1; }
  command -v docker >/dev/null || { echo '未找到 Docker CLI。' >&2; return 1; }
  docker compose version >/dev/null || { echo '未找到 Docker Compose 插件。' >&2; return 1; }
  docker info >/dev/null 2>&1 || {
    echo '无法连接 Docker。请确认服务已启动，并重新登录以使 docker 组权限生效。' >&2
    return 1
  }
  compose config --quiet
}

start() {
  local rebuild="${1:-false}"
  check_requirements
  command -v curl >/dev/null || { echo '未找到 curl。' >&2; return 1; }
  # 首次运行或显式 rebuild 时构建；日常 start 复用本项目已有的源码镜像。
  if [[ "${rebuild}" == true ]] ||
     ! docker image inspect compose-api compose-worker compose-web compose-supervisor \
       rakazo/computer:local >/dev/null 2>&1; then
    compose build
  fi
  # 使用已构建镜像启动，不将宿主机回环代理带入 API 和 Worker。
  compose_runtime up -d --no-build

  # 等待 API 和 Web 可访问；每次请求最多等待 2 秒。
  local attempt
  for attempt in {1..60}; do
    if curl --fail --silent --max-time 2 http://127.0.0.1:3100/ready >/dev/null &&
       curl --fail --silent --max-time 2 http://127.0.0.1:5173/ >/dev/null; then
      echo 'Rakazo 已启动：http://127.0.0.1:5173'
      return 0
    fi
    sleep 2
  done
  echo 'Rakazo 未能就绪，请运行 status 并查看 Compose 日志。' >&2
  return 1
}

# 只停止挂载了当前仓库 data/homes/ 的机器人电脑容器。
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

stop() {
  check_requirements
  stop_owned_computers
  # stop 保留容器、PostgreSQL 数据卷和仓库 data/，下次 start 可继续使用。
  compose_runtime stop
  echo 'Rakazo 已停止；数据库和机器人文件已保留。'
}

status() {
  check_requirements
  # computer 和 data-init 是一次性任务，Exited (0) 是正常状态。
  compose_runtime ps -a
}

case "${1:-}" in
  start) start ;;
  rebuild) start true ;;
  stop) stop ;;
  status) status ;;
  *) usage ;;
esac

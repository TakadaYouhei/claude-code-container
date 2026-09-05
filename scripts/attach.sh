#!/usr/bin/env bash
# アタッチスクリプト: CONTAINER_ENGINE に応じて docker/podman exec を選択し、
# コンテナ内の tmux セッション（work）にアタッチする。無ければ新規作成する。
#
# 使い方:
#   ./scripts/attach.sh [プロジェクト名]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_NAME="${1:-}"

if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
fi

CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"

PROJECT_ARGS=()
if [ -n "${PROJECT_NAME}" ]; then
  PROJECT_ARGS=(-p "${PROJECT_NAME}")
fi

cd "${ROOT_DIR}"

case "${CONTAINER_ENGINE}" in
  docker)
    COMPOSE_CMD=(docker compose)
    ;;
  podman)
    if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
      COMPOSE_CMD=(podman compose -f docker-compose.yml -f docker-compose.podman.yml)
    elif command -v podman-compose >/dev/null 2>&1; then
      COMPOSE_CMD=(podman-compose -f docker-compose.yml -f docker-compose.podman.yml)
    else
      echo "podman compose / podman-compose が見つかりません。./scripts/check-env.sh を実施済みか確認してください。" >&2
      exit 1
    fi
    ;;
  *)
    echo "CONTAINER_ENGINE: '${CONTAINER_ENGINE}' は未対応の値です。docker または podman を指定してください。" >&2
    exit 1
    ;;
esac

CONTAINER_ID="$("${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" ps -q claude-code)"
if [ -z "${CONTAINER_ID}" ]; then
  echo "起動中のコンテナが見つかりません。先に ./scripts/up.sh を実行してください。" >&2
  exit 1
fi

exec "${CONTAINER_ENGINE}" exec -it "${CONTAINER_ID}" tmux attach -t work \
  || exec "${CONTAINER_ENGINE}" exec -it "${CONTAINER_ID}" tmux new -s work

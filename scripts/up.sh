#!/usr/bin/env bash
# 起動スクリプト: CONTAINER_ENGINE に応じて compose 起動コマンド・override ファイルを選択する。
# 対応要件: 4.8, 4.9（docs/design.md 5章）
#
# 使い方:
#   ./scripts/up.sh [プロジェクト名]

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

# shellcheck source=scripts/lib/detect-engine.sh
source "${SCRIPT_DIR}/lib/detect-engine.sh"
CONTAINER_ENGINE="$(detect_container_engine "${CONTAINER_ENGINE:-}")"

echo "=== 環境チェックを実行します (CONTAINER_ENGINE=${CONTAINER_ENGINE}) ==="
if ! "${SCRIPT_DIR}/check-env.sh"; then
  echo "環境チェックで NG が検出されたため、起動処理を中止しました。" >&2
  exit 1
fi

PROJECT_ARGS=()
if [ -n "${PROJECT_NAME}" ]; then
  PROJECT_ARGS=(-p "${PROJECT_NAME}")
fi

cd "${ROOT_DIR}"

case "${CONTAINER_ENGINE}" in
  docker)
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
      echo "docker compose が見つかりません。./scripts/check-env.sh を実施済みか確認してください。" >&2
      exit 1
    fi
    echo "=== docker compose でコンテナを起動します ==="
    docker compose "${PROJECT_ARGS[@]}" up -d --build
    ;;
  podman)
    COMPOSE_CMD=()
    if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
      COMPOSE_CMD=(podman compose)
    elif command -v podman-compose >/dev/null 2>&1; then
      COMPOSE_CMD=(podman-compose)
    else
      echo "podman compose / podman-compose が見つかりません。./scripts/check-env.sh を実施済みか確認してください。" >&2
      exit 1
    fi
    # podman-compose は docker compose と異なり、イメージを再ビルドしても
    # 実行中のコンテナを自動では再作成しない（設定/イメージの変更検知が弱い）ため、
    # --force-recreate を付けて明示的に作り直す。付けないと、
    # ./scripts/up.sh でイメージを直しても古いコンテナが動き続けてしまう。
    echo "=== ${COMPOSE_CMD[*]} でコンテナを起動します（docker-compose.podman.yml を自動適用） ==="
    "${COMPOSE_CMD[@]}" -f docker-compose.yml -f docker-compose.podman.yml "${PROJECT_ARGS[@]}" up -d --build --force-recreate
    ;;
  *)
    echo "CONTAINER_ENGINE: '${CONTAINER_ENGINE}' は未対応の値です。docker または podman を指定してください。" >&2
    exit 1
    ;;
esac

echo "コンテナを起動しました。"

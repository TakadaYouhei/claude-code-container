#!/usr/bin/env bash
# 起動スクリプト: podman compose（無ければ podman-compose）でコンテナを起動する。
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

# shellcheck source=scripts/lib/compose-cmd.sh
source "${SCRIPT_DIR}/lib/compose-cmd.sh"

echo "=== 環境チェックを実行します ==="
if ! "${SCRIPT_DIR}/check-env.sh"; then
  echo "環境チェックで NG が検出されたため、起動処理を中止しました。" >&2
  exit 1
fi

PROJECT_ARGS=()
if [ -n "${PROJECT_NAME}" ]; then
  PROJECT_ARGS=(-p "${PROJECT_NAME}")
fi

cd "${ROOT_DIR}"

detect_compose_cmd || exit 1
# podman-compose は docker compose と異なり、イメージを再ビルドしても
# 実行中のコンテナを自動では再作成しない（設定/イメージの変更検知が弱い）ため、
# --force-recreate を付けて明示的に作り直す。付けないと、
# ./scripts/up.sh でイメージを直しても古いコンテナが動き続けてしまう。
echo "=== ${COMPOSE_CMD[*]} でコンテナを起動します ==="
"${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" up -d --build --force-recreate

echo "コンテナを起動しました。"

#!/usr/bin/env bash
# 再構築スクリプト: コンテナを破棄し、イメージをキャッシュ無しで作り直してから起動し直す。
# ボリューム（認証情報・ワークスペース・dotfiles）は削除せず引き継ぐ。
#
# 使い方:
#   ./scripts/rebuild.sh [プロジェクト名]

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

# ボリュームを消すと再ログイン・再 clone が必要になるため、-v は付けない。
echo "=== コンテナを破棄します（ボリュームは保持） ==="
"${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" down

# Claude Code を最新版で入れ直すため、キャッシュを使わずにビルドする。
echo "=== イメージをキャッシュ無しで再ビルドします ==="
"${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" build --no-cache

# 起動処理（環境チェック・override 適用）は up.sh に任せる。
# 直前にビルド済みのため、up.sh 内の --build はキャッシュが効いてすぐ終わる。
"${SCRIPT_DIR}/up.sh" "${PROJECT_NAME}"

echo "再構築が完了しました。./scripts/attach.sh でアタッチできます。"

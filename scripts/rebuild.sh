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

# shellcheck source=scripts/lib/compose-cmd.sh
source "${SCRIPT_DIR}/lib/compose-cmd.sh"

PROJECT_ARGS=()
if [ -n "${PROJECT_NAME}" ]; then
  PROJECT_ARGS=(-p "${PROJECT_NAME}")
fi

cd "${ROOT_DIR}"

detect_compose_cmd || exit 1

# ボリュームを消すと再ログイン・再 clone が必要になるため、-v は付けない。
echo "=== コンテナを破棄します（ボリュームは保持） ==="
"${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" down

# Claude Code を最新版で入れ直すため、キャッシュを使わずにビルドする。
echo "=== イメージをキャッシュ無しで再ビルドします ==="
"${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" build --no-cache

# 起動処理（環境チェック含む）は up.sh に任せる。
# 直前にビルド済みのため、up.sh 内の --build はキャッシュが効いてすぐ終わる。
"${SCRIPT_DIR}/up.sh" "${PROJECT_NAME}"

echo "再構築が完了しました。./scripts/attach.sh でアタッチできます。"

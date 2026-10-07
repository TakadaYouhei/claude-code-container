#!/usr/bin/env bash
# アタッチスクリプト: podman exec で
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

# shellcheck source=scripts/lib/compose-cmd.sh
source "${SCRIPT_DIR}/lib/compose-cmd.sh"

PROJECT_ARGS=()
if [ -n "${PROJECT_NAME}" ]; then
  PROJECT_ARGS=(-p "${PROJECT_NAME}")
fi

cd "${ROOT_DIR}"

detect_compose_cmd || exit 1

# podman-compose の `ps` サブコマンドは docker compose と異なり、
# サービス名を引数として受け付けない（`-q`/`--quiet` のみ対応）ため、サービス名は渡さない。
CONTAINER_ID="$("${COMPOSE_CMD[@]}" "${PROJECT_ARGS[@]}" ps -q | head -n1)"
if [ -z "${CONTAINER_ID}" ]; then
  echo "起動中のコンテナが見つかりません。先に ./scripts/up.sh を実行してください。" >&2
  exit 1
fi

# entrypoint.sh はコンテナ内で root から dev ユーザーへ su してから tmux
# セッションを作成する。tmux のソケットは UID ごとに分かれる（/tmp/tmux-<uid>/）ため、
# ここで -u dev を指定せずに exec すると（コンテナの既定ユーザーである root として
# 実行され）dev のセッションが見えず「no sessions」と表示されてしまう。
# 必ず dev ユーザーとして exec する。
#
# また `exec A || exec B` は A の起動（execve）自体が失敗した場合のみ B を実行する
# ため、A（tmux attach）が「起動はできたがセッションが無く終了コード非0で終わる」
# ケースでは B（tmux new）にフォールバックできない。判定と exec を分離する。
if podman exec -u dev "${CONTAINER_ID}" tmux has-session -t work 2>/dev/null; then
  exec podman exec -it -u dev "${CONTAINER_ID}" tmux attach -t work
else
  exec podman exec -it -u dev "${CONTAINER_ID}" tmux new -s work
fi

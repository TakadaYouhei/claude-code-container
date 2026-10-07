# podman の compose コマンドを検出する（各スクリプトから source して使う）
# 使い方:
#
#   # shellcheck source=scripts/lib/compose-cmd.sh
#   source "${SCRIPT_DIR}/lib/compose-cmd.sh"
#   detect_compose_cmd || exit 1
#   "${COMPOSE_CMD[@]}" up -d
#
# podman compose が使えればそれを、無ければ podman-compose を COMPOSE_CMD 配列に設定する。
# リポジトリのルートで実行する前提で compose.yml を明示する。
# どちらも無い場合はエラーメッセージを出して非0を返す。
detect_compose_cmd() {
  if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(podman compose -f compose.yml)
  elif command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(podman-compose -f compose.yml)
  else
    echo "podman compose / podman-compose が見つかりません。./scripts/check-env.sh を実施済みか確認してください。" >&2
    return 1
  fi
}

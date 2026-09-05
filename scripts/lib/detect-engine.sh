# CONTAINER_ENGINE 未指定時のフォールバック検出（各スクリプトから source して使う）
# 使い方: CONTAINER_ENGINE の値を確定させた後に detect_container_engine を呼ぶ
#
#   CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
#   # shellcheck source=scripts/lib/detect-engine.sh
#   source "${SCRIPT_DIR}/lib/detect-engine.sh"
#   CONTAINER_ENGINE="$(detect_container_engine "${CONTAINER_ENGINE}")"
#
# .env にも環境変数にも CONTAINER_ENGINE が指定されていない場合、docker が
# 見つからず podman のみ利用可能な環境（Podman only ホスト）で不当に NG に
# ならないよう、実際にインストールされているエンジンを見て docker/podman を
# 自動選択する。両方指定なしの場合は従来通り docker を既定値とする。
detect_container_engine() {
  local specified="${1:-}"
  if [ -n "${specified}" ]; then
    printf '%s' "${specified}"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    printf 'docker'
  elif command -v podman >/dev/null 2>&1; then
    printf 'podman'
  else
    printf 'docker'
  fi
}

#!/usr/bin/env bash
# セットアップ前環境チェックスクリプト
# 対応要件: 4.9（docs/design.md 6章）
#
# 使い方:
#   ./scripts/check-env.sh
#
# 終了コード: 全項目 OK の場合 0、必須項目に1つでも NG がある場合 1。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
fi

MIN_DISK_GB="${MIN_DISK_GB:-10}"
RECOMMENDED_MEM_GB="${RECOMMENDED_MEM_GB:-4}"
CHECK_TARGET_DIR="${ROOT_DIR}"

FAILED=0

ok() {
  printf '[OK] %s\n' "$1"
}

ng() {
  printf '[NG] %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '      -> 対処: %s\n' "$2"
  fi
  FAILED=1
}

warn() {
  printf '[WARN] %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '      -> 対処: %s\n' "$2"
  fi
}

version_ge() {
  # $1 >= $2 なら真
  [ "$1" = "$2" ] && return 0
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# 1. Podman の有無・バージョン
check_engine() {
  if ! command -v podman >/dev/null 2>&1; then
    ng "Podman: 未インストール" \
       "https://podman.io/docs/installation の手順に従い Podman をインストールしてください。"
    return
  fi
  local ver
  ver="$(podman --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  if [ -z "${ver}" ]; then
    ng "Podman: バージョン取得に失敗しました" "podman --version が正常に実行できるか確認してください。"
    return
  fi
  if version_ge "${ver}" "4.0.0"; then
    ok "Podman: ${ver} (>= 4.0 required)"
  else
    ng "Podman: ${ver} (>= 4.0 required)" "Podman を 4.0 以上にアップグレードしてください。"
  fi
}

# 2. compose ツールの有無
check_compose() {
  if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
    ok "podman compose: $(podman compose version 2>/dev/null | head -n1)"
  elif command -v podman-compose >/dev/null 2>&1; then
    ok "podman-compose: $(podman-compose --version 2>/dev/null | head -n1)"
  else
    ng "podman compose / podman-compose: 利用不可" \
       "'pip install podman-compose' または podman compose プラグインを導入してください。"
  fi
}

# 3. /dev/fuse・/dev/net/tun（コンテナ内の podman が fuse-overlayfs・slirp4netns で使う）
check_devices() {
  local dev mod
  for dev in /dev/fuse /dev/net/tun; do
    case "${dev}" in
      /dev/fuse) mod=fuse ;;
      /dev/net/tun) mod=tun ;;
    esac
    if [ -c "${dev}" ]; then
      ok "${dev}: 利用可能"
    else
      ng "${dev}: 見つかりません" \
         "${mod} カーネルモジュールを読み込んでください（例: 'sudo modprobe ${mod}'）。コンテナ内で podman を動かすのに必要です。"
    fi
  done
}

# 4. 必須コマンド
check_required_commands() {
  local cmd
  for cmd in git; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      ok "${cmd}: $(${cmd} --version | head -n1)"
    else
      ng "${cmd}: 未インストール" "パッケージマネージャ（apt/yum/brew 等）で ${cmd} をインストールしてください。"
    fi
  done
}

# 5. ディスク空き容量
check_disk_space() {
  local avail_kb avail_gb
  avail_kb="$(df -Pk "${CHECK_TARGET_DIR}" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [ -z "${avail_kb}" ]; then
    warn "disk free space: 取得に失敗しました" "df コマンドが利用可能か確認してください。"
    return
  fi
  avail_gb=$((avail_kb / 1024 / 1024))
  if [ "${avail_gb}" -ge "${MIN_DISK_GB}" ]; then
    ok "disk free space: ${avail_gb}GB (>= ${MIN_DISK_GB}GB required)"
  else
    ng "disk free space: ${avail_gb}GB (>= ${MIN_DISK_GB}GB required)" \
       "不要なイメージ・ボリュームを削除するか、ディスクを拡張してください。"
  fi
}

# 6. git ユーザー情報（任意・警告のみ）
check_git_identity() {
  if ! command -v git >/dev/null 2>&1; then
    return
  fi
  local git_name git_email
  git_name="$(git config --get user.name 2>/dev/null || true)"
  git_email="$(git config --get user.email 2>/dev/null || true)"
  if [ -n "${git_name}" ] && [ -n "${git_email}" ]; then
    ok "git user.name/user.email: ${git_name} <${git_email}>"
  else
    warn "git user.name/user.email: 未設定です" \
         "'git config --global user.name \"<名前>\"' と 'git config --global user.email \"<メールアドレス>\"' を実行してください。"
  fi
}

# 7. メモリ（任意・警告のみ）
check_memory() {
  local mem_kb mem_gb
  if [ -r /proc/meminfo ]; then
    mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    mem_gb=$((mem_kb / 1024 / 1024))
    if [ "${mem_gb}" -ge "${RECOMMENDED_MEM_GB}" ]; then
      ok "memory: ${mem_gb}GB (recommended >= ${RECOMMENDED_MEM_GB}GB)"
    else
      warn "memory: ${mem_gb}GB (recommended >= ${RECOMMENDED_MEM_GB}GB)" \
           "推奨メモリ量を下回っていますが、セットアップは続行できます。"
    fi
  else
    warn "memory: 取得に失敗しました（/proc/meminfo が見つかりません）" "手動でホストのメモリ量を確認してください。"
  fi
}

# 8. ネットワーク到達性
check_network() {
  if ! command -v curl >/dev/null 2>&1; then
    ng "network reachability: curl が見つかりません" "curl をインストールしてから再実行してください。"
    return
  fi
  # ルートパスは 4xx を返すことがあるため、接続自体が確立できたか（curl の終了コード）で判定する。
  if curl -sS --max-time 5 -o /dev/null https://api.anthropic.com 2>/dev/null; then
    ok "network reachability: https://api.anthropic.com に到達可能"
  else
    ng "network reachability: https://api.anthropic.com に到達不可" \
       "プロキシ設定・ファイアウォール設定を確認し、アウトバウンド HTTPS 通信を許可してください。"
  fi
}

echo "=== claude-code-container 環境チェック ==="
check_engine
check_compose
check_devices
check_required_commands
check_disk_space
check_git_identity
check_memory
check_network
echo "==================================================================="

if [ "${FAILED}" -ne 0 ]; then
  echo "セットアップを中断しました。上記 NG 項目を解消後、再実行してください。"
  exit 1
fi

echo "すべての必須項目が OK です。セットアップを続行できます。"
exit 0

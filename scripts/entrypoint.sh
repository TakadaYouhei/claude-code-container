#!/usr/bin/env bash
# コンテナ常駐用エントリポイント（初回clone・権限調整）
# 対応要件: 4.3, 4.4, 4.11（docs/design.md 7章）

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
CLAUDE_HOME="/home/dev/.claude"
DOTFILES_DIR="/home/dev/.dotfiles"
DEFAULT_SETTINGS="/opt/claude-container/claude-settings.default.json"
REPO_MARKER="${WORKSPACE_DIR}/.repo-initialized"

# root で起動された場合は、ボリュームの所有者を dev ユーザーへ調整したうえで
# dev ユーザーへ権限を落として以降の処理を継続する（5.1: 非root実行）。
if [ "$(id -u)" = "0" ]; then
  echo "[entrypoint] ボリュームの所有者を dev ユーザーへ調整します..."
  mkdir -p "${WORKSPACE_DIR}" "${CLAUDE_HOME}" "${DOTFILES_DIR}"
  chown -R dev:dev "${WORKSPACE_DIR}" "${CLAUDE_HOME}" "${DOTFILES_DIR}"
  chmod 700 "${DOTFILES_DIR}" "${CLAUDE_HOME}"
  echo "[entrypoint] dev ユーザーへ切り替えて起動処理を継続します..."
  # -l（ログインシェル）は環境変数をリセットしてしまうため使わない。
  # GIT_REPO_URL 等（docker-compose の environment で設定）を dev ユーザーへ引き継ぐ。
  exec su -s /bin/bash dev -c "/home/dev/scripts/entrypoint.sh"
fi

echo "[entrypoint] dev ユーザーとして起動処理を開始します。"

# dotfiles ボリューム配下のファイルを ~/.bash_history・~/.gitconfig・~/.ssh へシンボリックリンクする
link_dotfile() {
  local target="$1"    # dotfiles ボリューム側の実体パス
  local link_path="$2" # コンテナ内のリンク先パス
  local kind="$3"       # file または dir

  if [ "${kind}" = "dir" ]; then
    mkdir -p "${target}"
    chmod 700 "${target}"
  else
    [ -e "${target}" ] || : > "${target}"
  fi

  if [ -L "${link_path}" ]; then
    return 0
  fi
  if [ -e "${link_path}" ]; then
    rm -rf "${link_path}"
  fi
  ln -s "${target}" "${link_path}"
}

echo "[entrypoint] dotfiles（bash_history / gitconfig / ssh）のリンクを確認します..."
link_dotfile "${DOTFILES_DIR}/bash_history" "/home/dev/.bash_history" "file"
link_dotfile "${DOTFILES_DIR}/gitconfig" "/home/dev/.gitconfig" "file"
link_dotfile "${DOTFILES_DIR}/ssh" "/home/dev/.ssh" "dir"

# ~/.claude/settings.json が未配置であればデフォルトのフック設定を複製する（初回起動時のみ）
if [ -f "${DEFAULT_SETTINGS}" ] && [ ! -f "${CLAUDE_HOME}/settings.json" ]; then
  echo "[entrypoint] デフォルトの Claude Code 設定（フック定義）を配置します..."
  cp "${DEFAULT_SETTINGS}" "${CLAUDE_HOME}/settings.json"
fi

# 対象リポジトリの自動 clone（初回起動時のみ・マーカーファイルで判定）
if [ ! -f "${REPO_MARKER}" ]; then
  if [ -n "${GIT_REPO_URL:-}" ]; then
    REPO_NAME="$(basename "${GIT_REPO_URL}" .git)"
    REPO_PATH="${WORKSPACE_DIR}/${REPO_NAME}"
    if [ -d "${REPO_PATH}/.git" ]; then
      echo "[entrypoint] ${REPO_PATH} は既に clone 済みのため、clone をスキップします。"
      echo "${REPO_NAME}" > "${REPO_MARKER}"
    else
      echo "[entrypoint] 対象リポジトリを clone します: ${GIT_REPO_URL} -> ${REPO_PATH}"
      # clone に失敗しても（SSH known_hosts 未設定・認証情報未設定など）
      # set -e でコンテナごと落として再起動ループさせない。
      # アタッチして原因を直せるよう、マーカーは書かずに起動処理を継続し、
      # 次回起動時に再度 clone を試みられるようにする。
      if git clone "${GIT_REPO_URL}" "${REPO_PATH}"; then
        echo "${REPO_NAME}" > "${REPO_MARKER}"
      else
        echo "[entrypoint] リポジトリの clone に失敗しました。コンテナにアタッチし、SSH鍵/known_hosts 等を確認したうえで手動で clone してください。" >&2
        rm -rf "${REPO_PATH}"
      fi
    fi
  else
    echo "[entrypoint] GIT_REPO_URL が未設定のため、自動 clone をスキップしました。"
    echo "[entrypoint] .env に GIT_REPO_URL を設定し、コンテナを再作成してください。"
  fi
else
  echo "[entrypoint] リポジトリは初期化済みです（$(cat "${REPO_MARKER}")）。clone をスキップします。"
fi

# 認証情報が未設定であればログインを促す
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -f "${CLAUDE_HOME}/.credentials.json" ]; then
  echo "[entrypoint] Claude Code の認証情報が見つかりません。"
  echo "[entrypoint] コンテナにアタッチして 'claude login' を実行するか、ANTHROPIC_API_KEY を設定してください。"
fi

# tmux サーバーをバックグラウンドで起動（セッションが無ければ作成）
echo "[entrypoint] tmux セッションを準備します..."
tmux start-server || true
if ! tmux has-session -t work 2>/dev/null; then
  tmux new-session -d -s work -c "${WORKSPACE_DIR}"
fi

echo "[entrypoint] 起動処理が完了しました。コンテナを常駐させます。"
echo "[entrypoint] アタッチ例: ./scripts/attach.sh"

# フォアグラウンドプロセスとして待受状態を維持し、コンテナを常駐させる
exec tail -f /dev/null

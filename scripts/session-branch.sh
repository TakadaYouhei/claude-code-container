#!/usr/bin/env bash
# 対話セッション開始検知 -> ブランチ作成
# Claude Code の SessionStart フックとして呼び出される。
# 対応要件: 4.11（docs/design.md 11.1, 11.2章）
#
# 標準入力: Claude Code から渡される SessionStart フックの JSON
#   （session_id, source 等を含む）。

set -uo pipefail

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
BASE_BRANCH="${GIT_BASE_BRANCH:-main}"
REPO_MARKER="${WORKSPACE_DIR}/.repo-initialized"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "${INPUT}" | jq -r '.session_id // empty' 2>/dev/null)"

# 対象リポジトリが未初期化（clone未実施）の場合は何もしない
if [ ! -f "${REPO_MARKER}" ]; then
  echo "[session-branch] リポジトリが未初期化のため、ブランチ作成をスキップしました。" >&2
  exit 0
fi

REPO_NAME="$(cat "${REPO_MARKER}")"
REPO_PATH="${WORKSPACE_DIR}/${REPO_NAME}"

if [ ! -d "${REPO_PATH}/.git" ]; then
  echo "[session-branch] ${REPO_PATH} が Git リポジトリではないため、ブランチ作成をスキップしました。" >&2
  exit 0
fi

cd "${REPO_PATH}" || exit 0

# セッション単位のブランチ対応表（リポジトリには含めない: .git/info/exclude で除外）
STATE_DIR="${REPO_PATH}/.claude-container/session-branches"
mkdir -p "${STATE_DIR}"
EXCLUDE_FILE="${REPO_PATH}/.git/info/exclude"
if [ -f "${EXCLUDE_FILE}" ] && ! grep -qxF '.claude-container/' "${EXCLUDE_FILE}" 2>/dev/null; then
  echo '.claude-container/' >> "${EXCLUDE_FILE}"
fi

if [ -z "${SESSION_ID}" ]; then
  SESSION_ID="fallback-$(date +%s)-$$"
fi

MAP_FILE="${STATE_DIR}/${SESSION_ID}"

# 既にこの対話セッション用のブランチが作成済みであれば、新規作成せず継続する
if [ -f "${MAP_FILE}" ]; then
  BRANCH_NAME="$(cat "${MAP_FILE}")"
  echo "[session-branch] 既存の対話セッション用ブランチを継続します: ${BRANCH_NAME}"
  if ! git checkout "${BRANCH_NAME}" >/dev/null 2>&1; then
    echo "[session-branch] 警告: ブランチ ${BRANCH_NAME} への切り替えに失敗しました。" >&2
  fi
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SHORT_ID="$(printf '%s' "${SESSION_ID}" | tr -dc 'a-zA-Z0-9' | cut -c1-8)"
if [ -z "${SHORT_ID}" ]; then
  SHORT_ID="$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
BRANCH_NAME="session/${TIMESTAMP}-${SHORT_ID}"

echo "[session-branch] 新しい対話セッションを検知しました。ブランチを作成します: ${BRANCH_NAME}"

git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1

if git show-ref --verify --quiet "refs/remotes/origin/${BASE_BRANCH}"; then
  BASE_REF="origin/${BASE_BRANCH}"
elif git show-ref --verify --quiet "refs/heads/${BASE_BRANCH}"; then
  BASE_REF="${BASE_BRANCH}"
else
  BASE_REF="HEAD"
fi

if git checkout -b "${BRANCH_NAME}" "${BASE_REF}" >/tmp/session-branch-checkout.log 2>&1; then
  echo "${BRANCH_NAME}" > "${MAP_FILE}"
  echo "[session-branch] ブランチ ${BRANCH_NAME} を作成しました（ベース: ${BASE_REF}）。"
else
  echo "[session-branch] ブランチ作成に失敗しました:" >&2
  cat /tmp/session-branch-checkout.log >&2
fi

exit 0

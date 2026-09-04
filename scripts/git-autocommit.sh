#!/usr/bin/env bash
# 変更検知 -> commit/push 自動化
# Claude Code の Stop フックとして呼び出される（1指示=1ラウンドにつき1コミットを既定とする）。
# 対応要件: 4.11, 5.1（docs/design.md 11.3章）
#
# 標準入力: Claude Code から渡される Stop フックの JSON（session_id 等を含む）。
# push 失敗時（コンフリクト/認証エラー/ネットワーク断）は自動リトライを行わず、
# エラー内容を提示したうえで、変更はローカルの commit として保持する（force push は行わない）。

set -uo pipefail

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
REPO_MARKER="${WORKSPACE_DIR}/.repo-initialized"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "${INPUT}" | jq -r '.session_id // empty' 2>/dev/null)"

if [ ! -f "${REPO_MARKER}" ]; then
  exit 0
fi

REPO_NAME="$(cat "${REPO_MARKER}")"
REPO_PATH="${WORKSPACE_DIR}/${REPO_NAME}"

if [ ! -d "${REPO_PATH}/.git" ]; then
  exit 0
fi

cd "${REPO_PATH}" || exit 0

BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "${BRANCH_NAME}" ] || [ "${BRANCH_NAME}" = "HEAD" ]; then
  echo "[git-autocommit] 現在のブランチを特定できないため、自動 commit/push をスキップしました。" >&2
  exit 0
fi

HAS_CHANGES=false
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  HAS_CHANGES=true
fi

COMMIT_LOG="$(mktemp)"
PUSH_LOG="$(mktemp)"

if [ "${HAS_CHANGES}" = "true" ]; then
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
  COMMIT_MSG="Auto-commit: session ${SESSION_ID:-unknown} (${TIMESTAMP})"

  git add -A -- . ':!.claude-container'

  if ! git commit -m "${COMMIT_MSG}" >"${COMMIT_LOG}" 2>&1; then
    echo "[git-autocommit] commit に失敗しました:" >&2
    cat "${COMMIT_LOG}" >&2
    rm -f "${COMMIT_LOG}" "${PUSH_LOG}"
    exit 0
  fi

  echo "[git-autocommit] commit しました: $(git rev-parse --short HEAD) (${BRANCH_NAME})"
fi

# 前回の push が失敗している場合に備え、リモートに対して未反映のコミットがあれば push を試みる
NEED_PUSH=false
if git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH_NAME}" >/dev/null 2>&1; then
  AHEAD_COUNT="$(git rev-list --count "origin/${BRANCH_NAME}..HEAD" 2>/dev/null || echo 0)"
  [ "${AHEAD_COUNT}" -gt 0 ] && NEED_PUSH=true
elif git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  NEED_PUSH=true
fi

if [ "${NEED_PUSH}" != "true" ]; then
  rm -f "${COMMIT_LOG}" "${PUSH_LOG}"
  exit 0
fi

if git push origin "${BRANCH_NAME}" >"${PUSH_LOG}" 2>&1; then
  echo "[git-autocommit] push しました: origin/${BRANCH_NAME}"
else
  echo "[git-autocommit] push に失敗しました（コンフリクト・認証エラー・ネットワーク断の可能性があります）。" >&2
  echo "[git-autocommit] 変更はローカルの commit として保持されています。次の指示で再度 push が試みられます。" >&2
  cat "${PUSH_LOG}" >&2
fi

rm -f "${COMMIT_LOG}" "${PUSH_LOG}"
exit 0

# claude-code-container: 自動承認モードのデフォルト化
# 対応要件: 4.10（docs/design.md 10章）
#
# CLAUDE_AUTO_APPROVE=true（既定）の場合、素の `claude` コマンドを
# `claude --dangerously-skip-permissions` 相当（web版ライクな非対話自動承認）として実行する。
# 逐一確認したい場合は CLAUDE_AUTO_APPROVE=false を .env に設定するか、
# `command claude` で素のコマンドを直接呼び出す。
claude() {
  if [ "${CLAUDE_AUTO_APPROVE:-true}" = "true" ]; then
    command claude --dangerously-skip-permissions "$@"
  else
    command claude "$@"
  fi
}

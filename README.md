# claude-code-container
Claude Code を実行するためのコンテナ艦橋

## クイックスタート

詳細な手順は [取り扱い説明書](docs/manual.md) を参照。

```bash
git clone <このリポジトリの URL>
cd claude-code-container
cp .env.example .env
# .env を編集して GIT_REPO_URL 等を設定する

./scripts/check-env.sh   # セットアップ前環境チェック
./scripts/up.sh          # コンテナ起動（CONTAINER_ENGINE に応じて docker/podman を自動選択）
./scripts/attach.sh      # コンテナ内の tmux セッションにアタッチ（無ければ新規作成）
# コンテナ内で: claude login
```

## ドキュメント

- [要件定義書](docs/requirements.md)
- [ユースケース定義書](docs/use-cases.md)
- [設計書](docs/design.md)
- [取り扱い説明書](docs/manual.md)

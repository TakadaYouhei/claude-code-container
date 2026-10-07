# claude-code-container 取り扱い説明書

本書は `claude-code-container`（Claude Code を実行するためのコンテナ艦橋）を利用する
エンドユーザー向けの操作マニュアルである。仕様の詳細は [要件定義書](requirements.md)、
利用シーンの詳細は [ユースケース定義書](use-cases.md) を参照すること。

## 1. 本書の対象読者

- クラウド VM やオンプレサーバー上にコンテナを構築し、Claude Code を継続的に使いたい個人開発者。
- コンテナの管理者を兼ねる利用者（ホストの操作権限を持つこと）。

## 2. 事前に準備するもの

| 項目 | 内容 |
| --- | --- |
| ホスト | インターネットに接続できる Linux サーバー（クラウド VM 等） |
| コンテナエンジン | Podman 4.0 以上（rootless）と、`podman compose` または `podman-compose`。Docker には対応しない |
| `/dev/fuse` | コンテナ内で podman（ビルド用コンテナ）を動かすのに必要（fuse カーネルモジュール） |
| Claude.ai アカウント | Claude Code を利用可能なプラン（Pro/Max 等）。または `ANTHROPIC_API_KEY` |
| Git | 作業対象のリポジトリへアクセスできる認証情報（GitHub PAT または SSH 鍵） |

## 3. セットアップの流れ

セットアップは次の順序で行う。

```
1. リポジトリを取得する
2. 環境変数ファイル（.env）を準備する
3. 環境チェックを実行する（scripts/check-env.sh）
4. コンテナを起動する
5. 初回ログイン（認証）を行う
6. 作業対象リポジトリを指定する
```

### 3.1 リポジトリの取得

```bash
git clone <このリポジトリの URL>
cd claude-code-container
```

### 3.2 環境変数ファイル（.env）の準備

コンテナの動作に必要な設定値は `.env` ファイルで指定する。サンプルファイルをコピーして
値を編集する。

```bash
cp .env.example .env
```

`.env` で設定する主な項目は以下のとおり。

| 変数 | 必須/任意 | 内容 |
| --- | --- | --- |
| `GIT_REPO_URL` | 必須 | 初回起動時に自動 clone する対象リポジトリの URL |
| `GIT_BASE_BRANCH` | 任意（既定 `main`） | セッション用ブランチの作成元となるベースブランチ |
| `ANTHROPIC_API_KEY` | 任意 | API キー認証を使う場合に設定する（未設定時は OAuth ログインを想定） |
| `CLAUDE_AUTO_APPROVE` | 任意（既定 `true`） | 自動承認モード（4.2）の有効/無効 |

`GIT_REPO_URL` には対象リポジトリへの認証情報を含む URL（GitHub PAT 付き HTTPS URL や SSH 鍵
経由の URL 等）を指定すること。この値は 3.6 節の自動 clone に使用される。

### 3.3 環境チェックの実行

コンテナを起動する前に、ホスト環境が要件を満たしているかを確認する。

```bash
./scripts/check-env.sh
```

以下の項目が OK / NG で表示される。

- Podman がインストール済みで、動作要件（4.0 以上）を満たすバージョンか（必須）
- `podman compose` / `podman-compose` が利用可能か（必須）
- `/dev/fuse` があるか（必須・コンテナ内で podman を動かすのに使う）
- `git` など必須コマンドが PATH 上に存在するか（必須）
- ディスク空き容量が最低要件を満たしているか（必須）
- git の `user.name` / `user.email` が設定済みか（任意・未設定でも警告表示のみでセットアップは続行できる）
- メモリが推奨要件を満たしているか（任意・NG でも警告表示のみでセットアップは続行できる）
- Anthropic API / claude.ai への到達性があるか（必須）

**必須項目で NG があった場合**は、表示される原因と対処方法（インストール手順・設定変更方法）に
従ってホスト環境を修正し、再度 `./scripts/check-env.sh` を実行すること。必須項目がすべて OK に
なるまで次のステップ（コンテナ起動）へは進めない。メモリや git ユーザー情報の NG（警告）は
セットアップを止めるものではないが、git ユーザー情報が未設定のままだとコンテナ内で commit した
際の author 情報が空になるため、`git config --global user.name "<名前>"` /
`git config --global user.email "<メールアドレス>"` をあらかじめ設定しておくことを推奨する。

### 3.4 コンテナの起動

起動は `scripts/up.sh` 経由で行う。`podman compose` / `podman-compose` を直接叩く必要はない。

```bash
./scripts/up.sh
```

> `scripts/up.sh` は `podman compose`（無ければ `podman-compose`）で `compose.yml` を使って起動する。
> sudo 権限が使えないホスト（会社支給端末など）でも rootless で利用できる。

起動後、コンテナはバックグラウンドで常駐する（`restart: unless-stopped` 相当のポリシー）。
ホストやコンテナが予期せず再起動しても、作業内容・認証情報は失われない（詳細は 6 章）。

### 3.5 初回ログイン（認証）

コンテナ内シェルにアタッチし、Claude.ai アカウントで認証する。

```bash
podman exec -it -u dev <コンテナ名> bash

claude login
```

ブラウザ経由の OAuth 認証フローに従ってログインする。認証情報はボリュームマウントされた
`~/.claude` 等のディレクトリに保存されるため、コンテナを再作成しても再ログインは不要になる。

`ANTHROPIC_API_KEY` を使う場合は、OAuth ログインの代わりに環境変数として設定することで
認証できる（併用・切り替え可）。

### 3.6 作業対象リポジトリの指定

コンテナの初回起動時に、対象リポジトリを一度だけ `git clone` して作業用ディレクトリ
（`/workspace` 等）に配置する。稼働中のコンテナで別のリポジトリへ途中から切り替えることは
想定していない。別のプロジェクトを扱いたい場合は、5 章の手順でコンテナを追加すること。

push 用の認証情報（GitHub PAT や SSH 鍵）はボリューム経由で永続化されるため、コンテナを
再作成しても再設定は不要である。

## 4. 日常の使い方

### 4.1 コンテナへのアタッチ

SSH でホストに接続したうえで、コンテナ内シェルにアタッチする。長時間セッションの
切断・再接続に備え、`tmux` セッション内で作業する。

```bash
ssh <ホスト>
./scripts/attach.sh
```

`scripts/attach.sh` はコンテナを特定し、
`podman exec -it -u dev <コンテナ名> tmux attach -t work || podman exec -it -u dev <コンテナ名> tmux new -s work`
に相当する処理を行う（毎回コンテナ名を打ち込む必要がない）。`up.sh` と同様に、
複数プロジェクトを起動している場合は引数でプロジェクト名を指定できる
（`./scripts/attach.sh <プロジェクト名>`）。

作業を中断する場合は `tmux` セッションをデタッチ（`Ctrl-b d`）したまま SSH 接続を切断してよい。
コンテナはバックグラウンドで稼働を継続し、次回接続時に同じ `tmux` セッションへ再アタッチできる。

### 4.2 Claude Code との対話（自動承認モード）

`tmux` セッション内で `claude` コマンドを実行する。デフォルトでは、`claude code on the web`
と同様にコマンド実行のたびに逐一承認を求めない自動承認モードで動作する。

```bash
claude
```

自然文で指示を送ると、Claude Code はコマンド実行・ファイル編集・Git 操作などの一連の作業を
承認確認なしに自律的に最後まで実行する。ただし force push などの破壊的操作はデフォルトでは
自動実行されない。逐一承認しながら進めたい場合は、対話モードに切り替えることもできる。

### 4.3 コンテナ内でのビルド用コンテナの利用

コンテナ内の `dev` ユーザーは rootless の `podman` を使える。ビルド環境をコンテナで用意したい場合は、
コンテナ内でそのまま `podman build` / `podman run` を実行する。

```bash
podman run --rm -v "$PWD":/src:Z -w /src docker.io/library/debian:bookworm make
```

- イメージ名は `docker.io/library/debian` のように完全な名前で指定する（短い名前の解決先は
  設定していない）。
- pull したイメージは `podman-storage` ボリュームに保存されるため、コンテナを作り直しても残る。

### 4.4 対話セッションとブランチ・commit / push の関係

Claude Code との1回の会話単位（＝1タスク）を「対話セッション」と呼ぶ。これは `tmux` / SSH の
接続セッションとは別の概念であり、SSH・`tmux` の接続を切断・再接続しても対話セッション自体
（＝作業中のブランチ）は継続する。

- 新しい対話セッションを開始すると、ベースブランチ（`main` 等）から自動的に新規ブランチが
  作成される。
- 同じ対話セッション内で追加の指示を送っても、新しいブランチは切られず、同じブランチ上で
  作業が継続される。
- 指示に基づく変更を行うたびに、自動的に `git commit` され、リモートへ `git push` される。
  利用者が都度手動でコミットする必要はない。
- push がコンフリクトや認証エラーで失敗した場合は、エラー内容が提示され、変更は次の指示まで
  ローカルのコミットとして保持される。
- 対話セッションが完了したら、リモートリポジトリ側でブランチの差分・Pull Request を確認する。
  別の依頼をする場合は新しい対話セッションを開始し、新規ブランチから作業する。

## 5. 複数プロジェクトの並行利用

1台のホスト上で、プロジェクトごとに別名のコンテナ・ボリュームをセットアップすることで、
複数プロジェクトを並行して利用できる。各コンテナは認証情報・作業ディレクトリを独立した
ボリュームで保持するため、一方の変更が他方に影響することはない。

```bash
# プロジェクト A
./scripts/up.sh project-a

# プロジェクト B
./scripts/up.sh project-b
```

## 6. 再起動・復旧

ホストが再起動した場合でも、以下の手順で環境を復旧できる。

```bash
./scripts/up.sh
```

自動起動が設定されていれば、Podman サービス（`podman-restart.service` 等）の起動に伴いコンテナも自動的に再起動する。
復旧後は 4.1 の手順で `tmux` セッションにアタッチすれば、認証情報・作業内容が保持されたまま
作業を再開できる。

### 6.1 コンテナの破棄・イメージの再ビルド

`Dockerfile` の変更を反映したい場合や、Claude Code を入れ直したい場合は以下を実行する。

```bash
./scripts/rebuild.sh            # 複数プロジェクト運用時は ./scripts/rebuild.sh <プロジェクト名>
```

コンテナを破棄（`compose down`）し、イメージをキャッシュ無しで再ビルドしてから `up.sh` で起動し直す。
ボリューム（認証情報・ワークスペース・dotfiles・podman-storage）は削除しないため、再ログインや再 clone は不要。

コンテナのログは標準出力または永続化されたログファイルで確認できる。

```bash
podman compose -f compose.yml logs -f
# podman compose が無い場合
podman-compose -f compose.yml logs -f
```

## 7. トラブルシューティング

| 症状 | 原因の例 | 対処方法 |
| --- | --- | --- |
| セットアップが環境チェックで止まる | コンテナエンジン未インストール、`git` 未インストール、ネットワーク不通 等 | `./scripts/check-env.sh` の出力に従い、指示されたコマンドで不足しているソフトウェアを導入する |
| `claude` コマンドで再ログインを求められる | 認証情報用ボリュームがマウントされていない、別ボリュームでコンテナを再作成した | ボリューム設定を確認し、認証情報ディレクトリ（`~/.claude` 等）が永続化されているか確認する |
| `git push` が失敗する | 認証情報（PAT/SSH 鍵）の期限切れ、ブランチの競合、ネットワーク断 | エラー内容を確認し、認証情報を更新するかコンフリクトを解消したうえで再度指示を送る |
| Podman でボリュームの権限エラーが出る | SELinux ラベルが付与されていない | `compose.yml` を使わずに `podman run` 等で直接起動していないか確認し、`./scripts/up.sh` 経由で起動する |
| コンテナ内の `podman` が `fuse: device not found` 等で失敗する | ホストに `/dev/fuse` が無い、または古い定義で起動したコンテナを使っている | ホストで `sudo modprobe fuse` を実行し、`./scripts/up.sh` でコンテナを作り直す |
| `./scripts/up.sh` でコンテナが起動せず、SELinux の型 `container_engine_t` に関するエラーが出る | ホストの SELinux ポリシー（container-selinux）が古く、`container_engine_t` が無い | `sudo dnf update container-selinux` で更新する。更新できない場合は `compose.yml` の `label=type:container_engine_t` を `label=disable` に置き換える（SELinux による閉じ込めが外れる） |
| コンテナ内の `podman` が `Permission denied` で失敗し、ホストの `sudo ausearch -m avc -ts recent` に拒否記録がある | SELinux のポリシーで許されていない操作がある | 拒否記録の内容を確認する。切り分けとして一時的に `label=disable` で起動して動くか確かめる |
| コンテナ内の `podman run` が `mount proc` 等で `Operation not permitted` になる | 入れ子のコンテナで proc をマウントできない | 外側コンテナの `/proc` を入れ子に渡す回避策（`containers.conf` の `volumes = ["/proc:/proc"]`）は、入れ子から外側の認証情報が見えるため既定では使っていない。設計書 3.2 節を参照 |
| コンテナ内の `podman pull` が `insufficient UIDs or GIDs` で失敗する | イメージ内に 65535 を超える uid が持ち主のファイルがある | 外側コンテナで使える uid は 0〜65535 のため、そのイメージは使えない。別のイメージを使う |
| コンテナ内の `podman pull ubuntu` が short-name エラーになる | 短い名前の解決先を設定していない | `docker.io/library/ubuntu` のように完全な名前で指定する |
| ホスト再起動後にコンテナが起動しない | 自動起動が設定されていない | `./scripts/up.sh` を手動実行する |
| `claude` の自動アップデートが行われない | `~/.claude/settings.json` に `DISABLE_AUTOUPDATER=1` が設定されている | 現在のイメージは Claude Code を `dev` ユーザーの npm グローバル領域（`~/.npm-global`）へ sudo 無しでインストールしているため自動アップデート可能。旧デフォルト設定由来の `DISABLE_AUTOUPDATER=1` は新イメージの初回起動時に `entrypoint.sh` が一度だけ自動削除する。それ以降に残っている場合は手動で `env.DISABLE_AUTOUPDATER` を削除する。なお自動アップデートした CLI はイメージ層に入るため、コンテナ再作成時はイメージのバージョンに戻る（起動後に再度自動アップデートされる） |

## 8. よくある質問（FAQ）

**Q. Docker で使えますか。**
A. 使えません。Podman（rootless）専用です。

**Q. コンテナ内で複数のリポジトリを切り替えて使えますか。**
A. 想定していません。1コンテナ＝1リポジトリが前提です。別リポジトリを扱いたい場合は、
5章の手順でプロジェクトごとにコンテナを追加してください。

**Q. 承認なしの自動実行が不安です。確認しながら進める方法はありますか。**
A. 自動承認モードから対話モード（逐一確認）へ切り替えて利用できます。破壊的操作
（force push 等）はデフォルトでは自動実行されません。

**Q. API キーでの認証はできますか。**
A. `ANTHROPIC_API_KEY` を環境変数として設定することで、OAuth ログインなしに認証できます。
OAuth 認証と併用・切り替えも可能です。

## 9. 対象外の利用方法

以下は本コンテナの想定範囲外であり、本書でもサポートしない（詳細は要件定義書 2章・3.2）。

- CI/CD パイプラインからの非対話バッチ実行
- ローカル PC 上での VSCode Dev Containers 連携
- 複数利用者間での権限分離・監査ログを前提とした運用

# claude-code-container: Claude Code CLI を実行するためのコンテナイメージ
# 対応要件: 4.1, 4.2, 4.6, 5.1（docs/design.md 3章）

FROM debian:bookworm-slim

ARG CLAUDE_CODE_VERSION=latest
ARG CONTAINER_UID=1000
ARG CONTAINER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/dev \
    WORKSPACE=/workspace

# 同梱ツール: git, gh, python3/pip, tmux, curl, ca-certificates, jq（フックスクリプトのJSON解析用）
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        git \
        tmux \
        python3 \
        python3-pip \
        python3-venv \
        jq \
        openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI 本体（CLAUDE_CODE_VERSION でバージョン固定 or 最新版取得を選択可能）
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force

# 非rootの実行ユーザー（ホストとUID/GIDを合わせられるようARGで調整可）
RUN groupadd -g "${CONTAINER_GID}" dev \
    && useradd -m -u "${CONTAINER_UID}" -g "${CONTAINER_GID}" -s /bin/bash dev \
    && mkdir -p "${WORKSPACE}" /home/dev/.claude /home/dev/.dotfiles \
    && chown -R dev:dev "${WORKSPACE}" /home/dev

# 初回起動時に ~/.claude/settings.json へ複製するデフォルトフック設定
COPY --chown=dev:dev config/claude-settings.default.json /opt/claude-container/claude-settings.default.json

COPY --chown=dev:dev scripts/ /home/dev/scripts/
RUN chmod +x /home/dev/scripts/*.sh

# 自動承認モード（4.10）: 素の `claude` を --dangerously-skip-permissions 付きで実行するラッパー
COPY config/bashrc-claude.sh /etc/profile.d/claude-container.sh
RUN cat /etc/profile.d/claude-container.sh >> /home/dev/.bashrc \
    && chown dev:dev /home/dev/.bashrc

WORKDIR /workspace

# entrypoint.sh はコンテナ起動直後は root で実行し、ボリュームの所有者調整（chown）を行った後、
# dev ユーザーへ権限を落として（su）以降の全処理（tmux・claude 等）を非root実行する（5.1）。
ENTRYPOINT ["/home/dev/scripts/entrypoint.sh"]

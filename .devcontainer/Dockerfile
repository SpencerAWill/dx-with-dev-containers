FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG TZ
ENV TZ="$TZ"

# Install additional tools not included in the base image
RUN apt-get update && apt-get install -y --no-install-recommends \
  fzf \
  jq \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# cloudflared — exposes local ports (web-api) over a public https URL so Expo Go on a phone can reach them
RUN ARCH=$(dpkg --print-architecture) \
  && curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb" -o /tmp/cloudflared.deb \
  && apt-get update && apt-get install -y --no-install-recommends /tmp/cloudflared.deb \
  && rm /tmp/cloudflared.deb \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Persist bash history.
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R vscode /commandhistory \
  && echo "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
     >> /home/vscode/.bashrc

# Create workspace directory
RUN mkdir -p /workspace && chown -R vscode:vscode /workspace

WORKDIR /workspace

# Set up non-root user
USER vscode

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash && \
  mkdir -p /home/vscode/.claude

# Pre-create the mount point for the host's gh config. Docker invents missing
# intermediate directories for a bind mount as root, which would leave
# ~/.config root-owned and break any later tool that wants a directory under
# it. Created here as vscode instead. The bind itself supplies the contents.
RUN mkdir -p /home/vscode/.config/gh

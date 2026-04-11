# Base Image for Ubuntu
ARG SYSTEM_VERSION=noble
FROM ubuntu:${SYSTEM_VERSION}

ARG OPENJDK_VERSION
ARG USE_CN_MIRROR=false

RUN if [ "$USE_CN_MIRROR" = "true" ]; then \
        apt-get update && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends --no-install-suggests \
        curl \
        ca-certificates \
        bash && \
        rm -rf /var/lib/apt/lists/* && \
        curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
            --source mirrors.aliyun.com \
            --protocol https \
            --use-intranet-source false \
            --backup false \
            --upgrade-software false \
            --clean-cache false \
            --lang en \
            --pure-mode; \
    fi

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends --no-install-suggests \
    dbus-x11 \
    supervisor \
    tigervnc-standalone-server tigervnc-common tigervnc-tools \
    x11-xserver-utils \
    xfonts-base \
    novnc \
    wget \
    unzip \
    locales \
    sudo \
    pv \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8

# Setup a non-root user
ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN GROUP_NAME="$(awk -F: -v gid="$USER_GID" '$3 == gid { print $1; exit }' /etc/group)" && \
    if [ -z "$GROUP_NAME" ]; then \
        groupadd --gid "$USER_GID" "$USERNAME"; \
        GROUP_NAME="$USERNAME"; \
    fi && \
    if ! id -u "$USERNAME" >/dev/null 2>&1; then \
        useradd --uid "$USER_UID" --gid "$GROUP_NAME" -m -s /bin/bash "$USERNAME"; \
    fi && \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" && \
    chmod 0440 "/etc/sudoers.d/$USERNAME"

USER $USERNAME
WORKDIR /home/$USERNAME

# Copy Scripts
COPY --chown=${USER_UID}:${USER_GID} base-scripts ./bin
RUN chmod +x ./bin/*.sh

RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/${USERNAME}/.desktop-in-docker/.bash_history" \
    && echo "$SNIPPET" >> ~/.bashrc

# supervisor sock 是保存到run 目录中的
RUN mkdir -p log/supervisor run

# Copy supervisor configuration
COPY --chown=${USER_UID}:${USER_GID} supervisord.conf ./supervisor/supervisord.conf

# 主要用于supervisor
ENV SUPERVISOR_USER=$USERNAME

# Expose Ports:
# 6080: noVNC Web Interface
# 5901: VNC Server (for display :1)
EXPOSE 6080 5901

# Command to run supervisor
# ENTRYPOINT ["sh", "-c", "tail -f /dev/null"]
ENTRYPOINT ["sh", "-c", "$HOME/bin/entrypoint.sh"]

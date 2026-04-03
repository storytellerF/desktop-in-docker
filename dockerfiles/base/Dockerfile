# Base Image
FROM debian:trixie

ARG OPENJDK_VERSION
ARG USE_CN_MIRROR=false

COPY build-scripts/switch-mirror.sh /usr/local/bin/switch-mirror.sh
RUN chmod +x /usr/local/bin/switch-mirror.sh && \
    USE_CN_MIRROR="$USE_CN_MIRROR" /usr/local/bin/switch-mirror.sh

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

RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Setup a non-root user
ARG USERNAME=debian
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

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

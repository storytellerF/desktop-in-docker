# Base Image for Arch Linux
# Arch Linux uses a rolling release model
ARG SYSTEM_VERSION=latest
FROM archlinux:${SYSTEM_VERSION}

ARG OPENJDK_VERSION

# Initialize pacman keyring first (required in Docker), then install dependencies
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    dbus \
    tigervnc \
    xorg-xrdb \
    xorg-server \
    xorg-xhost \
    xorg-xinit \
    xterm \
    xorg-server-xvfb \
    python \
    python-pip \
    wget \
    unzip \
    sudo \
    pv \
    bash \
    supervisor \
    && pacman -Scc --noconfirm

# Install websockify via pip to an isolated directory to avoid
# conflicting with pacman-managed python packages (requests, urllib3, etc.)
RUN pip install --target=/opt/pip-packages websockify && \
    echo '#!/bin/sh' > /usr/bin/websockify && \
    echo 'PYTHONPATH=/opt/pip-packages exec python -m websockify "$@"' >> /usr/bin/websockify && \
    chmod +x /usr/bin/websockify

# Download and install noVNC
RUN wget -q https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz -O /tmp/novnc.tar.gz && \
    tar -xzf /tmp/novnc.tar.gz -C /opt && \
    mv /opt/noVNC-1.5.0 /opt/novnc && \
    rm /tmp/novnc.tar.gz

# Create symlink so supervisord.conf path (/usr/share/novnc) works correctly
RUN mkdir -p /usr/share && \
    ln -s /opt/novnc /usr/share/novnc

# Arch's vncserver only accepts a single ":display" arg; all options go into
# ~/.config/tigervnc/config. Install a wrapper at /usr/local/bin/vncserver
# (takes PATH priority over /usr/sbin/vncserver) that translates the
# Debian-style CLI flags used by start-vnc.sh into the config file format.
COPY arch-scripts/vncserver /usr/local/bin/vncserver
RUN chmod +x /usr/local/bin/vncserver

# Setup locale
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Setup a non-root user
ARG USERNAME=arch
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
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

ENTRYPOINT ["sh", "-c", "$HOME/bin/entrypoint.sh"]

# Base Image for Arch Linux
# Arch Linux uses a rolling release model; version tag is typically "latest" or a date snapshot
ARG SYSTEM_VERSION=latest
FROM archlinux:${SYSTEM_VERSION}

ARG OPENJDK_VERSION

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
# Enable multilib and update mirrors first
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    dbus \
    python-supervisor \
    tigervnc \
    xorg-xrdb \
    xorg-server \
    xorg-xhost \
    xorg-xinit \
    xterm \
    xorg-server-xvfb \
    python-websockify \
    novnc \
    wget \
    unzip \
    sudo \
    pv \
    bash \
    && pacman -Scc --noconfirm

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

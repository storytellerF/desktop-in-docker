# Base Image for Alpine Linux
ARG SYSTEM_VERSION=latest
FROM alpine:${SYSTEM_VERSION}

ARG OPENJDK_VERSION

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
# Alpine uses apk and has bash/shadow for user management
RUN apk add --no-cache \
    dbus \
    supervisor \
    tigervnc \
    xrdb \
    xterm \
    xvfb \
    py3-websockify \
    novnc \
    wget \
    unzip \
    sudo \
    pv \
    bash \
    shadow \
    coreutils \
    findutils \
    procps

# Setup locale (Alpine uses musl, limited locale support)
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Setup a non-root user
ARG USERNAME=alpine
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN addgroup -g $USER_GID $USERNAME \
    && adduser -u $USER_UID -G $USERNAME -s /bin/bash -D $USERNAME \
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

# Base Image
ARG SYSTEM_VERSION=trixie
ARG BASE_FROM_IMAGE=debian:${SYSTEM_VERSION}
FROM ${BASE_FROM_IMAGE}

ARG SYSTEM_VERSION
ARG OPENJDK_VERSION
ARG TIMEZONE=UTC

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends --no-install-suggests \
    supervisor \
    tigervnc-standalone-server tigervnc-common tigervnc-tools \
    novnc \
    wget \
    unzip \
    locales \
    sudo \
    pv \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y fonts-noto \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && echo $TIMEZONE > /etc/timezone

# Setup a non-root user
ARG USERNAME=debian
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

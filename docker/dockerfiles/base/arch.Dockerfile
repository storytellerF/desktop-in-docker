# Base Image for Arch Linux
# Arch Linux uses a rolling release model
ARG SYSTEM_VERSION=latest
ARG BASE_FROM_IMAGE=archlinux:${SYSTEM_VERSION}
FROM ${BASE_FROM_IMAGE}

ARG TIMEZONE=UTC

# __INJECT_BEFORE_DEPS__
# Initialize pacman keyring first (required in Docker), then install dependencies
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    tigervnc \
    python \
    python-pip \
    firefox \
    wget \
    unzip \
    noto-fonts \
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

# Setup locale
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && echo $TIMEZONE > /etc/timezone

# Setup a non-root user
ARG USERNAME=arch
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

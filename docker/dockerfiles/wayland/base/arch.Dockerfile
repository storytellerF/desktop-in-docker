# Base Image for Arch Linux Wayland
ARG SYSTEM_VERSION=latest
ARG BASE_FROM_IMAGE=archlinux:${SYSTEM_VERSION}
FROM ${BASE_FROM_IMAGE}

ARG TIMEZONE=UTC

# __INJECT_BEFORE_DEPS__
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    bash \
    dbus \
    firefox \
    freerdp \
    mesa \
    noto-fonts \
    openssl \
    pv \
    sudo \
    supervisor \
    unzip \
    wget \
    weston \
    xdg-utils \
    xorg-xwayland \
    && pacman -Scc --noconfirm

RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

RUN ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && echo $TIMEZONE > /etc/timezone

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

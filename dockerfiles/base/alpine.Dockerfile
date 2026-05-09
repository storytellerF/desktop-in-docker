# Base Image for Alpine Linux
ARG SYSTEM_VERSION=latest
ARG BASE_FROM_IMAGE=alpine:${SYSTEM_VERSION}
FROM ${BASE_FROM_IMAGE}

ARG SYSTEM_VERSION
ARG OPENJDK_VERSION
ARG TIMEZONE=UTC

# Set timezone for Alpine
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/$TIMEZONE /etc/localtime && \
    echo $TIMEZONE > /etc/timezone && \
    apk del tzdata

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
# Alpine uses apk and has bash/shadow for user management
RUN apk add --no-cache \
    supervisor \
    tigervnc \
    websockify \
    novnc \
    wget \
    unzip \
    sudo \
    pv \
    bash \
    shadow \
    coreutils \
    findutils

# Setup locale (Alpine uses musl, limited locale support)
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Setup a non-root user
ARG USERNAME=alpine
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN GROUP_NAME="$(awk -F: -v gid="$USER_GID" '$3 == gid { print $1; exit }' /etc/group)" && \
    if [ -z "$GROUP_NAME" ]; then \
        addgroup -g "$USER_GID" "$USERNAME"; \
        GROUP_NAME="$USERNAME"; \
    fi && \
    if ! id -u "$USERNAME" >/dev/null 2>&1; then \
        adduser -u "$USER_UID" -G "$GROUP_NAME" -s /bin/bash -D "$USERNAME"; \
    fi && \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" && \
    chmod 0440 "/etc/sudoers.d/$USERNAME"

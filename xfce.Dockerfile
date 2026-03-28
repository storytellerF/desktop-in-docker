# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker-base:latest
FROM ${BASE_IMAGE}

USER root
# Prevent installation of power-related packages via APT pinning
RUN printf 'Package: %s\nPin: release *\nPin-Priority: -1\n\n' \
    upower \
    power-profiles-daemon \
    xfce4-power-manager \
    > /etc/apt/preferences.d/no-power-management

# Install XFCE-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    xfce4 \
    && rm -rf /var/lib/apt/lists/*

USER debian
# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "startxfce4" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup


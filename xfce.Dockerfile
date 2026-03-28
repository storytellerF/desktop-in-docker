# Use the locally built base image
ARG BASE_IMAGE=desktop-base:latest
FROM ${BASE_IMAGE}

USER root
# Install XFCE-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal \
    && rm -rf /var/lib/apt/lists/*

USER debian
# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "startxfce4" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup


# Use the locally built base image
ARG BASE_IMAGE=desktop-base:latest
FROM ${BASE_IMAGE}

USER root
# Install LXQt-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    lxqt-core lxterminal openbox \
    && rm -rf /var/lib/apt/lists/*

USER debian
WORKDIR /home/debian

# Setup the startup script for the VNC server to launch the desktop
# Using dbus-run-session is the modern way to ensure a fresh session bus
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

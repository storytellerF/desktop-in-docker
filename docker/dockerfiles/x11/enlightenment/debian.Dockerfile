# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Install Enlightenment-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    enlightenment \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=debian
# This account already has passwordless sudo; permit its desktop helper too.
RUN if [ -f /etc/enlightenment/system.conf ]; then \
    { printf 'user: %s allow: *\n' "$USERNAME"; cat /etc/enlightenment/system.conf; } > /tmp/enlightenment-system.conf && \
    mv /tmp/enlightenment-system.conf /etc/enlightenment/system.conf; fi

USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "if grep -qx 'ID=ubuntu' /etc/os-release && [ -d /proc/acpi ] && [ ! -S /var/run/acpid.socket ]; then sudo acpid; fi" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session enlightenment_start" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Install MATE-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    mate-desktop-environment \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu MATE's default panel layout references an extra indicator applet.
RUN . /etc/os-release && if [ "$ID" = ubuntu ]; then \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    mate-indicator-applet dconf-cli ayatana-indicator-application ayatana-indicator-datetime && \
    rm -rf /var/lib/apt/lists/*; fi

ARG USERNAME=debian
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "if grep -qx 'ID=ubuntu' /etc/os-release; then dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { sudo mkdir -p /run/dbus; sudo dbus-daemon --system --fork --nopidfile; }; fi" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session mate-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

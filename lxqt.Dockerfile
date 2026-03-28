# Use the locally built base image
ARG BASE_IMAGE=desktop-base:latest
FROM ${BASE_IMAGE}

USER root
# Install LXQt-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    lxqt-core lxterminal openbox \
    adwaita-icon-theme-full lxqt-qtplugin \
    && rm -rf /var/lib/apt/lists/*

USER debian
# Setup the startup script for the VNC server to launch the desktop
# We need to ensure dbus and proper environment variables are set for LXQt components
RUN mkdir -p .config/tigervnc && \
    printf "#!/bin/bash\n\
[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"\n\
export XDG_CURRENT_DESKTOP=LXQt\n\
export XDG_SESSION_TYPE=x11\n\
export XDG_RUNTIME_DIR=/tmp/runtime-debian\n\
mkdir -p \$XDG_RUNTIME_DIR && chmod 700 \$XDG_RUNTIME_DIR\n\
dbus-launch --exit-with-session startlxqt\n" > .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

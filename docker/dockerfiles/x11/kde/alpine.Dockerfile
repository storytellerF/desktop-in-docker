# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install KDE Plasma on Alpine Linux
RUN apk add --no-cache \
    plasma-desktop \
    plasma-workspace \
    plasma-workspace-x11 \
    plasma-workspace-wallpapers \
    breeze-icons \
    kglobalacceld \
    kquickcharts \
    kpipewire \
    kwin \
    konsole \
    dolphin \
    mesa-dri-gallium \
    dbus-x11 \
    dbus \
    xrdb \
    xdg-utils

# Breeze supplies Plasma's default Next wallpaper; notifications import plasma-pa.
RUN apk add --no-cache breeze plasma-pa
# These applications are pinned by Plasma's default task manager.
RUN apk add --no-cache systemsettings discover

RUN command -v startplasma-x11 && command -v kwin_x11

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export KWIN_COMPOSE=N" >> .config/tigervnc/xstartup && \
    echo "export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE" >> .config/tigervnc/xstartup && \
    echo "export XDG_RUNTIME_DIR=\"\${XDG_RUNTIME_DIR:-\$HOME/.cache/runtime}\"" >> .config/tigervnc/xstartup && \
    echo "mkdir -p \"\$XDG_RUNTIME_DIR\" && chmod 700 \"\$XDG_RUNTIME_DIR\"" >> .config/tigervnc/xstartup && \
    echo "dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { sudo mkdir -p /run/dbus; sudo dbus-daemon --system --fork --nopidfile; }" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startplasma-x11" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

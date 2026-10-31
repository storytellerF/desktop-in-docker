# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root
# Install GNOME-specific packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    gnome \
    && rm -rf /var/lib/apt/lists/*

# An empty package-created seats directory falsely advertises a running logind.
RUN if [ -d /run/systemd/seats ]; then rmdir /run/systemd/seats; fi

# Power control requires logind and must not be a required VNC session component.
RUN sed 's/org\.gnome\.SettingsDaemon\.Power;//g' \
    /usr/share/gnome-session/sessions/gnome.session > /usr/share/gnome-session/sessions/gnome-vnc.session

ARG USERNAME=debian
USER $USERNAME
WORKDIR /home/$USERNAME

# Setup the startup script for the VNC server to launch the desktop
# Using dbus-run-session for the GNOME session
RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export DISPLAY=:1" >> .config/tigervnc/xstartup && \
    echo "dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { sudo mkdir -p /run/dbus; sudo dbus-daemon --system --fork --nopidfile; }" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session gnome-session --session=gnome-vnc" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

RUN mkdir -p .config/autostart
COPY --chown=${USERNAME} docker/config/autostart/disabled.desktop .config/autostart/org.gnome.SettingsDaemon.Power.desktop

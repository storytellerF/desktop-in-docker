# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install GNOME on Alpine Linux
RUN apk add --no-cache \
    gnome \
    gnome-terminal \
    nautilus \
    mesa-dri-gallium \
    dbus-x11 \
    dbus \
    xrdb \
    xdg-utils

# An empty package-created seats directory falsely advertises a running logind.
RUN if [ -d /run/systemd/seats ]; then rmdir /run/systemd/seats; fi

# Power control requires logind and must not be a required VNC session component.
RUN sed 's/org\.gnome\.SettingsDaemon\.Power;//g' \
    /usr/share/gnome-session/sessions/gnome.session > /usr/share/gnome-session/sessions/gnome-vnc.session

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export DISPLAY=:1" >> .config/tigervnc/xstartup && \
    echo "export XDG_SESSION_TYPE=x11 XDG_SESSION_DESKTOP=gnome DESKTOP_SESSION=gnome-vnc XDG_CURRENT_DESKTOP=GNOME" >> .config/tigervnc/xstartup && \
    echo "export XDG_RUNTIME_DIR=\"\${XDG_RUNTIME_DIR:-\$HOME/.cache/runtime}\"" >> .config/tigervnc/xstartup && \
    echo "mkdir -p \"\$XDG_RUNTIME_DIR\" && chmod 700 \"\$XDG_RUNTIME_DIR\"" >> .config/tigervnc/xstartup && \
    echo "dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { sudo mkdir -p /run/dbus; sudo dbus-daemon --system --fork --nopidfile; }" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session gnome-session --session=gnome-vnc" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

RUN mkdir -p .config/autostart
COPY --chown=${USERNAME} docker/config/autostart/disabled.desktop .config/autostart/org.gnome.SettingsDaemon.Power.desktop

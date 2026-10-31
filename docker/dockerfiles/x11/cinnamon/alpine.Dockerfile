# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Cinnamon and its libraries are in edge/testing, not edge/community.
# Derive the testing mirror from this edge base, preserving CN mirror selection.
RUN grep -q '/edge/main' /etc/apk/repositories && \
    testing_repo="$(sed -n 's|/edge/community.*|/edge/testing|p' /etc/apk/repositories)" && \
    test -n "$testing_repo" && printf '@testing %s\n' "$testing_repo" >> /etc/apk/repositories && \
    apk add --no-cache \
    cinnamon@testing \
    cinnamon-session@testing \
    cinnamon-settings-daemon@testing \
    cinnamon-control-center@testing \
    py3-xapp@testing \
    py3-cairo \
    gsettings-desktop-schemas \
    polkit \
    networkmanager \
    accountsservice \
    ibus \
    nemo \
    adwaita-icon-theme \
    mesa-dri-gallium \
    dbus-x11 \
    dbus \
    xrdb \
    xdg-utils

# AccountsService's typelib does not pull in its separately packaged library.
RUN apk add --no-cache libaccountsservice

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export XDG_SESSION_TYPE=x11 XDG_SESSION_DESKTOP=cinnamon DESKTOP_SESSION=cinnamon XDG_CURRENT_DESKTOP=X-Cinnamon" >> .config/tigervnc/xstartup && \
    echo "export XDG_RUNTIME_DIR=\"\${XDG_RUNTIME_DIR:-\$HOME/.cache/runtime}\"" >> .config/tigervnc/xstartup && \
    echo "mkdir -p \"\$XDG_RUNTIME_DIR\" && chmod 700 \"\$XDG_RUNTIME_DIR\"" >> .config/tigervnc/xstartup && \
    echo "dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { sudo mkdir -p /run/dbus; sudo dbus-daemon --system --fork --nopidfile; }" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session cinnamon-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

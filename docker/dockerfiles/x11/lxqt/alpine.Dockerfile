# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXQt on Alpine Linux
COPY docker/build/screensaver-packages.py /tmp/screensaver-packages.py
RUN python3 /tmp/screensaver-packages.py \
    lxqt-desktop \
    openbox \
    dbus-x11 \
    dbus \
    xrdb \
    xdg-utils \
    xdg-user-dirs

# The LXQt metapackage does not supply a usable desktop icon theme.
RUN apk add --no-cache papirus-icon-theme

ARG USERNAME=alpine
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/sh" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# Select a window manager without a first-login chooser in the remote session.
RUN mkdir -p .config/lxqt
COPY --chown=${USERNAME} docker/config/lxqt/session.conf .config/lxqt/session.conf
COPY --chown=${USERNAME} docker/config/lxqt/lxqt.conf .config/lxqt/lxqt.conf

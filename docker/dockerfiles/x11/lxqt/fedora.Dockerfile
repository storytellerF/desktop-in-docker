# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXQt on Fedora
RUN dnf install -y \
    @lxqt-desktop-environment \
    openbox \
    dbus-x11 \
    xdg-utils \
    && dnf clean all

ARG USERNAME=user
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxqt" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# Select a window manager without a first-login chooser in the remote session.
RUN mkdir -p .config/lxqt
COPY --chown=${USERNAME} docker/config/lxqt/session.conf .config/lxqt/session.conf

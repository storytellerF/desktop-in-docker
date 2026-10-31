# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install Cinnamon on Fedora
RUN dnf install -y \
    cinnamon \
    dbus-x11 \
    xdg-utils \
    nemo \
    && dnf clean all

ARG USERNAME=user
USER $USERNAME
WORKDIR /home/$USERNAME

# Cinnamon's IMSettings starts Fcitx on its session bus after X11 is ready.
RUN rm -f supervisor/conf.d/fcitx.supervisord.conf

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "export XDG_SESSION_TYPE=x11 XDG_SESSION_DESKTOP=cinnamon DESKTOP_SESSION=cinnamon XDG_CURRENT_DESKTOP=X-Cinnamon" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session cinnamon-session" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

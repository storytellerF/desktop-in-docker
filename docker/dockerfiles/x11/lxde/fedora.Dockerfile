# Use the locally built base image
ARG BASE_IMAGE=desktop-in-docker:debian-trixie-base-latest
FROM ${BASE_IMAGE}

USER root

# Install LXDE on Fedora
RUN dnf install -y \
    @lxde-desktop-environment \
    dbus-x11 \
    xdg-utils \
    && dnf clean all

ARG USERNAME=user
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p .config/tigervnc && \
    echo "#!/bin/bash" > .config/tigervnc/xstartup && \
    echo "[ -f \"\$HOME/.Xresources\" ] && xrdb \"\$HOME/.Xresources\"" >> .config/tigervnc/xstartup && \
    echo "exec dbus-run-session startlxde" >> .config/tigervnc/xstartup && \
    chmod +x .config/tigervnc/xstartup

# There is no logind session for lxpolkit or a screen locker in this container.
RUN mkdir -p .config/autostart .config/lxsession/LXDE
COPY --chown=${USERNAME} docker/config/autostart/disabled.desktop .config/autostart/lxpolkit.desktop
COPY --chown=${USERNAME} docker/config/autostart/disabled.desktop .config/autostart/light-locker.desktop
COPY --chown=${USERNAME} docker/config/lxde/autostart .config/lxsession/LXDE/autostart

# LXSession starts its policy agent independently from XDG autostart entries.
RUN sed -e '/^polkit\/command=/d' -e '/^\[Session\]/a polkit/command=none' \
    /etc/xdg/lxsession/LXDE/desktop.conf > .config/lxsession/LXDE/desktop.conf

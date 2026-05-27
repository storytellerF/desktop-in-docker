ARG BASE_IMAGE=desktop-in-docker:wayland-arch-latest-base-latest
FROM ${BASE_IMAGE}

USER root

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    foot \
    && pacman -Scc --noconfirm

ARG USERNAME=arch
ARG USER_UID=1000
ARG USER_GID=$USER_UID

USER $USERNAME
WORKDIR /home/$USERNAME

COPY --chown=${USER_UID}:${USER_GID} base-scripts ./bin
RUN chmod +x ./bin/*.sh

RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/${USERNAME}/.desktop-in-docker/.bash_history" \
    && echo "$SNIPPET" >> ~/.bashrc

RUN mkdir -p log/supervisor run .config/weston

COPY --chown=${USER_UID}:${USER_GID} docker/config/supervisor/wayland.supervisord.conf ./supervisor/supervisord.conf
COPY --chown=${USER_UID}:${USER_GID} docker/config/wayland/weston.ini ./.config/weston/weston.ini

ENV SUPERVISOR_USER=$USERNAME
ENV RDP_PORT=3389

EXPOSE 3389

CMD ["sh", "-c", "$HOME/bin/entrypoint.sh"]

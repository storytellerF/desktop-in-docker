ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:fedora-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

RUN dnf install -y \
        supervisor \
        fcitx \
        fcitx-pinyin && \
    dnf clean all

COPY base-scripts/start-fcitx.sh /usr/local/bin/start-fcitx.sh
COPY docker/config/supervisor/webtop.supervisord.conf /opt/desktop-in-docker/supervisord.conf
COPY docker/config/webtop/custom-services.d/desktop-in-docker-supervisor /custom-services.d/desktop-in-docker-supervisor

RUN chmod +x /usr/local/bin/start-fcitx.sh /custom-services.d/desktop-in-docker-supervisor && \
    mkdir -p /config/.config/fcitx /config/log/supervisor /config/run && \
    if id abc >/dev/null 2>&1; then chown -R abc:abc /config/.config/fcitx /config/log /config/run; fi

COPY fcitx/config /config/.config/fcitx/config
COPY fcitx/profile /config/.config/fcitx/profile

RUN if id abc >/dev/null 2>&1; then chown -R abc:abc /config/.config/fcitx; fi

ARG WEBTOP_IMAGE=lscr.io/linuxserver/webtop:fedora-xfce
FROM ${WEBTOP_IMAGE}

USER root

RUN dnf install -y curl ca-certificates bash && \
    dnf clean all

RUN curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
    --source mirrors.aliyun.com \
    --protocol https \
    --use-intranet-source false \
    --backup false \
    --upgrade-software false \
    --clean-cache false \
    --lang en \
    --pure-mode

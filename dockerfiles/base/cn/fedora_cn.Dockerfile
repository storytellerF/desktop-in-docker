ARG SYSTEM_VERSION=41
FROM fedora:${SYSTEM_VERSION}

RUN dnf install -y curl ca-certificates bash && \
    dnf clean all && \
    bash -o pipefail -c 'curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
        --source mirrors.aliyun.com \
        --protocol https \
        --use-intranet-source false \
        --backup false \
        --upgrade-software false \
        --clean-cache false \
        --lang en \
        --pure-mode'

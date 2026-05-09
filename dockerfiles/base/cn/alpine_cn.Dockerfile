ARG SYSTEM_VERSION=latest
FROM alpine:${SYSTEM_VERSION}

RUN apk add --no-cache curl ca-certificates bash && \
    update-ca-certificates || true && \
    bash -o pipefail -c 'curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
        --source mirrors.aliyun.com \
        --protocol https \
        --use-intranet-source false \
        --backup false \
        --upgrade-software false \
        --clean-cache false \
        --lang en \
        --pure-mode'

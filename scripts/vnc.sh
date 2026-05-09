#!/bin/bash

launch_quietly() {
    if command -v setsid &> /dev/null; then
        setsid "$@" >/dev/null 2>&1 </dev/null &
    else
        "$@" >/dev/null 2>&1 </dev/null &
        disown
    fi
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR" || exit 1

COMPOSE_FILE=""
if [ -f ".devcontainer/docker-compose.yml" ]; then
    COMPOSE_FILE=".devcontainer/docker-compose.yml"
elif [ -f "docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
fi

if [ -z "$COMPOSE_FILE" ]; then
    echo "错误：未找到 docker compose 配置文件。"
    exit 1
fi

SERVICE_NAME="desktop"

VNC_PORT_MAPPING=$(docker compose -f "$COMPOSE_FILE" port "$SERVICE_NAME" 5901 2>/dev/null)
if [ -n "$VNC_PORT_MAPPING" ]; then
    VNC_PORT=${VNC_PORT_MAPPING##*:}
else
    CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME" 2>/dev/null | head -n 1)
    if [ -z "$CONTAINER_ID" ]; then
        CONTAINER_ID=$(docker ps --filter "name=${SERVICE_NAME}" --format "{{.ID}}" | head -n 1)
    fi

    if [ -n "$CONTAINER_ID" ]; then
        PORT_LINE=$(docker port "$CONTAINER_ID" 5901/tcp 2>/dev/null | head -n 1)
        if [ -z "$PORT_LINE" ]; then
            PORT_LINE=$(docker port "$CONTAINER_ID" 5901 2>/dev/null | head -n 1)
        fi
        if [ -n "$PORT_LINE" ]; then
            VNC_PORT=${PORT_LINE##*:}
        fi
    fi

    if [ -z "$VNC_PORT" ]; then
        VNC_PORT=$(sed -nE 's/.*-.*"?([0-9]+):5901"?/\1/p' "$COMPOSE_FILE" | head -n 1)
        if [ -z "$VNC_PORT" ] && grep -qE "\"?5901\"?" "$COMPOSE_FILE"; then
            echo "提示：检测到 5901 使用动态端口映射，需要先启动容器才能确定宿主端口。"
        fi
    fi
fi

if [ -z "$VNC_PORT" ]; then
    echo "警告：无法确定 VNC 宿主端口映射（容器 5901）。默认使用 5901。"
    VNC_PORT=5901
fi

echo "检测到 VNC 宿主端口: $VNC_PORT"
ENV_FILE=""
if [ -f ".devcontainer/.env" ]; then
    ENV_FILE=".devcontainer/.env"
elif [ -f ".env" ]; then
    ENV_FILE=".env"
fi

VNC_PASSWD="password"
if [ -n "$ENV_FILE" ]; then
    VNC_PASSWD_FROM_ENV=$(grep -E "^VNC_PASS(WD|WORD)=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")
    if [ -n "$VNC_PASSWD_FROM_ENV" ]; then
        VNC_PASSWD="$VNC_PASSWD_FROM_ENV"
    fi
fi

if [ "$1" = "--show-password" ]; then
    echo "提示：当前 VNC 密码为: $VNC_PASSWD"
fi

PASSWD_FILE="tmp/passwd"
mkdir -p "$(dirname "$PASSWD_FILE")"

if command -v vncpasswd &> /dev/null; then
    echo "$VNC_PASSWD" | vncpasswd -f > "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
else
    echo "$VNC_PASSWD" > "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
    echo "警告：未找到 vncpasswd，密码文件将以明文保存：$PASSWD_FILE"
fi

if command -v remmina &> /dev/null; then
    echo "启动 remmina vnc://localhost:$VNC_PORT ..."
    launch_quietly remmina -c "vnc://localhost:$VNC_PORT"
    exit 0
fi

if ! command -v vncviewer &> /dev/null; then
    echo "错误：未找到 remmina 或 vncviewer。"
    echo "请安装其一，例如：sudo apt install remmina 或 tigervnc-viewer"
    exit 1
fi

echo "启动 vncviewer localhost:$VNC_PORT ..."
if vncviewer -h 2>&1 | grep -q "PasswordFile"; then
    vncviewer "localhost:$VNC_PORT" -PasswordFile="$PASSWD_FILE"
elif vncviewer -h 2>&1 | grep -q "\-passwd"; then
    vncviewer "localhost:$VNC_PORT" -passwd "$PASSWD_FILE"
else
    vncviewer "localhost:$VNC_PORT"
fi

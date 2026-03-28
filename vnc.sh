#!/bin/bash

# 获取当前正在运行的容器暴露到 host 的 VNC 端口（默认映射到内部 5901）
# 优先从 docker compose 获取，兼容常规 docker 容器获取方式

# 1. 尝试使用 docker compose 获取
VNC_INFO=$(docker compose port desktop 5901 2>/dev/null)

if [ -z "$VNC_INFO" ]; then
    # 2. 如果 docker compose 不行，尝试直接在当前目录查找名为 desktop 的容器
    CONTAINER_ID=$(docker ps --filter "name=desktop" --format "{{.ID}}" | head -n 1)
    if [ -n "$CONTAINER_ID" ]; then
        VNC_PORT=$(docker port "$CONTAINER_ID" 5901 | cut -d':' -f2)
    fi
else
    VNC_PORT=$(echo "$VNC_INFO" | cut -d':' -f2)
fi

if [ -z "$VNC_PORT" ]; then
    echo "未找到正在运行的 'desktop' 容器或 5901 端口未映射。"
    echo "请先运行: ./build-image.sh -S 或 docker compose up -d"
    exit 1
fi

echo "发现 VNC 映射端口: $VNC_PORT"

# 读取 .env 文件中的 VNC 密码，以便在运行脚本时给用户提示
if [ -f .env ]; then
    # 使用 grep 而不是 source，避免 shell 不兼容
    PWD_HINT=$(grep "^VNC_PASSWD=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    if [ -n "$PWD_HINT" ]; then
        echo "提示：.env 中的 VNC 密码为: $PWD_HINT"
    fi
fi


# 使用vncpasswd 保存密码到./tmp/passwd
vncpasswd -f > ./tmp/passwd <<EOF
password
EOF

echo "正在尝试连接 vncviewer localhost:$VNC_PORT ..."
vncviewer "localhost:$VNC_PORT" -passwd="./tmp/passwd"

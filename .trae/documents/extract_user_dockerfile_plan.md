# 在 build-image.sh 中合并 Dockerfile 的方案（最终版）

## 目标

在 `build-image.sh` 脚本中实现 Dockerfile 的自动合并，将原有的 Dockerfile 中 `USER` 后面的重复代码删除，只保留系统特定部分，构建时自动合并到项目根目录的 `build` 目录中。

## 方案设计

### 文件结构

```
/home/kx/Projects/desktop-in-docker/
├── build/                          # 构建目录（生成的合并文件）
│   ├── debian.Dockerfile
│   ├── alpine.Dockerfile
│   ├── arch.Dockerfile
│   ├── fedora.Dockerfile
│   └── ubuntu.Dockerfile
├── dockerfiles/base/               # 修改后的 Dockerfile（只保留系统特定部分）
│   ├── Dockerfile                   # debian 系统（删除了 USER 后面的内容）
│   ├── alpine.Dockerfile            # alpine 系统（删除了 USER 后面的内容）
│   ├── arch.Dockerfile              # arch 系统（删除了 USER 后面的内容）
│   ├── fedora.Dockerfile            # fedora 系统（删除了 USER 后面的内容）
│   └── ubuntu.Dockerfile            # ubuntu 系统（删除了 USER 后面的内容）
├── user-config.dockerfrag          # 用户配置（重复部分）
├── build-image.sh                  # 构建脚本
└── .gitignore                      # 自动更新
```

### 步骤 1: 修改原有的 Dockerfile

将每个原有的 Dockerfile 中 `USER $USERNAME` 后面的所有内容删除，只保留系统特定部分。

**修改后的 dockerfiles/base/Dockerfile 示例：**

```dockerfile
# Base Image
FROM debian:trixie

ARG OPENJDK_VERSION
ARG TIMEZONE=UTC

RUN if [ "$TIMEZONE" = "Asia/Shanghai" ] || [ "$TIMEZONE" = "Asia/Chongqing" ] || [ "$TIMEZONE" = "Asia/Harbin" ] || [ "$TIMEZONE" = "Asia/Urumqi" ] || [ "$TIMEZONE" = "PRC" ]; then \
        apt-get update && \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends --no-install-suggests \
        curl \
        ca-certificates \
        bash && \
        rm -rf /var/lib/apt/lists/* && \
        bash -o pipefail -c 'curl -fsSL https://linuxmirrors.cn/main.sh | bash -s -- \
            --source mirrors.aliyun.com \
            --protocol https \
            --use-intranet-source false \
            --backup false \
            --upgrade-software false \
            --clean-cache false \
            --lang en \
            --pure-mode; \
    fi

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && echo $TIMEZONE > /etc/timezone

# Install Dependencies: VNC, Supervisor, noVNC, and other tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends --no-install-suggests \
    dbus-x11 \
    supervisor \
    tigervnc-standalone-server tigervnc-common tigervnc-tools \
    x11-xserver-utils \
    xfonts-base \
    novnc \
    wget \
    unzip \
    locales \
    sudo \
    pv \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Setup a non-root user
ARG USERNAME=debian
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN GROUP_NAME="$(awk -F: -v gid="$USER_GID" '$3 == gid { print $1; exit }' /etc/group)" && \
    if [ -z "$GROUP_NAME" ]; then \
        groupadd --gid "$USER_GID" "$USERNAME"; \
        GROUP_NAME="$USERNAME"; \
    fi && \
    if ! id -u "$USERNAME" >/dev/null 2>&1; then \
        useradd --uid "$USER_UID" --gid "$GROUP_NAME" -m -s /bin/bash "$USERNAME"; \
    fi && \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" && \
    chmod 0440 "/etc/sudoers.d/$USERNAME"

# 到这里结束，删除 USER $USERNAME 后面的所有内容
```

### 步骤 2: 创建用户配置文件

创建 `/home/kx/Projects/desktop-in-docker/user-config.dockerfrag` 包含所有重复的用户配置：

**user-config.dockerfrag：**

```dockerfile
USER $USERNAME
WORKDIR /home/$USERNAME

# Copy Scripts
COPY --chown=${USER_UID}:${USER_GID} base-scripts ./bin
RUN chmod +x ./bin/*.sh

RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/${USERNAME}/.desktop-in-docker/.bash_history" \
    && echo "$SNIPPET" >> ~/.bashrc

# supervisor sock 是保存到run 目录中的
RUN mkdir -p log/supervisor run

# Copy supervisor configuration
COPY --chown=${USER_UID}:${USER_GID} supervisord.conf ./supervisor/supervisord.conf

# 主要用于supervisor
ENV SUPERVISOR_USER=$USERNAME

# Expose Ports:
# 6080: noVNC Web Interface
# 5901: VNC Server (for display :1)
EXPOSE 6080 5901

ENTRYPOINT ["sh", "-c", "$HOME/bin/entrypoint.sh"]
```

### 步骤 3: 创建 build-image.sh 脚本

创建 `/home/kx/Projects/desktop-in-docker/build-image.sh` 脚本来自动合并和构建：

**build-image.sh：**

```bash
#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 基础目录
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$BASE_DIR/build"
DOCKERFILES_DIR="$BASE_DIR/dockerfiles/base"
USER_CONFIG_FILE="$BASE_DIR/user-config.dockerfrag"
GITIGNORE_FILE="$BASE_DIR/.gitignore"

# 镜像名称前缀
IMAGE_PREFIX="desktop-in-docker"

# 系统列表
SYSTEMS=("debian" "alpine" "arch" "fedora" "ubuntu")

# 创建构建目录
mkdir -p "$BUILD_DIR"

# 函数：显示帮助信息
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [SYSTEM]

构建桌面 Docker 镜像 - 自动合并系统特定配置和用户配置

OPTIONS:
    -h, --help          显示帮助信息
    -t, --tag TAG       指定镜像标签 (默认: latest)
    -p, --push          构建后推送到仓库
    -a, --all           构建所有系统
    -c, --clean         清理构建目录
    -u, --update-gitingore 更新 .gitignore 文件
    -v, --verbose       详细输出
    -d, --dry-run       只合并不构建，用于测试

SYSTEM:
    指定要构建的系统，可选值:
    - debian (默认)
    - alpine
    - arch
    - fedora
    - ubuntu

EXAMPLES:
    $0                  # 构建默认的 debian 系统
    $0 -t v1.0.0       # 构建并标记为 v1.0.0
    $0 -a -t latest     # 构建所有系统
    $0 alpine           # 构建 alpine 系统
    $0 -c               # 清理构建文件
    $0 -d               # 只合并不构建
    $0 -u               # 更新 .gitignore 文件

文件结构:
    dockerfiles/base/*.Dockerfile - 系统特定配置（已删除 USER 后面的内容）
    user-config.dockerfrag        - 用户配置（重复部分）
    build/*.Dockerfile            - 合并后的完整 Dockerfile

EOF
}

# 函数：检查文件是否存在
check_files() {
    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        echo -e "${RED}错误: 用户配置文件不存在: $USER_CONFIG_FILE${NC}"
        echo -e "${YELLOW}请创建 user-config.dockerfrag 文件${NC}"
        exit 1
    fi
    
    for system in "${SYSTEMS[@]}"; do
        local dockerfile="$DOCKERFILES_DIR/Dockerfile"
        if [[ "$system" != "debian" ]]; then
            dockerfile="$DOCKERFILES_DIR/${system}.Dockerfile"
        fi
        if [[ ! -f "$dockerfile" ]]; then
            echo -e "${RED}错误: Dockerfile 不存在: $dockerfile${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✓ 所有必需文件检查通过${NC}"
}

# 函数：检查 Dockerfile 是否已修改
verify_dockerfile_modification() {
    local dockerfile="$1"
    local system="$2"
    
    echo -e "${YELLOW}正在检查 $system Dockerfile 的修改状态...${NC}"
    
    # 检查是否包含 USER 命令
    if grep -q "^USER \$USERNAME" "$dockerfile"; then
        echo -e "${RED}✗ $system Dockerfile 仍然包含 USER 命令，需要删除 USER 后面的所有内容${NC}"
        return 1
    fi
    
    # 检查是否以用户创建结束
    if grep -q "chmod 0440 \"/etc/sudoers.d/\$USERNAME\"" "$dockerfile"; then
        echo -e "${GREEN}✓ $system Dockerfile 看起来已经正确修改${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ $system Dockerfile 可能需要检查${NC}"
        return 0
    fi
}

# 函数：更新 .gitignore
update_gitignore() {
    echo -e "${YELLOW}正在更新 .gitignore 文件...${NC}"
    
    # 检查是否已存在 build/ 条目
    if [[ -f "$GITIGNORE_FILE" ]]; then
        if ! grep -q "^build/" "$GITIGNORE_FILE"; then
            echo "build/" >> "$GITIGNORE_FILE"
            echo -e "${GREEN}✓ 已添加 build/ 到 .gitignore${NC}"
        else
            echo -e "${GREEN}✓ build/ 已存在于 .gitignore${NC}"
        fi
    else
        echo "build/" > "$GITIGNORE_FILE"
        echo -e "${GREEN}✓ 已创建 .gitignore 并添加 build/${NC}"
    fi
}

# 函数：合并 Dockerfile
merge_dockerfile() {
    local system="$1"
    local dockerfile="$DOCKERFILES_DIR/Dockerfile"
    local output_file="$BUILD_DIR/${system}.Dockerfile"
    
    # 对于 debian 系统，使用默认的 Dockerfile
    if [[ "$system" != "debian" ]]; then
        dockerfile="$DOCKERFILES_DIR/${system}.Dockerfile"
    fi
    
    echo -e "${YELLOW}正在合并 ${system}.Dockerfile...${NC}"
    
    # 验证原文件是否已修改
    verify_dockerfile_modification "$dockerfile" "$system"
    
    # 清空或创建输出文件
    > "$output_file"
    
    # 写入系统特定配置
    echo "# 系统特定配置 - $(date)" >> "$output_file"
    echo "# 来源: $dockerfile" >> "$output_file"
    cat "$dockerfile" >> "$output_file"
    
    # 添加空行分隔
    echo "" >> "$output_file"
    
    # 写入用户配置
    echo "# 用户配置 - $(date)" >> "$output_file"
    echo "# 来源: $USER_CONFIG_FILE" >> "$output_file"
    cat "$USER_CONFIG_FILE" >> "$output_file"
    
    echo -e "${GREEN}✓ 合并完成: $output_file${NC}"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "文件内容预览:"
        head -20 "$output_file"
        echo "..."
    fi
}

# 函数：构建镜像
build_image() {
    local system="$1"
    local tag="$2"
    local dockerfile="$BUILD_DIR/${system}.Dockerfile"
    local image_name="$IMAGE_PREFIX:$system-$tag"
    
    echo -e "${YELLOW}正在构建镜像: $image_name${NC}"
    
    # 构建镜像
    docker buildx build \
        --file "$dockerfile" \
        --tag "$image_name" \
        --build-arg SYSTEM_VERSION="latest" \
        "$BASE_DIR"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ 镜像构建成功: $image_name${NC}"
        
        # 如果指定了推送
        if [[ "$PUSH" == "true" ]]; then
            echo -e "${YELLOW}正在推送镜像: $image_name${NC}"
            docker push "$image_name"
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ 镜像推送成功: $image_name${NC}"
            else
                echo -e "${RED}✗ 镜像推送失败: $image_name${NC}"
                return 1
            fi
        fi
    else
        echo -e "${RED}✗ 镜像构建失败: $image_name${NC}"
        return 1
    fi
}

# 函数：清理构建目录
clean_build() {
    echo -e "${YELLOW}正在清理构建目录...${NC}"
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        echo -e "${GREEN}✓ 构建目录已清理${NC}"
    else
        echo -e "${GREEN}✓ 构建目录不存在，无需清理${NC}"
    fi
}

# 主函数
main() {
    # 默认参数
    TAG="latest"
    SYSTEM="debian"
    BUILD_ALL=false
    PUSH=false
    CLEAN=false
    UPDATE_GITIGNORE=false
    VERBOSE=false
    DRY_RUN=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -p|--push)
                PUSH=true
                shift
                ;;
            -a|--all)
                BUILD_ALL=true
                shift
                ;;
            -c|--clean)
                CLEAN=true
                shift
                ;;
            -u|--update-gitingore)
                UPDATE_GITIGNORE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                echo -e "${RED}错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
            *)
                SYSTEM="$1"
                shift
                ;;
        esac
    done
    
    # 如果指定了更新 .gitignore
    if [[ "$UPDATE_GITIGNORE" == "true" ]]; then
        update_gitignore
        exit 0
    fi
    
    # 如果指定了清理
    if [[ "$CLEAN" == "true" ]]; then
        clean_build
        exit 0
    fi
    
    # 检查文件
    check_files
    
    # 更新 .gitignore
    update_gitignore
    
    echo -e "${GREEN}开始构建桌面 Docker 镜像...${NC}"
    echo -e "标签: $TAG"
    echo -e "系统: $SYSTEM"
    echo -e "基础目录: $BASE_DIR"
    echo ""
    
    # 构建逻辑
    if [[ "$BUILD_ALL" == "true" ]]; then
        # 构建所有系统
        for system in "${SYSTEMS[@]}"; do
            merge_dockerfile "$system"
            if [[ "$DRY_RUN" != "true" ]]; then
                build_image "$system" "$TAG"
            fi
            echo ""
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${GREEN}干运行模式完成! 已生成合并文件，未构建镜像${NC}"
        else
            echo -e "${GREEN}所有系统构建完成!${NC}"
        fi
    else
        # 构建指定系统
        merge_dockerfile "$SYSTEM"
        if [[ "$DRY_RUN" != "true" ]]; then
            build_image "$SYSTEM" "$TAG"
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${GREEN}干运行模式完成! 已生成合并文件，未构建镜像${NC}"
        else
            echo -e "${GREEN}构建完成!${NC}"
        fi
    fi
    
    # 显示构建结果（如果不是干运行模式）
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo -e "${GREEN}构建结果:${NC}"
        docker images | grep "$IMAGE_PREFIX" || echo "没有找到相关镜像"
    fi
}

# 运行主函数
main "$@"
```

### 步骤 4: 使用方法

```bash
# 1. 给脚本添加执行权限
chmod +x /home/kx/Projects/desktop-in-docker/build-image.sh

# 2. 首先需要手动修改原有的 Dockerfile 文件
# 删除每个 Dockerfile 中 USER $USERNAME 后面的所有内容

# 3. 创建用户配置文件
cp /home/kx/Projects/desktop-in-docker/dockerfiles/base/Dockerfile /tmp/backup/
# 手动编辑文件，只保留 USER 前面的内容

# 4. 构建镜像
./build-image.sh                    # 构建默认的 debian 系统
./build-image.sh alpine              # 构建 alpine 系统
./build-image.sh -a -t v1.0.0        # 构建所有系统并标记

# 5. 干运行模式（只合并不构建）
./build-image.sh -d                  # 测试合并是否正确

# 6. 更新 .gitignore
./build-image.sh -u                  # 只更新 .gitignore 文件

# 7. 清理构建文件
./build-image.sh -c                  # 清理 build 目录
```

## 方案特点

### 1. 彻底重构

* 原有的 Dockerfile 中 USER 后面的内容完全删除

* 只保留系统特定的安装和配置

* 用户配置完全独立到单独文件

### 2. 智能验证

* 自动检查 Dockerfile 是否已正确修改

* 验证是否删除了 USER 后面的内容

* 提供详细的错误提示

### 3. 安全机制

* 干运行模式用于测试合并效果

* 详细的文件检查和验证

* 完整的错误处理和提示

### 4. 自动化管理

* 自动更新 .gitignore 文件

* 自动生成带时间戳的合并文件

* 支持详细的构建日志

### 5. 向后兼容

* 支持原有的构建参数和选项

* 保持相同的镜像命名规范

* 支持标签管理和推送

## 实施步骤

### 第一步：备份原有文件

```bash
cd /home/kx/Projects/desktop-in-docker/dockerfiles/base
cp Dockerfile Dockerfile.backup
cp alpine.Dockerfile alpine.Dockerfile.backup
cp arch.Dockerfile arch.Dockerfile.backup
cp fedora.Dockerfile fedora.Dockerfile.backup
cp ubuntu.Dockerfile ubuntu.Dockerfile.backup
```

### 第二步：修改原有 Dockerfile

手动编辑每个 Dockerfile，删除 `USER $USERNAME` 后面的所有内容，只保留系统特定部分。

### 第三步：创建用户配置文件

创建 `/home/kx/Projects/desktop-in-docker/user-config.dockerfrag`，包含所有重复的用户配置。

### 第四步：测试构建脚本

使用干运行模式测试合并效果：

```bash
./build-image.sh -d
```

### 第五步：验证合并结果

检查生成的合并文件是否正确，然后执行实际构建。

## 验证步骤

1. 检查原有的 Dockerfile 是否正确修改（删除了 USER 后面的内容）
2. 使用干运行模式测试合并效果
3. 检查生成的合并文件是否完整正确
4. 验证构建的镜像功能正常
5. 测试 VNC 和 noVNC 服务
6. 验证用户环境配置
7. 确认 .gitignore 已正确更新


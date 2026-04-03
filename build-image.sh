#!/bin/bash
set -e

IMAGE_NAME="desktop-in-docker"
# IMAGE_TAG="latest"
ENV_FILE=".env"
DEFAULT_VNC_PASSWORD="password"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --system <system>        Specify the Linux distribution (debian, ubuntu, fedora, arch, alpine) (default: debian)"
    echo "  -v, --version <version>      Specify the distribution version (e.g., bookworm, trixie, focal, jammy, noble)"
    echo "  -p, --password <password>    Specify the VNC password (default: $DEFAULT_VNC_PASSWORD)"
    echo "  -c, --create-env             Create or overwrite the .env file with the specified or default values"
    echo "  -b, --build                  Execute the docker build process"
    echo "  -S, --start                  Start docker compose up --build after building the image"
    echo "  -P, --publish                Build and Push multi-arch images to Docker Hub (requires docker login)"
    echo "  -m, --multi-arch             Enable multi-arch mode (builds/pushes for amd64 and arm64)"
    echo "  -d, --desktop <desktop>      Specify the desktop environment (xfce, lxqt, kde, mate, cinnamon, lxde, gnome, enlightenment) (default: xfce)"
    echo "  --latest                     Tag the image as 'latest'"
    echo "  --no-snapshot                Do not tag the image as 'snapshot' (snapshot is tagged by default)"
    echo "  -h, --help                   Display this help message"
    exit 1
}

# Helper to write or update var in file
update_env_var() {
    local key=$1
    local val=$2
    local file=$3
    [ ! -f "$file" ] && touch "$file"
    if grep -q "^${key}=" "$file"; then
        # Use a temporary file to avoid issues with sed -i on some systems, 
        # though sed -i is generally fine on linux.
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
    else
        echo "${key}=\"${val}\"" >> "$file"
    fi
}

# Parse arguments
CREATE_ENV=false
EXECUTE_BUILD=false
START_CONTAINER=false
PUBLISH=false
MULTI_ARCH=false
CMD_DOCKER_USERNAME=""
CMD_VNC_PASSWORD=""
CMD_DESKTOP_ENV=""
CMD_SYSTEM=""
CMD_SYSTEM_VERSION=""
TAG_LATEST=false
TAG_SNAPSHOT=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--system)
            CMD_SYSTEM="$2"
            shift
            ;;
        -v|--version)
            CMD_SYSTEM_VERSION="$2"
            shift
            ;;
        -p|--password)
            CMD_VNC_PASSWORD="$2"
            shift
            ;;
        -c|--create-env)
            CREATE_ENV=true
            ;;
        -b|--build)
            EXECUTE_BUILD=true
            ;;
        -S|--start)
            START_CONTAINER=true
            ;;
        -P|--publish)
            PUBLISH=true
            ;;
        -m|--multi-arch)
            MULTI_ARCH=true
            ;;
        --latest)
            TAG_LATEST=true
            ;;
        --no-snapshot)
            TAG_SNAPSHOT=false
            ;;
        -d|--desktop)
            CMD_DESKTOP_ENV="$2"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
    shift
done

# Get current date with timestamp
CURRENT_DATE=$(date +%Y%m%d%H%M%S)

# Load existing .env if present
if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE..."
    source "$ENV_FILE"
fi

# Re-apply command line arguments (overriding .env)
[ -n "$CMD_DOCKER_USERNAME" ] && DOCKER_USERNAME="$CMD_DOCKER_USERNAME"
[ -n "$CMD_VNC_PASSWORD" ] && VNC_PASSWD="$CMD_VNC_PASSWORD"
[ -n "$CMD_DESKTOP_ENV" ] && DESKTOP_ENV="$CMD_DESKTOP_ENV"
[ -n "$CMD_SYSTEM" ] && SYSTEM="$CMD_SYSTEM"
[ -n "$CMD_SYSTEM_VERSION" ] && SYSTEM_VERSION="$CMD_SYSTEM_VERSION"

# Set defaults
VNC_PASSWD="${VNC_PASSWD:-$DEFAULT_VNC_PASSWORD}"
DESKTOP_ENV="${DESKTOP_ENV:-xfce}"
SYSTEM="${SYSTEM:-debian}"

# Default versions based on system
if [ -z "$SYSTEM_VERSION" ]; then
    case $SYSTEM in
        debian) SYSTEM_VERSION="trixie" ;;
        ubuntu) SYSTEM_VERSION="noble" ;;
        fedora) SYSTEM_VERSION="41" ;;
        arch) SYSTEM_VERSION="latest" ;;
        alpine) SYSTEM_VERSION="latest" ;;
        *) SYSTEM_VERSION="latest" ;;
    esac
fi

# Define tags based on system and version
TAG_BASE_FULL="${SYSTEM}-${SYSTEM_VERSION}-${DESKTOP_ENV}"
TAG_BASE_MIN=""

# Minimized tags (omit defaults)
if [ "$SYSTEM" = "debian" ] && [ "$SYSTEM_VERSION" = "trixie" ]; then
    # Default system/version, tag can be just desktop-env
    if [ "$DESKTOP_ENV" = "xfce" ]; then
        TAG_BASE_MIN=""
    else
        TAG_BASE_MIN="${DESKTOP_ENV}"
    fi
else
    # Non-default system OR non-default version
    TAG_BASE_MIN="${SYSTEM}-${SYSTEM_VERSION}"
    if [ "$DESKTOP_ENV" != "xfce" ]; then
        TAG_BASE_MIN="${TAG_BASE_MIN}-${DESKTOP_ENV}"
    fi
fi

# If creating env, handle interactive mode
if [ "$CREATE_ENV" = true ]; then
    read -p "Enter VNC password (default: $VNC_PASSWD, enter 'r' for random): " INPUT_PASSWORD
    if [ "$INPUT_PASSWORD" = "r" ]; then
        VNC_PASSWD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo "Generated random VNC password: $VNC_PASSWD"
    else
        VNC_PASSWD="${INPUT_PASSWORD:-$VNC_PASSWD}"
    fi

    echo "--- Docker Hub Configuration ---"
    read -p "Enter Docker Hub Username (default: $DOCKER_USERNAME, optional, required for publish): " INPUT_DOCKER_USERNAME
    DOCKER_USERNAME="${INPUT_DOCKER_USERNAME:-$DOCKER_USERNAME}"

    # Determine IMAGE_TAG (use minimized as standard for .env)
    if [ -n "$TAG_BASE_MIN" ]; then
        IMAGE_TAG="${TAG_BASE_MIN}-${CURRENT_DATE}"
    else
        IMAGE_TAG="${CURRENT_DATE}"
    fi

    echo "Updating $ENV_FILE..."
    touch "$ENV_FILE"
    update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
    update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    update_env_var "IMAGE_TAG" "$IMAGE_TAG" "$ENV_FILE"
    update_env_var "SYSTEM" "$SYSTEM" "$ENV_FILE"
    update_env_var "SYSTEM_VERSION" "$SYSTEM_VERSION" "$ENV_FILE"
    update_env_var "DESKTOP_ENV" "$DESKTOP_ENV" "$ENV_FILE"
    
    echo ".env file updated."
else
    # If a build is requested or tag is empty, calculate primary tag
    if [ "$EXECUTE_BUILD" = true ] || [ "$PUBLISH" = true ] || [ -z "$IMAGE_TAG" ]; then
        if [ -n "$TAG_BASE_MIN" ]; then
            IMAGE_TAG="${TAG_BASE_MIN}-${CURRENT_DATE}"
        else
            IMAGE_TAG="${CURRENT_DATE}"
        fi
    fi

    # Update the .env if explicitly provided via args or if building
    if [ "$EXECUTE_BUILD" = true ] || [ "$START_CONTAINER" = true ]; then
        update_env_var "DESKTOP_ENV" "$DESKTOP_ENV" "$ENV_FILE"
        update_env_var "SYSTEM" "$SYSTEM" "$ENV_FILE"
        update_env_var "SYSTEM_VERSION" "$SYSTEM_VERSION" "$ENV_FILE"
        update_env_var "IMAGE_TAG" "$IMAGE_TAG" "$ENV_FILE"
        update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
        update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    fi
fi

# Determine CONTAINER_USER based on system
case $SYSTEM in
    debian) CONTAINER_USER="debian" ;;
    ubuntu) CONTAINER_USER="ubuntu" ;;
    arch) CONTAINER_USER="arch" ;;
    alpine) CONTAINER_USER="alpine" ;;
    fedora) CONTAINER_USER="user" ;;
    *) CONTAINER_USER="user" ;;
esac
CONTAINER_HOME="/home/${CONTAINER_USER}"
update_env_var "CONTAINER_HOME" "$CONTAINER_HOME" "$ENV_FILE"



# Prepend Docker Username to Image Name if set
if [ -n "$DOCKER_USERNAME" ]; then
    IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
fi


if [ "$PUBLISH" = true ] || [ "$EXECUTE_BUILD" = true ]; then
    # Auto-enable China mirror switching when the local timezone is in China.
    CURRENT_TZ="${TZ:-}"
    if [ -z "$CURRENT_TZ" ] && [ -f /etc/timezone ]; then
        CURRENT_TZ=$(cat /etc/timezone)
    fi
    if [ -z "$CURRENT_TZ" ]; then
        CURRENT_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
    fi

    USE_CN_MIRROR="false"
    case "$CURRENT_TZ" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|PRC)
            USE_CN_MIRROR="true"
            ;;
    esac
    echo "Detected timezone: ${CURRENT_TZ:-unknown}, USE_CN_MIRROR=$USE_CN_MIRROR"

    # Determine base dockerfile
    BASE_DOCKERFILE="base.Dockerfile"
    if [ -f "base.${SYSTEM}.Dockerfile" ]; then
        BASE_DOCKERFILE="base.${SYSTEM}.Dockerfile"
    fi

    # Determine flavor dockerfile
    DOCKERFILE="${DESKTOP_ENV}.Dockerfile"
    if [ -f "${DESKTOP_ENV}.${SYSTEM}.Dockerfile" ]; then
        DOCKERFILE="${DESKTOP_ENV}.${SYSTEM}.Dockerfile"
    fi

    if [ -f "$DOCKERFILE" ]; then
        echo "Building using $DOCKERFILE"
        
        # Build base image locally first?
        # Note: For multi-arch buildx, this might be tricky if base isn't pushed.
        # But for local builds it's fine.
        echo "Building base image from $BASE_DOCKERFILE..."
        docker build -t desktop-in-docker-base:latest \
            --build-arg SYSTEM="$SYSTEM" \
            --build-arg SYSTEM_VERSION="$SYSTEM_VERSION" \
            --build-arg USERNAME="$CONTAINER_USER" \
            --build-arg USE_CN_MIRROR="$USE_CN_MIRROR" \
            -f "$BASE_DOCKERFILE" .
    else
        DOCKERFILE="Dockerfile"
        echo "Building standard version using Dockerfile"
    fi

    # Generate all tag variants
    TAG_BASES=("$TAG_BASE_FULL")
    if [ "$TAG_BASE_MIN" != "$TAG_BASE_FULL" ]; then
        TAG_BASES+=("$TAG_BASE_MIN")
    fi

    BUILD_TAGS=()
    for tb in "${TAG_BASES[@]}"; do
        if [ -n "$tb" ]; then
            BUILD_TAGS+=("-t" "${IMAGE_NAME}:${tb}-${CURRENT_DATE}")
            [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${tb}-latest")
            [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${tb}-snapshot")
        else
            BUILD_TAGS+=("-t" "${IMAGE_NAME}:${CURRENT_DATE}")
            [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:latest")
            [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:snapshot")
        fi
    done

    BUILD_TAGS_FLAVOR=()
    for tag_option in "${BUILD_TAGS[@]}"; do
        if [[ "$tag_option" == "-t" ]]; then
            continue
        fi
        
        if [[ "$tag_option" == *":"* ]]; then
            image_part="${tag_option%:*}"
            tag_part="${tag_option#*:}"
            modified_tag="${image_part}:${tag_part}"
            BUILD_TAGS_FLAVOR+=("-t" "$modified_tag")
        else
            BUILD_TAGS_FLAVOR+=("$tag_option")
        fi
    done
fi

if [ "$PUBLISH" = true ]; then
    echo "Publisher mode enabled. Building and Pushing Multi-Arch Images (amd64, arm64)..."
    
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg DESKTOP_ENV="$DESKTOP_ENV" \
        --build-arg USERNAME="$CONTAINER_USER" \
        "${BUILD_TAGS_FLAVOR[@]}" \
        --push \
        -f "$DOCKERFILE" .

    echo "Multi-arch build and push finished."
    echo "Image pushed variants:"
    for tag_option in "${BUILD_TAGS_FLAVOR[@]}"; do
        if [ "$tag_option" != "-t" ]; then
            echo "  - $tag_option"
        fi
    done
    echo "Cleaning up dangling images..."
    docker image prune -f

elif [ "$EXECUTE_BUILD" = true ]; then   
    echo "Building the Docker image locally for current architecture..."
    
    docker build \
        --build-arg DESKTOP_ENV="$DESKTOP_ENV" \
        --build-arg USERNAME="$CONTAINER_USER" \
        "${BUILD_TAGS_FLAVOR[@]}" \
        -f "$DOCKERFILE" .

    echo "Docker image build process finished."
    echo "Image created variants:"
    for tag_option in "${BUILD_TAGS_FLAVOR[@]}"; do
        if [ "$tag_option" != "-t" ]; then
            echo "  - $tag_option"
        fi
    done
    echo "Cleaning up dangling images..."
    docker image prune -f
fi

# Start container if requested
if [ "$START_CONTAINER" = true ]; then
    echo ""
    # 启动并检查是否成功，如果成功显示下面的log
    COMPOSE_FILES="-f docker-compose.yml"
    echo "Starting docker compose..."
    if docker compose $COMPOSE_FILES up -d --build; then
        echo "Docker compose started successfully."
        # 获取映射后的外部端口
        WEB_PORT=$(docker compose port desktop 6080 2>/dev/null | cut -d':' -f2)
        VNC_PORT=$(docker compose port desktop 5901 2>/dev/null | cut -d':' -f2)
        
        echo "You can access the desktop via:"
        if [ -n "$WEB_PORT" ]; then
            echo "  - Web VNC: http://localhost:${WEB_PORT}/vnc.html"
        else
            echo "  - Web VNC mapping not found (port 6080)"
        fi
        
        if [ -n "$VNC_PORT" ]; then
            echo "  - VNC direct: localhost:${VNC_PORT}"
            echo "  - You can also run: ./vnc.sh to connect using vncviewer"
        else
            echo "  - VNC direct mapping not found (port 5901)"
        fi
    else
        echo "Failed to start docker compose."
    fi
fi

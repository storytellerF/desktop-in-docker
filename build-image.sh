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
TAG_LATEST=false
TAG_SNAPSHOT=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
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

# Get base image version from Dockerfile (supports ubuntu: or debian:)
if [ -f "base.Dockerfile" ]; then
    BASE_VERSION=$(grep "^FROM " base.Dockerfile | cut -d':' -f2 | tr -d '\r' | tr -d ' ')
    # Extract USERNAME from Dockerfile (ARG USERNAME=...)
    DF_USERNAME=$(grep "^ARG USERNAME=" base.Dockerfile | cut -d'=' -f2 | tr -d '\r' | tr -d ' ')
    CONTAINER_USER="${DF_USERNAME:-debian}"
elif [ -f "Dockerfile" ]; then
    BASE_VERSION=$(grep "^FROM " Dockerfile | cut -d':' -f2 | tr -d '\r' | tr -d ' ')
    # Extract USERNAME from Dockerfile (ARG USERNAME=...)
    DF_USERNAME=$(grep "^ARG USERNAME=" Dockerfile | cut -d'=' -f2 | tr -d '\r' | tr -d ' ')
    CONTAINER_USER="${DF_USERNAME:-debian}"
else
    BASE_VERSION="unknown"
    CONTAINER_USER="debian"
fi
CONTAINER_HOME="/home/${CONTAINER_USER}"

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

# Set defaults if still empty
VNC_PASSWD="${VNC_PASSWD:-$DEFAULT_VNC_PASSWORD}"
DESKTOP_ENV="${DESKTOP_ENV:-xfce}"

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

    # Calculate IMAGE_TAG
    IMAGE_TAG="${BASE_VERSION}-${DESKTOP_ENV}-${CURRENT_DATE}"

    echo "Updating $ENV_FILE..."
    touch "$ENV_FILE"
    update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
    update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    update_env_var "IMAGE_TAG" "$IMAGE_TAG" "$ENV_FILE"
    update_env_var "CONTAINER_HOME" "$CONTAINER_HOME" "$ENV_FILE"
    update_env_var "BASE_VERSION" "$BASE_VERSION" "$ENV_FILE"
    update_env_var "DESKTOP_ENV" "$DESKTOP_ENV" "$ENV_FILE"
    
    echo ".env file updated."
else
    # Non-interactive Mode:
    # If a build is requested, calculate a fresh tag
    if [ "$EXECUTE_BUILD" = true ] || [ "$PUBLISH" = true ]; then
        IMAGE_TAG="${BASE_VERSION}-${DESKTOP_ENV}-${CURRENT_DATE}"
    elif [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="${BASE_VERSION}-${DESKTOP_ENV}-${CURRENT_DATE}"
    fi

    # Update the .env if explicitly provided via args or if building
    if [ "$EXECUTE_BUILD" = true ] || [ "$START_CONTAINER" = true ]; then
        update_env_var "DESKTOP_ENV" "$DESKTOP_ENV" "$ENV_FILE"
        update_env_var "BASE_VERSION" "$BASE_VERSION" "$ENV_FILE"
        update_env_var "IMAGE_TAG" "$IMAGE_TAG" "$ENV_FILE"
        update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
        update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    fi
fi



# Prepend Docker Username to Image Name if set
if [ -n "$DOCKER_USERNAME" ]; then
    IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
fi


if [ "$PUBLISH" = true ] || [ "$EXECUTE_BUILD" = true ]; then
    if [ -f "${DESKTOP_ENV}.Dockerfile" ]; then
        DOCKERFILE="${DESKTOP_ENV}.Dockerfile"
        echo "Building using flavor-specific $DOCKERFILE"
        
        # Build base image locally first?
        # Note: For multi-arch buildx, this might be tricky if base isn't pushed.
        # But for local builds it's fine.
        echo "Building base image from base.Dockerfile..."
        docker build -t desktop-in-docker-base:latest -f base.Dockerfile .
    else
        DOCKERFILE="Dockerfile"
        echo "Building standard version using Dockerfile"
    fi

    BUILD_TAGS=("-t" "${IMAGE_NAME}:${IMAGE_TAG}")
    [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${BASE_VERSION}-${DESKTOP_ENV}-latest")
    [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${BASE_VERSION}-${DESKTOP_ENV}-snapshot")

    if [ "$BASE_VERSION" = "trixie" ]; then
        BUILD_TAGS+=("-t" "${IMAGE_NAME}:${DESKTOP_ENV}-${CURRENT_DATE}")
        [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${DESKTOP_ENV}-latest")
        [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:${DESKTOP_ENV}-snapshot")
    fi

    # Only tag as global latest/snapshot if the desktop environment is xfce
    if [ "$DESKTOP_ENV" = "xfce" ]; then
        [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:latest")
        [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:snapshot")
    fi

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
        "${BUILD_TAGS_FLAVOR[@]}" \
        --push \
        -f "$DOCKERFILE" .

    echo "Multi-arch build and push finished."
    echo "Image pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
    if [ "$BASE_VERSION" = "trixie" ]; then
        echo "Also pushed tag: ${IMAGE_NAME}:${DESKTOP_ENV}-${CURRENT_DATE}"
        [ "$TAG_LATEST" = true ] && echo "Also pushed tag: ${IMAGE_NAME}:${DESKTOP_ENV}-latest"
        [ "$TAG_SNAPSHOT" = true ] && echo "Also pushed tag: ${IMAGE_NAME}:${DESKTOP_ENV}-snapshot"
    fi
    if [ "$DESKTOP_ENV" = "xfce" ]; then
        [ "$TAG_LATEST" = true ] && echo "Also pushed tag: ${IMAGE_NAME}:latest"
        [ "$TAG_SNAPSHOT" = true ] && echo "Also pushed tag: ${IMAGE_NAME}:snapshot"
    fi
    echo "Cleaning up dangling images..."
    docker image prune -f

elif [ "$EXECUTE_BUILD" = true ]; then   
    echo "Building the Docker image locally for current architecture..."
    
    docker build \
        --build-arg DESKTOP_ENV="$DESKTOP_ENV" \
        "${BUILD_TAGS_FLAVOR[@]}" \
        -f "$DOCKERFILE" .

    echo "Docker image build process finished."
    echo "Image created: ${IMAGE_NAME}:${IMAGE_TAG}"
    if [ "$BASE_VERSION" = "trixie" ]; then
        echo "Also tagged as: ${IMAGE_NAME}:${DESKTOP_ENV}-${CURRENT_DATE}"
        [ "$TAG_LATEST" = true ] && echo "Also tagged as: ${IMAGE_NAME}:${DESKTOP_ENV}-latest"
        [ "$TAG_SNAPSHOT" = true ] && echo "Also tagged as: ${IMAGE_NAME}:${DESKTOP_ENV}-snapshot"
    fi
    if [ "$DESKTOP_ENV" = "xfce" ]; then
        [ "$TAG_LATEST" = true ] && echo "Also tagged as: ${IMAGE_NAME}:latest"
        [ "$TAG_SNAPSHOT" = true ] && echo "Also tagged as: ${IMAGE_NAME}:snapshot"
    fi
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

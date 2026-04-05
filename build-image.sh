#!/bin/bash
set -e

IMAGE_NAME="desktop-in-docker"
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

append_tag_with_reason() {
    local tags_name=$1
    local reasons_name=$2
    local reason=$3
    local tag=$4
    local -n tags_ref="$tags_name"
    local -n reasons_ref="$reasons_name"

    tags_ref+=("-t" "$tag")
    reasons_ref+=("$reason")
}

print_tag_summary() {
    local title=$1
    local tags_name=$2
    local reasons_name=$3
    local -n tags_ref="$tags_name"
    local -n reasons_ref="$reasons_name"
    local tag_header="Tag"
    local reason_header="Reason"
    local reason_index=0
    local reason_width
    local tag_width
    local reason_sep
    local tag_sep

    reason_width=${#reason_header}
    tag_width=${#tag_header}

    for tag_option in "${tags_ref[@]}"; do
        if [ "$tag_option" != "-t" ]; then
            if [ ${#reasons_ref[$reason_index]} -gt "$reason_width" ]; then
                reason_width=${#reasons_ref[$reason_index]}
            fi
            if [ ${#tag_option} -gt "$tag_width" ]; then
                tag_width=${#tag_option}
            fi
            ((reason_index += 1))
        fi
    done

    printf -v reason_sep '%*s' "$reason_width" ''
    printf -v tag_sep '%*s' "$tag_width" ''
    reason_sep=${reason_sep// /-}
    tag_sep=${tag_sep// /-}

    echo "$title"
    printf '  | %-*s | %-*s |\n' "$tag_width" "$tag_header" "$reason_width" "$reason_header"
    printf '  | %s | %s |\n' "$tag_sep" "$reason_sep"
    reason_index=0
    for tag_option in "${tags_ref[@]}"; do
        if [ "$tag_option" != "-t" ]; then
            printf '  | %-*s | %-*s |\n' "$tag_width" "$tag_option" "$reason_width" "${reasons_ref[$reason_index]}"
            ((reason_index += 1))
        fi
    done
}

print_available_desktops() {
    echo "Available desktop environments: xfce, lxqt, kde, mate, cinnamon, lxde, gnome, enlightenment"
}

is_default_system_version() {
    [ "$SYSTEM" = "debian" ] && [ "$SYSTEM_VERSION" = "trixie" ]
}

is_default_desktop() {
    [ "$DESKTOP_ENV" = "xfce" ]
}

append_standard_image_tags() {
    local image_name=$1
    local tag_prefix=$2
    local tags_name=$3
    local reasons_name=$4

    append_tag_with_reason "$tags_name" "$reasons_name" "always" "${image_name}:${tag_prefix}-${CURRENT_DATE}"
    if [ "$TAG_LATEST" = true ]; then
        append_tag_with_reason "$tags_name" "$reasons_name" "--latest specified" "${image_name}:${tag_prefix}-latest"
    fi
    if [ "$TAG_SNAPSHOT" = true ]; then
        append_tag_with_reason "$tags_name" "$reasons_name" "--no-snapshot not specified" "${image_name}:${tag_prefix}-snapshot"
    fi
}

append_short_image_tags() {
    local image_name=$1
    local full_prefix=$2
    local short_prefix=$3
    local description=$4
    local tags_name=$5
    local reasons_name=$6
    local separator="-"

    if [ "$short_prefix" = "$full_prefix" ]; then
        return
    fi

    if [ -z "$short_prefix" ]; then
        separator=""
    fi

    append_tag_with_reason "$tags_name" "$reasons_name" "always, ${description} shorthand" "${image_name}:${short_prefix}${separator}${CURRENT_DATE}"
    if [ "$TAG_LATEST" = true ]; then
        append_tag_with_reason "$tags_name" "$reasons_name" "--latest specified, ${description} shorthand" "${image_name}:${short_prefix}${separator}latest"
    fi
    if [ "$TAG_SNAPSHOT" = true ]; then
        append_tag_with_reason "$tags_name" "$reasons_name" "--no-snapshot not specified, ${description} shorthand" "${image_name}:${short_prefix}${separator}snapshot"
    fi
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

IMAGE_TIMESTAMP="${IMAGE_TIMESTAMP:-$CURRENT_DATE}"

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

BASE_TAG_PREFIX="${SYSTEM}-${SYSTEM_VERSION}-base"
DESKTOP_TAG_PREFIX="${SYSTEM}-${SYSTEM_VERSION}-${DESKTOP_ENV}"

SHORT_BASE_TAG_PREFIX="$BASE_TAG_PREFIX"
if is_default_system_version; then
    SHORT_BASE_TAG_PREFIX="base"
fi

SHORT_DESKTOP_TAG_PREFIX="$DESKTOP_TAG_PREFIX"
if is_default_system_version; then
    SHORT_DESKTOP_TAG_PREFIX="$DESKTOP_ENV"
fi
if is_default_desktop; then
    if is_default_system_version; then
        SHORT_DESKTOP_TAG_PREFIX=""
    else
        SHORT_DESKTOP_TAG_PREFIX="${SYSTEM}-${SYSTEM_VERSION}"
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

    echo "Updating $ENV_FILE..."
    touch "$ENV_FILE"
    IMAGE_TIMESTAMP="$CURRENT_DATE"
    update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
    update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    update_env_var "IMAGE_TIMESTAMP" "$IMAGE_TIMESTAMP" "$ENV_FILE"

    echo ".env file updated."
else
    echo "Not creating .env file. Using existing values or defaults."
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

# Prepend Docker Username to Image Name if set
BASE_IMAGE_NAME="desktop-in-docker"
if [ -n "$DOCKER_USERNAME" ]; then
    IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
    BASE_IMAGE_NAME="${DOCKER_USERNAME}/${BASE_IMAGE_NAME}"
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
    BASE_DOCKERFILE="dockerfiles/base/Dockerfile"
    if [ -f "dockerfiles/base/${SYSTEM}.Dockerfile" ]; then
        BASE_DOCKERFILE="dockerfiles/base/${SYSTEM}.Dockerfile"
    fi
    if [ ! -f "$BASE_DOCKERFILE" ]; then
        echo "Base Dockerfile not found for system '$SYSTEM': $BASE_DOCKERFILE"
        exit 1
    fi

    # Determine flavor dockerfile
    DOCKERFILE="dockerfiles/${DESKTOP_ENV}/Dockerfile"
    if [ -f "dockerfiles/${DESKTOP_ENV}/${SYSTEM}.Dockerfile" ]; then
        DOCKERFILE="dockerfiles/${DESKTOP_ENV}/${SYSTEM}.Dockerfile"
    fi

    if [ ! -f "$DOCKERFILE" ]; then
        echo "Desktop Dockerfile not found for desktop '$DESKTOP_ENV' on system '$SYSTEM': $DOCKERFILE"
        print_available_desktops
        exit 1
    fi

    echo "Building using $DOCKERFILE"
    
    # Build base image locally first?
    # Note: For multi-arch buildx, this might be tricky if base isn't pushed.
    # But for local builds it's fine.
    BASE_BUILD_TAGS=()
    BASE_BUILD_TAG_REASONS=()
    append_standard_image_tags "$BASE_IMAGE_NAME" "$BASE_TAG_PREFIX" "BASE_BUILD_TAGS" "BASE_BUILD_TAG_REASONS"
    append_short_image_tags "$BASE_IMAGE_NAME" "$BASE_TAG_PREFIX" "$SHORT_BASE_TAG_PREFIX" "default system-version omitted" "BASE_BUILD_TAGS" "BASE_BUILD_TAG_REASONS"

    # Reference tag for desktop Dockerfiles to use as FROM
    BASE_IMAGE_LOCAL_REF="${BASE_IMAGE_NAME}:${BASE_TAG_PREFIX}-${CURRENT_DATE}"
    BASE_IMAGE_PUBLISH_REF="${BASE_IMAGE_NAME}:${BASE_TAG_PREFIX}-${CURRENT_DATE}"

    echo "Building base image from $BASE_DOCKERFILE..."
    docker build \
        "${BASE_BUILD_TAGS[@]}" \
        --build-arg SYSTEM="$SYSTEM" \
        --build-arg SYSTEM_VERSION="$SYSTEM_VERSION" \
        --build-arg USERNAME="$CONTAINER_USER" \
        --build-arg USE_CN_MIRROR="$USE_CN_MIRROR" \
        -f "$BASE_DOCKERFILE" .

    BUILD_TAGS=()
    BUILD_TAG_REASONS=()
    append_standard_image_tags "$IMAGE_NAME" "$DESKTOP_TAG_PREFIX" "BUILD_TAGS" "BUILD_TAG_REASONS"
    append_short_image_tags "$IMAGE_NAME" "$DESKTOP_TAG_PREFIX" "$SHORT_DESKTOP_TAG_PREFIX" "default system-version and/or desktop omitted" "BUILD_TAGS" "BUILD_TAG_REASONS"

    BUILD_TAGS_FLAVOR=("${BUILD_TAGS[@]}")
    BUILD_TAGS_FLAVOR_REASONS=("${BUILD_TAG_REASONS[@]}")
fi

if [ "$PUBLISH" = true ]; then
    echo "Publisher mode enabled. Building and Pushing Multi-Arch Images (amd64, arm64)..."

    # Push base image
    echo "Pushing base image..."
    BASE_PUBLISH_TAGS=()
    BASE_PUBLISH_TAG_REASONS=()
    append_standard_image_tags "$BASE_IMAGE_NAME" "$BASE_TAG_PREFIX" "BASE_PUBLISH_TAGS" "BASE_PUBLISH_TAG_REASONS"
    append_short_image_tags "$BASE_IMAGE_NAME" "$BASE_TAG_PREFIX" "$SHORT_BASE_TAG_PREFIX" "default system-version omitted" "BASE_PUBLISH_TAGS" "BASE_PUBLISH_TAG_REASONS"

    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg SYSTEM="$SYSTEM" \
        --build-arg SYSTEM_VERSION="$SYSTEM_VERSION" \
        --build-arg USERNAME="$CONTAINER_USER" \
        --build-arg USE_CN_MIRROR="$USE_CN_MIRROR" \
        "${BASE_PUBLISH_TAGS[@]}" \
        --push \
        -f "$BASE_DOCKERFILE" .

    print_tag_summary "Base image pushed variants:" "BASE_PUBLISH_TAGS" "BASE_PUBLISH_TAG_REASONS"

    # Push desktop image
    echo "Pushing desktop image..."
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg BASE_IMAGE="${BASE_IMAGE_PUBLISH_REF}" \
        --build-arg DESKTOP_ENV="$DESKTOP_ENV" \
        --build-arg USERNAME="$CONTAINER_USER" \
        "${BUILD_TAGS_FLAVOR[@]}" \
        --push \
        -f "$DOCKERFILE" .

    echo "Multi-arch build and push finished."
    print_tag_summary "Desktop image pushed variants:" "BUILD_TAGS_FLAVOR" "BUILD_TAGS_FLAVOR_REASONS"
    echo "Cleaning up dangling images..."
    docker image prune -f

elif [ "$EXECUTE_BUILD" = true ]; then   
    echo "Building the Docker image locally for current architecture..."
    
    docker build \
        --build-arg BASE_IMAGE="${BASE_IMAGE_LOCAL_REF}" \
        --build-arg DESKTOP_ENV="$DESKTOP_ENV" \
        --build-arg USERNAME="$CONTAINER_USER" \
        "${BUILD_TAGS_FLAVOR[@]}" \
        -f "$DOCKERFILE" .

    echo "Docker image build process finished."
    print_tag_summary "Base image created variants:" "BASE_BUILD_TAGS" "BASE_BUILD_TAG_REASONS"
    print_tag_summary "Desktop image created variants:" "BUILD_TAGS_FLAVOR" "BUILD_TAGS_FLAVOR_REASONS"
    echo "Cleaning up dangling images..."
    docker image prune -f
fi

# Start container if requested
if [ "$START_CONTAINER" = true ]; then
    echo ""

    # Determine IMAGE_TAG for docker compose
    if [ "$TAG_LATEST" = true ]; then
        IMAGE_TAG="${DESKTOP_TAG_PREFIX}-latest"
    elif [ "$TAG_SNAPSHOT" = true ]; then
        IMAGE_TAG="${DESKTOP_TAG_PREFIX}-snapshot"
    else
        IMAGE_TAG="${DESKTOP_TAG_PREFIX}-${CURRENT_DATE}"
    fi

    # Export variables for docker compose
    export DOCKER_USERNAME="${DOCKER_USERNAME:-storytellerf}"
    export IMAGE_TAG
    export CONTAINER_HOME
    export VNC_PASSWD
    echo "Exported DOCKER_USERNAME=$DOCKER_USERNAME, IMAGE_TAG=$IMAGE_TAG, CONTAINER_HOME=$CONTAINER_HOME"

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

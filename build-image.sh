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
    echo "  --latest                     Tag the image as 'latest'"
    echo "  --no-snapshot                Do not tag the image as 'snapshot' (snapshot is tagged by default)"
    echo "  -h, --help                   Display this help message"
    exit 1
}

# Parse arguments
CREATE_ENV=false
EXECUTE_BUILD=false
START_CONTAINER=false
PUBLISH=false
MULTI_ARCH=false
DOCKER_USERNAME=""
VNC_PASSWORD=""
TAG_LATEST=false
TAG_SNAPSHOT=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--password)
            VNC_PASSWORD="$2"
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
if [ -f "Dockerfile" ]; then
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
    # We use a temporary file to source to avoid exporting variables to the current shell if we didn't want to, 
    # but here we do want them.
    # However, we must be careful not to overwrite args passed via command line if we want args to take precedence.
    # Strategy: Source env, then re-apply args if they were set.
    source "$ENV_FILE"
fi

# Re-apply command line arguments if valid (overriding .env)
[ -n "$DOCKER_USERNAME" ] && DOCKER_USERNAME="$DOCKER_USERNAME"
[ -n "$VNC_PASSWORD" ] && VNC_PASSWD="$VNC_PASSWORD"

# Set defaults if still empty
VNC_PASSWD="${VNC_PASSWD:-$DEFAULT_VNC_PASSWORD}"


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

    # Calculate IMAGE_TAG (removed JDK part)
    IMAGE_TAG="${BASE_VERSION}.${CURRENT_DATE}"

    echo "Updating $ENV_FILE..."
    # Helper to write or update var in file
    update_env_var() {
        local key=$1
        local val=$2
        local file=$3
        if grep -q "^${key}=" "$file"; then
            sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
        else
            echo "${key}=\"${val}\"" >> "$file"
        fi
    }

    # Initialize file if not exists
    touch "$ENV_FILE"

    update_env_var "DOCKER_USERNAME" "$DOCKER_USERNAME" "$ENV_FILE"
    update_env_var "VNC_PASSWD" "$VNC_PASSWD" "$ENV_FILE"
    update_env_var "IMAGE_TAG" "$IMAGE_TAG" "$ENV_FILE"
    update_env_var "CONTAINER_HOME" "$CONTAINER_HOME" "$ENV_FILE"
    
    echo ".env file updated."
else
    # Non-interactive Mode: Just calculate tag if not present or needs refresh? 
    # Actually, if we are just building, we rely on .env values.
    # If IMAGE_TAG is not in .env, we generate one temporarily for this build?
    if [ -z "$IMAGE_TAG" ]; then
         IMAGE_TAG="${BASE_VERSION}.${CURRENT_DATE}"
    fi
fi


# Prepend Docker Username to Image Name if set
if [ -n "$DOCKER_USERNAME" ]; then
    IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}"
fi


if [ "$PUBLISH" = true ] || [ "$EXECUTE_BUILD" = true ]; then
    DOCKERFILE="Dockerfile"
    echo "Building standard version using Dockerfile"

    BUILD_TAGS=("-t" "${IMAGE_NAME}:${IMAGE_TAG}")
    [ "$TAG_LATEST" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:latest")
    [ "$TAG_SNAPSHOT" = true ] && BUILD_TAGS+=("-t" "${IMAGE_NAME}:snapshot")

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
        "${BUILD_TAGS_FLAVOR[@]}" \
        --push \
        -f "$DOCKERFILE" .

    echo "Multi-arch build and push finished."
    echo "Image pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Cleaning up dangling images..."
    docker image prune -f

elif [ "$EXECUTE_BUILD" = true ]; then   
    echo "Building the Docker image locally for current architecture..."
    
    docker build \
        "${BUILD_TAGS_FLAVOR[@]}" \
        -f "$DOCKERFILE" .

    echo "Docker image build process finished."
    echo "Image created: ${IMAGE_NAME}:${IMAGE_TAG}"
    [ "$TAG_LATEST" = true ] && echo "Also tagged as: ${IMAGE_NAME}:latest"
    [ "$TAG_SNAPSHOT" = true ] && echo "Also tagged as: ${IMAGE_NAME}:snapshot"
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
        echo "You can access the desktop via:"
        echo "  - Web VNC: http://localhost:6080/vnc.html"
        echo "  - VNC direct: localhost:5901"
    else
        echo "Failed to start docker compose."
    fi
fi

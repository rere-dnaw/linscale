#!/bin/bash
# -----------------------------------------------------------------------------
# Build and push skynet Docker image
# Usage: ./release.sh [tag]
# -----------------------------------------------------------------------------
set -e

TAG="${1:-latest}"
REGISTRY="${REGISTRY:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WORKLOAD_DIR")"

if [ -z "$REGISTRY" ]; then
    REMOTE=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")
    if echo "$REMOTE" | grep -q "github.com"; then
        REPO_PATH=$(echo "$REMOTE" | sed 's/.*github.com[/:]//' | sed 's/.git//')
        REGISTRY="ghcr.io/${REPO_PATH}"
    else
        REGISTRY="docker.io/library/skynet"
    fi
fi

IMAGE="${REGISTRY}:${TAG}"

echo "==> Building skynet image: $IMAGE"
echo "    Context: $REPO_ROOT/skynet"
echo "    Build args: BUILD_WITH_VLLM=1"

docker build \
    -t "$IMAGE" \
    --build-arg BUILD_WITH_VLLM=1 \
    -f "$REPO_ROOT/skynet/Dockerfile" \
    "$REPO_ROOT/skynet"

echo "==> Pushing $IMAGE..."
docker push "$IMAGE"

if [ "$TAG" != "latest" ]; then
    echo "==> Also tagging as latest..."
    docker tag "$IMAGE" "${REGISTRY}:latest"
    docker push "${REGISTRY}:latest"
fi

echo ""
echo "========================================"
echo "Image ready: $IMAGE"
echo "========================================"
echo ""
echo "To deploy, update k8scale/skynet/.env:"
echo "  WORKLOAD_IMAGE=$IMAGE"

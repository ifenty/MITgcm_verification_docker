#!/bin/bash
#
# Helper script to build the Docker image (compilers + libraries only)
#
# The new architecture mounts MITgcm at runtime, so the Docker image
# only contains compilers, NetCDF, and MPI libraries. This allows
# users to modify MITgcm source code without rebuilding Docker.
#

set -e

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Build the mitgcm:latest Docker image (compilers + NetCDF + OpenMPI only;"
    echo "MITgcm source is mounted at runtime, not baked into the image)."
    echo ""
    echo "Architecture (ARM64 vs x86_64) is auto-detected via 'uname -m';"
    echo "there are no flags to set."
    exit 0
fi

# Resolve symlink to find the actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_PATH" )" && pwd )"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_PATH" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect architecture and set appropriate MPI architecture
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64)
        MPI_ARCH="aarch64-linux-gnu"
        ;;
    x86_64|amd64)
        MPI_ARCH="x86_64-linux-gnu"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: arm64, aarch64, x86_64, amd64"
        exit 1
        ;;
esac

echo "=========================================="
echo "Building Docker image for MITgcm"
echo "=========================================="
echo "  Architecture: $ARCH"
echo "  MPI arch:     $MPI_ARCH"
echo "=========================================="
echo ""
echo "Note: This image contains only compilers and libraries."
echo "      MITgcm source will be mounted at runtime from your host."
echo ""

cd "$REPO_ROOT"
docker build -t mitgcm:latest \
    --build-arg MPI_ARCH="$MPI_ARCH" \
    -f Dockerfile .

echo ""
echo "=========================================="
echo "Docker image built successfully!"
echo "=========================================="
echo ""
echo "The image is ready to use. MITgcm source code will be"
echo "mounted from your host machine when you run experiments."
echo ""

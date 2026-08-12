#!/bin/bash
#
# Helper script to build the Docker image
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MITGCM_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect architecture and set appropriate optfile and MPI architecture
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64)
        OPTFILE="linux_arm64_gfortran"
        MPI_ARCH="aarch64-linux-gnu"
        ;;
    x86_64|amd64)
        OPTFILE="linux_amd64_gfortran"
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
echo "  Optfile:      $OPTFILE"
echo "  MPI arch:     $MPI_ARCH"
echo "=========================================="
echo ""

cd "$MITGCM_ROOT"
docker build -t mitgcm:latest \
    --build-arg OPTFILE="$OPTFILE" \
    --build-arg MPI_ARCH="$MPI_ARCH" \
    -f verification/Dockerfile .

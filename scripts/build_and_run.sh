#!/bin/bash
#
# Helper script to build and run the Docker
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MITGCM_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building Docker image for MITgcm..."
cd "$MITGCM_ROOT"
docker build -t mitgcm:latest -f verification/Dockerfile .

echo ""
echo "Running the Docker image (like logging in)..."
docker run --rm -it \
    --platform linux/arm64 \
    mitgcm:latest


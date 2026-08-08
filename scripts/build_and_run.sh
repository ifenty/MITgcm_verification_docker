#!/bin/bash
#
# Helper script to build and run MITgcm 1D_ocean_ice_column verification test in Docker
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MITGCM_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building Docker image for MITgcm..."
cd "$MITGCM_ROOT"
docker build -t mitgcm:latest -f verification/Dockerfile .

echo ""
echo "Running MITgcm 1D_ocean_ice_column verification test..."
docker run --rm -it \
    --platform linux/arm64 \
    mitgcm:latest

echo ""
echo "Test complete!"

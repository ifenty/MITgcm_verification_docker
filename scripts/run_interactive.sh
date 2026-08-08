#!/bin/bash
#
# Run an interactive shell in the MITgcm Docker container
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MITGCM_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Starting interactive Docker container for MITgcm..."
cd "$MITGCM_ROOT"

# Build image if it doesn't exist
if ! docker image inspect mitgcm:latest >/dev/null 2>&1; then
    echo "Image not found. Building..."
    docker build -t mitgcm:latest -f verification/Dockerfile .
fi

echo ""
echo "Starting interactive bash shell..."
echo "You are in: /home/mitgcm/MITgcm/verification"
echo ""
echo "To run the test manually:"
echo "  ./testreport -t 1D_ocean_ice_column -optfile ../tools/build_options/linux_amd64_gfortran"
echo ""
echo "Or to build manually:"
echo "  cd 1D_ocean_ice_column/build"
echo "  ../../../tools/genmake2 -mods=../code -optfile=../../../tools/build_options/linux_amd64_gfortran"
echo "  make depend"
echo "  make"
echo "  cd ../run"
echo "  ln -s ../input/* ."
echo "  ln -s ../build/mitgcmuv ."
echo "  ./mitgcmuv"
echo ""

docker run --rm -it \
    --platform linux/arm64 \
    mitgcm:latest \
    /bin/bash

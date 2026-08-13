#!/bin/bash
#
# Run an interactive shell in the MITgcm Docker container
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MITGCM_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
    OPTFILE="linux_arm64_gfortran"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    PLATFORM="linux/amd64"
    OPTFILE="linux_amd64_gfortran"
else
    echo "Warning: Unknown architecture $ARCH, defaulting to linux/amd64"
    PLATFORM="linux/amd64"
    OPTFILE="linux_amd64_gfortran"
fi

echo "Starting interactive Docker container for MITgcm..."
echo "Architecture: $ARCH -> $PLATFORM"
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
echo "Environment variables set:"
echo "  OPTFILE=$OPTFILE (full path)"
echo ""
echo "To run the test manually:"
echo "  ./testreport -t 1D_ocean_ice_column -optfile \$OPTFILE"
echo ""
echo "Or to build manually:"
echo "  cd 1D_ocean_ice_column/build"
echo "  ../../../tools/genmake2 -mods=../code -optfile=\$OPTFILE"
echo "  make depend"
echo "  make"
echo "  cd ../run"
echo "  ln -s ../input/* ."
echo "  ln -s ../build/mitgcmuv ."
echo "  ./mitgcmuv"
echo ""

docker run --rm -it \
    --platform $PLATFORM \
    mitgcm:latest \
    /bin/bash

#!/bin/bash
#
# Setup symlinks from this repository to MITgcm verification directory
#
# Usage: ./setup_links.sh /path/to/MITgcm/verification [optfile]

set -e

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TARGET_DIR="${1}"
OPTFILE="${2}"

if [[ "$1" == "-h" || "$1" == "--help" || -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 /path/to/MITgcm/verification [optfile]"
    echo ""
    echo "One-time setup: symlinks this repo's scripts and README into your"
    echo "MITgcm verification/ directory. (docker_build.sh builds the image"
    echo "from this repo's Dockerfile, so no copy is placed there.)"
    echo ""
    echo "optfile is optional; if omitted, the architecture (ARM64/x86_64) is"
    echo "auto-detected and a matching build-options file is suggested."
    echo ""
    echo "Example:"
    echo "  $0 /Users/username/MITgcm/verification"
    echo "  $0 /Users/username/MITgcm/verification linux_amd64_gfortran"
    echo ""
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        exit 0
    fi
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory not found: $TARGET_DIR"
    echo ""
    echo "Please provide the full path to your MITgcm verification directory."
    exit 1
fi

# Check if it looks like a verification directory
if [ ! -d "$TARGET_DIR/1D_ocean_ice_column" ]; then
    echo "Warning: $TARGET_DIR doesn't appear to be a MITgcm verification directory"
    echo "(1D_ocean_ice_column not found)"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "=========================================="
echo "Setting up MITgcm Docker tools"
echo "=========================================="
echo "Repository: $REPO_DIR"
echo "Target:     $TARGET_DIR"
echo "=========================================="
echo ""

# Check for MITgcm build options directory
TOOLS_DIR="$TARGET_DIR/../tools/build_options"
if [ ! -d "$TOOLS_DIR" ]; then
    echo "Error: MITgcm build_options directory not found: $TOOLS_DIR"
    echo ""
    echo "Please ensure TARGET_DIR is a valid MITgcm verification directory."
    exit 1
fi

# Detect system architecture if optfile not specified
if [ -z "$OPTFILE" ]; then
    ARCH=$(uname -m)
    OS=$(uname -s)

    echo "Detecting system architecture..."
    echo "  OS:   $OS"
    echo "  Arch: $ARCH"
    echo ""

    # Map architecture to optfile
    if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        SUGGESTED_OPTFILE="linux_arm64_gfortran"
        ARCH_DESC="ARM64 (Apple Silicon M1/M2/M3/M4 or ARM servers)"
    elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        SUGGESTED_OPTFILE="linux_amd64_gfortran"
        ARCH_DESC="x86_64 (Intel/AMD)"
    else
        echo "⚠ Warning: Unrecognized architecture: $ARCH"
        echo ""
        echo "Please select a build options file from MITgcm's tools/build_options/"
        echo ""
        read -p "Enter optfile name (or press Enter to skip): " OPTFILE
        if [ -z "$OPTFILE" ]; then
            echo "Skipping optfile verification. You'll need to specify it manually when compiling."
            OPTFILE="none"
        fi
    fi

    if [ -n "$SUGGESTED_OPTFILE" ]; then
        echo "Recommended build options file for $ARCH_DESC:"
        echo "  → $SUGGESTED_OPTFILE"
        echo ""

        # Check if recommended optfile exists in MITgcm
        if [ -f "$TOOLS_DIR/$SUGGESTED_OPTFILE" ]; then
            echo "✓ Found $SUGGESTED_OPTFILE in MITgcm's build_options/"
            OPTFILE="$SUGGESTED_OPTFILE"
        else
            echo "⚠ $SUGGESTED_OPTFILE not found in MITgcm's build_options/"
            echo ""
            echo "Available files in $TOOLS_DIR:"
            ls -1 "$TOOLS_DIR" | grep "linux_.*_gfortran" | head -10
            echo ""
            read -p "Enter optfile name (or press Enter to use $SUGGESTED_OPTFILE anyway): " custom_choice
            if [ -n "$custom_choice" ]; then
                OPTFILE="$custom_choice"
            else
                OPTFILE="$SUGGESTED_OPTFILE"
            fi
        fi

        echo ""
        echo "Using optfile: $OPTFILE"
    fi
fi

# Verify optfile exists in MITgcm if not "none"
if [ "$OPTFILE" != "none" ]; then
    if [ ! -f "$TOOLS_DIR/$OPTFILE" ]; then
        echo "⚠ Warning: Build options file not found in MITgcm:"
        echo "   $TOOLS_DIR/$OPTFILE"
        echo ""
        echo "You may need to:"
        echo "  1. Use a different optfile name from MITgcm's tools/build_options/"
        echo "  2. Create your own optfile in tools/build_options/"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo ""

# Files to link from scripts directory
SCRIPT_FILES=(
    "experiment_compile.sh"
    "experiment_run_no_compile.sh"
    "docker_build.sh"
    "docker_run_interactive.sh"
    "compare_results.sh"
)

# Files to link from root directory (documentation)
DOC_FILES=(
    "README.md"
)

# Create symlinks for scripts
echo "Creating symlinks..."
for file in "${SCRIPT_FILES[@]}"; do
    SOURCE="$REPO_DIR/scripts/$file"
    DEST="$TARGET_DIR/$file"

    if [ -L "$DEST" ]; then
        echo "  ✓ $file (already linked)"
    elif [ -e "$DEST" ]; then
        echo "  ⚠ $file (exists, skipping)"
    else
        ln -s "$SOURCE" "$DEST"
        echo "  ✓ $file"
    fi
done

# Earlier versions copied the Dockerfile here. docker_build.sh never used
# that copy (it builds from this repo), so remove it before it goes stale --
# but only if it is recognizably this repo's Dockerfile.
if [ -f "$TARGET_DIR/Dockerfile" ] && [ ! -L "$TARGET_DIR/Dockerfile" ] && \
   grep -q "MITgcm will be mounted at runtime at /mitgcm" "$TARGET_DIR/Dockerfile"; then
    rm -f "$TARGET_DIR/Dockerfile"
    echo "  ✗ Dockerfile (removed old copy; the image is built from $REPO_DIR/Dockerfile)"
fi

# Create symlinks for documentation files
for file in "${DOC_FILES[@]}"; do
    SOURCE="$REPO_DIR/$file"
    DEST="$TARGET_DIR/$file"

    if [ -L "$DEST" ]; then
        echo "  ✓ $file (already linked)"
    elif [ -e "$DEST" ]; then
        echo "  ⚠ $file (exists, skipping)"
    else
        ln -s "$SOURCE" "$DEST"
        echo "  ✓ $file"
    fi
done

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="

if [ "$OPTFILE" != "none" ]; then
    echo ""
    echo "Build options file: $OPTFILE"
    echo "Location: ../tools/build_options/$OPTFILE"
fi

echo ""
echo "Next steps:"
echo ""
echo "1. Build Docker image:"
echo "   cd $TARGET_DIR"
echo "   ./docker_build.sh"
echo ""

if [ "$OPTFILE" != "none" ]; then
    echo "2. Compile an experiment:"
    echo "   ./experiment_compile.sh 1D_ocean_ice_column -j 8"
    echo ""
    echo "3. Run the model:"
    echo "   ./experiment_run_no_compile.sh 1D_ocean_ice_column"
else
    echo "2. You'll need to specify a build options file manually when compiling."
    echo "   See: ../tools/build_options/ for available options"
fi

echo ""
echo "See README.md for more commands."
echo ""

#!/bin/bash
#
# Compile MITgcm verification experiment (NO RUN)
#
# Usage: ./experiment_compile.sh <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-output <dir>] [-clean]
#
# Options:
#   -j <jobs>     Number of parallel make jobs (default: 4)
#                 Use -j 1 for serial build
#                 Use -j 8 or -j 16 for faster builds on powerful machines
#   -mpi          Compile with MPI support (auto-detects processes from SIZE.h_mpi)
#   -mods <dir>   Use custom code from specified directory (MUST be absolute path)
#   -output <dir> Output directory name (default: output_docker)
#   -clean        Force clean build (otherwise uses incremental compilation)
#
# Output:
#   - Build files saved to: <experiment>/build_docker/
#   - Binary saved to both:
#       <experiment>/build_docker/mitgcmuv
#       <experiment>/output_docker/mitgcmuv
#
# Examples:
#   ./experiment_compile.sh 1D_ocean_ice_column
#   ./experiment_compile.sh 1D_ocean_ice_column -j 8
#   ./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

set -e

# Check for help or no arguments before anything that depends on being run
# from inside a MITgcm checkout, so -h always works (even from a bare clone).
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean]"
    echo ""
    echo "Options:"
    echo "  -j <jobs>     Number of parallel make jobs (default: 4)"
    echo "                Examples: -j 1 (serial), -j 8 (fast), -j 16 (max)"
    echo "  -mpi          Compile with MPI support (auto-detects processes from SIZE.h_mpi)"
    echo "  -mods <dir>   Use custom code from specified directory (MUST be absolute path)"
    echo "  -build <dir>  Build directory name (default: build_docker)"
    echo "  -clean        Force clean build (otherwise uses incremental compilation)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Non-MPI, default -j 4, incremental"
    echo "  $0 1D_ocean_ice_column -j 8         # Non-MPI, fast, incremental"
    echo "  $0 1D_ocean_ice_column -clean -j 8  # Force full rebuild"
    echo "  $0 tutorial_global_oce_latlon -mpi -j 8  # MPI-enabled, incremental"
    echo "  $0 lab_sea -mods /full/path/to/code_validation -j 8  # Custom code, incremental"
    echo "  $0 lab_sea -mods /path/to/code -clean -j 8  # Custom code, force full rebuild"
    echo "  $0 lab_sea -build build_validation -j 8  # Custom build directory"
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>]"
    echo ""
    echo "Examples:"
    echo "  $0 lab_sea -j 8"
    echo "  $0 tutorial_global_oce_latlon -mpi -j 12"
    echo "  $0 lab_sea -mods ../code_validation -j 8"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Find MITgcm root (parent of verification directory)
if [ -f "$SCRIPT_DIR/../verification/.gitignore" ]; then
    # We're in a symlinked script in verification directory
    MITGCM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    # Fallback: look for MITgcm in parent directories
    MITGCM_ROOT=""
    SEARCH_DIR="$SCRIPT_DIR"
    for i in {1..5}; do
        if [ -d "$SEARCH_DIR/verification" ] && [ -d "$SEARCH_DIR/model" ]; then
            MITGCM_ROOT="$SEARCH_DIR"
            break
        fi
        SEARCH_DIR="$(dirname "$SEARCH_DIR")"
    done

    if [ -z "$MITGCM_ROOT" ]; then
        echo "Error: Cannot find MITgcm root directory"
        echo "Please run this script from MITgcm/verification/"
        exit 1
    fi
fi

VERIFICATION_DIR="$MITGCM_ROOT/verification"

# Function to extract MPI info from SIZE.h_mpi on host side
get_mpi_info_from_size_h() {
    local experiment_path="$1"
    local size_h_mpi="$experiment_path/code/SIZE.h_mpi"

    # Check if SIZE.h_mpi exists
    if [ ! -f "$size_h_mpi" ]; then
        echo "not_found"
        return
    fi

    # Parse Fortran PARAMETER format to extract nPx and nPy
    # Format: &           nPx =   2,  or  &           nPx=2,
    local npx=$(grep -i 'nPx' "$size_h_mpi" | grep -o '[0-9]\+' | head -1)
    local npy=$(grep -i 'nPy' "$size_h_mpi" | grep -o '[0-9]\+' | head -1)

    # Validate extracted values
    if [ -z "$npx" ] || [ -z "$npy" ]; then
        echo "not_found"
        return
    fi

    # Calculate total processes
    local total=$((npx * npy))
    echo "$npx:$npy:$total"
}

EXPERIMENT="$1"
MAKE_JOBS=4  # Default to 4 parallel jobs
USE_MPI=false
MODS_DIR=""
BUILD_DIR_NAME="build_docker"  # Default build directory name
CLEAN_BUILD=false  # Force clean build

# Parse remaining arguments
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        -j)
            MAKE_JOBS="$2"
            shift 2
            ;;
        -mpi)
            USE_MPI=true
            shift
            ;;
        -mods)
            MODS_DIR="$2"
            # Validate that -mods path is absolute
            if [[ "$MODS_DIR" != /* ]]; then
                echo "ERROR: -mods path must be an absolute path"
                echo "Provided: $MODS_DIR"
                echo ""
                echo "Example: -mods /full/path/to/code_validation"
                exit 1
            fi
            shift 2
            ;;
        -build)
            BUILD_DIR_NAME="$2"
            shift 2
            ;;
        -clean)
            CLEAN_BUILD=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean]"
            echo "Use -h or --help for more information"
            exit 1
            ;;
    esac
done

if [ ! -d "$VERIFICATION_DIR/$EXPERIMENT" ]; then
    echo "Error: Experiment directory '$EXPERIMENT' not found in $VERIFICATION_DIR"
    echo ""
    echo "Available experiments:"
    ls -d "$VERIFICATION_DIR"/*/ | grep -v "output_docker\|build_docker\|input_custom" | xargs -n 1 basename | head -20
    exit 1
fi

# Detect architecture for MPI path and optfile
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64)
        MPI_ARCH="aarch64-linux-gnu"
        OPTFILE="linux_arm64_gfortran"
        ;;
    x86_64|amd64)
        MPI_ARCH="x86_64-linux-gnu"
        OPTFILE="linux_amd64_gfortran"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: arm64, aarch64, x86_64, amd64"
        exit 1
        ;;
esac

echo "=========================================="
echo "Compiling MITgcm (NO RUN)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Arch:       $ARCH"
echo "  MPI:        $USE_MPI"
echo "  Make jobs:  -j $MAKE_JOBS"
if [ -n "$MODS_DIR" ]; then
echo "  Mods:       $MODS_DIR"
fi
echo "  MITgcm:     $MITGCM_ROOT"
echo "=========================================="
echo ""

# Create build directory on host
BUILD_DIR="$VERIFICATION_DIR/$EXPERIMENT/$BUILD_DIR_NAME"

# Clean build directory only when user explicitly requests -clean flag
# Otherwise keep it for incremental compilation (much faster for single file changes)
# Make's dependency tracking will detect changed files in mods directory by timestamp
if [ "$CLEAN_BUILD" = true ]; then
    if [ -d "$BUILD_DIR" ]; then
        echo "Cleaning build directory (user requested): $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
elif [ -d "$BUILD_DIR" ]; then
    echo "Using existing build directory for incremental compilation: $BUILD_DIR"
    echo "(Use -clean flag to force full rebuild)"
else
    echo "Creating build directory: $BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

echo "Mounting directories:"
echo "  MITgcm: $MITGCM_ROOT -> /mitgcm (read-write)"
echo "  Build:  $BUILD_DIR -> /build_output (read-write)"
echo ""

# Check for SIZE.h_mpi on host side (informational only)
if [ "$USE_MPI" = true ]; then
    MPI_INFO=$(get_mpi_info_from_size_h "$VERIFICATION_DIR/$EXPERIMENT")
    if [ "$MPI_INFO" != "not_found" ]; then
        NPX=$(echo "$MPI_INFO" | cut -d: -f1)
        NPY=$(echo "$MPI_INFO" | cut -d: -f2)
        TOTAL=$(echo "$MPI_INFO" | cut -d: -f3)
        echo "==> SIZE.h_mpi found: nPx=$NPX, nPy=$NPY ($TOTAL processes)"
    else
        echo "==> SIZE.h_mpi not found in code/ (testreport will use default SIZE.h)"
    fi
    echo ""
fi

# Copy SIZE.h_mpi to SIZE.h on HOST side when -mpi flag is used
if [ "$USE_MPI" = true ]; then
    if [ "$MPI_INFO" = "not_found" ]; then
        echo "ERROR: -mpi flag requires SIZE.h_mpi in $EXPERIMENT/code/"
        echo "       SIZE.h_mpi not found. Cannot proceed with MPI build."
        exit 1
    fi

    # Copy SIZE.h_mpi to SIZE.h on HOST side (for symlink resolution in build_docker)
    SIZE_H_MPI_SOURCE="$VERIFICATION_DIR/$EXPERIMENT/code/SIZE.h_mpi"
    SIZE_H_DEST="$VERIFICATION_DIR/$EXPERIMENT/code/SIZE.h"

    echo "==> Copying SIZE.h_mpi to SIZE.h in code directory..."
    if cp "$SIZE_H_MPI_SOURCE" "$SIZE_H_DEST"; then
        echo "    Copied: code/SIZE.h_mpi -> code/SIZE.h"
        echo ""
    else
        echo "ERROR: Failed to copy SIZE.h_mpi to SIZE.h"
        exit 1
    fi
fi

# Compile in Docker with MITgcm mounted from host
# Build docker command with mods mount if needed
if [ -n "$MODS_DIR" ]; then
    # MODS_DIR is guaranteed to be absolute (validated above)

    # Check if mods directory contains symlinks
    if find "$MODS_DIR" -maxdepth 1 -type l | grep -q .; then
        # Has symlinks - create temp directory with dereferenced files
        echo "  Mods:   $MODS_DIR (dereferencing symlinks)"
        TEMP_MODS_DIR="/tmp/mitgcm_mods_$$_$(basename "$MODS_DIR")"
        mkdir -p "$TEMP_MODS_DIR"
        # Use tar to copy and dereference symlinks
        (cd "$MODS_DIR" && tar ch .) | tar xC "$TEMP_MODS_DIR"
        echo "  Temp:   $TEMP_MODS_DIR -> /mods_dir"
        MODS_MOUNT_ARG="-v $TEMP_MODS_DIR:/mods_dir"
        CLEANUP_TEMP_MODS=true
    else
        echo "  Mods:   $MODS_DIR -> /mods_dir"
        MODS_MOUNT_ARG="-v $MODS_DIR:/mods_dir"
        CLEANUP_TEMP_MODS=false
    fi
else
    MODS_MOUNT_ARG=""
    CLEANUP_TEMP_MODS=false
fi

docker run --rm \
    -v "$MITGCM_ROOT:/mitgcm" \
    -v "$BUILD_DIR:/build_output" \
    $MODS_MOUNT_ARG \
    mitgcm:latest bash -c "
    set -e
    cd /mitgcm/verification

    # Set optfile path (now points to mounted MITgcm)
    export OPTFILE=/mitgcm/tools/build_options/$OPTFILE

    echo '==> Compiling experiment with -j $MAKE_JOBS...'

    # If -mods is specified, temporarily replace code/ directory with mods
    if [ -n \"$MODS_DIR\" ]; then
        echo 'Using custom code directory (temporarily replacing code/)'

        # Check for leftover code_orig from interrupted previous run
        if [ -d \"/mitgcm/verification/$EXPERIMENT/code_orig\" ]; then
            echo ''
            echo 'ERROR: Found leftover code_orig/ from previous interrupted run'
            echo '       This indicates the script was interrupted before cleanup.'
            echo ''
            echo 'To fix, manually restore the original code directory:'
            echo '  cd /mitgcm/verification/$EXPERIMENT'
            echo '  rm -rf code'
            echo '  mv code_orig code'
            echo ''
            exit 1
        fi

        # Backup original code directory
        if [ -d \"/mitgcm/verification/$EXPERIMENT/code\" ]; then
            echo '==> Backing up original code/ to code_orig/'
            mv \"/mitgcm/verification/$EXPERIMENT/code\" \"/mitgcm/verification/$EXPERIMENT/code_orig\"
        fi

        # Copy mods directory to code/ preserving timestamps for incremental compilation
        echo '==> Copying mods directory to code/ (preserving timestamps)'
        cp -rp /mods_dir \"/mitgcm/verification/$EXPERIMENT/code\"
    fi

    # Use testreport for compilation
    TESTREPORT_CMD=\"./testreport -t $EXPERIMENT -optfile \$OPTFILE -norun\"

    if [ \"$USE_MPI\" = true ]; then
        export MPI=true
        export MPI_INC_DIR=/usr/lib/$MPI_ARCH/openmpi/include
        export MPIINCLUDEDIR=/usr/lib/$MPI_ARCH/openmpi/include
        TESTREPORT_CMD=\"\$TESTREPORT_CMD -mpi\"
    fi

    TESTREPORT_CMD=\"\$TESTREPORT_CMD -j $MAKE_JOBS\"

    echo \"Running: \$TESTREPORT_CMD\"
    if ! eval \$TESTREPORT_CMD > /tmp/compile.log 2>&1; then
        # Restore original code directory before exiting on error
        if [ -n \"$MODS_DIR\" ] && [ -d \"/mitgcm/verification/$EXPERIMENT/code_orig\" ]; then
            rm -rf \"/mitgcm/verification/$EXPERIMENT/code\"
            mv \"/mitgcm/verification/$EXPERIMENT/code_orig\" \"/mitgcm/verification/$EXPERIMENT/code\"
        fi

        # Copy log to build directory before exiting
        cp /tmp/compile.log /build_output/compile.log
        echo 'ERROR: testreport command failed!'
        echo ''
        echo 'Last 50 lines of log:'
        tail -50 /tmp/compile.log
        echo ''
        echo 'Full log saved to: build_docker/compile.log'
        exit 1
    fi

    if [ ! -f $EXPERIMENT/build/mitgcmuv ]; then
        # Restore original code directory before exiting on error
        if [ -n \"$MODS_DIR\" ] && [ -d \"/mitgcm/verification/$EXPERIMENT/code_orig\" ]; then
            rm -rf \"/mitgcm/verification/$EXPERIMENT/code\"
            mv \"/mitgcm/verification/$EXPERIMENT/code_orig\" \"/mitgcm/verification/$EXPERIMENT/code\"
        fi

        # Copy log to build directory before exiting
        cp /tmp/compile.log /build_output/compile.log
        echo 'ERROR: Compilation failed - binary not created!'
        echo ''
        echo 'Last 50 lines of log:'
        tail -50 /tmp/compile.log
        echo ''
        echo 'Full log saved to: build_docker/compile.log'
        exit 1
    fi

    # After successful compilation, save mods as reference copy
    if [ -n \"$MODS_DIR\" ]; then
        echo '==> Saving mods directory as reference (code_validation/)'
        # Remove old reference copy if exists
        if [ -d \"/mitgcm/verification/$EXPERIMENT/code_validation\" ]; then
            rm -rf \"/mitgcm/verification/$EXPERIMENT/code_validation\"
        fi
        # Copy mods to reference location
        cp -rp /mods_dir \"/mitgcm/verification/$EXPERIMENT/code_validation\"
        echo '    Saved to: code_validation/'
    fi

    # Restore original code directory after successful compilation
    if [ -n \"$MODS_DIR\" ] && [ -d \"/mitgcm/verification/$EXPERIMENT/code_orig\" ]; then
        echo '==> Restoring original code/ directory'
        rm -rf \"/mitgcm/verification/$EXPERIMENT/code\"
        mv \"/mitgcm/verification/$EXPERIMENT/code_orig\" \"/mitgcm/verification/$EXPERIMENT/code\"
    fi

    # Save compilation log to build directory (works for both paths)
    cp /tmp/compile.log /build_output/compile.log
    echo '==> Compilation log saved to: build_docker/compile.log'
    echo ''
    echo '==> Compilation successful!'
    echo ''

    echo '==> Copying build files...'

    # Copy all build files to build directory (suppress symlink warnings)
    cp -r $EXPERIMENT/build/* /build_output/ 2>&1 | grep -v 'dangling symlink' || true

    # Ensure binary is in build directory
    cp $EXPERIMENT/build/mitgcmuv /build_output/mitgcmuv

    echo '✓ Binary saved to $BUILD_DIR_NAME/mitgcmuv'
    echo ''

    # Count build files
    BUILD_FILE_COUNT=\$(find /build_output -type f | wc -l)
    echo \"Copied \$BUILD_FILE_COUNT build files\"
    echo ''
    echo '==> Complete!'
"

echo ""
echo "=========================================="
echo "Compilation Complete!"
echo "=========================================="
echo ""
echo "Build directory: $BUILD_DIR"
ls -lh "$BUILD_DIR/mitgcmuv"
echo ""
echo "Compilation log: $BUILD_DIR/compile.log"
ls -lh "$BUILD_DIR/compile.log"
echo ""
echo "Build files: $(find "$BUILD_DIR" -type f | wc -l | tr -d ' ') files"
echo ""

# Show mods reference directory if used
if [ -n "$MODS_DIR" ]; then
    MODS_REF_DIR="$VERIFICATION_DIR/$EXPERIMENT/code_validation"
    if [ -d "$MODS_REF_DIR" ]; then
        echo "Modified code reference: $MODS_REF_DIR"
        echo "  Files: $(ls -1 "$MODS_REF_DIR" | tr '\n' ' ')"
        echo ""
    fi
fi

# Cleanup temp mods directory if created
if [ "$CLEANUP_TEMP_MODS" = true ] && [ -n "$TEMP_MODS_DIR" ] && [ -d "$TEMP_MODS_DIR" ]; then
    echo "Cleaning up temporary mods directory: $TEMP_MODS_DIR"
    rm -rf "$TEMP_MODS_DIR"
    echo ""
fi

echo "Next step: Run the model with"
if [ "$BUILD_DIR_NAME" != "build_docker" ]; then
    echo "  ./experiment_run_no_compile.sh $EXPERIMENT -build $BUILD_DIR_NAME"
else
    echo "  ./experiment_run_no_compile.sh $EXPERIMENT"
fi
echo ""

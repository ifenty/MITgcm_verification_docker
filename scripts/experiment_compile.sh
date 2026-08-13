#!/bin/bash
#
# Compile MITgcm verification experiment (NO RUN)
#
# Usage: ./experiment_compile.sh <experiment_name> [-j <jobs>] [-mpi]
#
# Options:
#   -j <jobs>   Number of parallel make jobs (default: 4)
#               Use -j 1 for serial build
#               Use -j 8 or -j 16 for faster builds on powerful machines
#   -mpi        Compile with MPI support (auto-detects processes from SIZE.h_mpi)
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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

# Check for help or no arguments
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi]"
    echo ""
    echo "Options:"
    echo "  -j <jobs>   Number of parallel make jobs (default: 4)"
    echo "              Examples: -j 1 (serial), -j 8 (fast), -j 16 (max)"
    echo "  -mpi        Compile with MPI support (auto-detects processes from SIZE.h_mpi)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Non-MPI, default -j 4"
    echo "  $0 1D_ocean_ice_column -j 8         # Non-MPI, fast"
    echo "  $0 tutorial_global_oce_latlon -mpi -j 8  # MPI-enabled"
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi]"
    echo ""
    echo "Examples:"
    echo "  $0 lab_sea -j 8"
    echo "  $0 tutorial_global_oce_latlon -mpi -j 12"
    exit 1
fi
EXPERIMENT="$1"
MAKE_JOBS=4  # Default to 4 parallel jobs
USE_MPI=false

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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi]"
            echo "Use -h or --help for more information"
            exit 1
            ;;
    esac
done

if [ ! -d "$SCRIPT_DIR/$EXPERIMENT" ]; then
    echo "Error: Experiment directory '$EXPERIMENT' not found in $SCRIPT_DIR"
    echo ""
    echo "Available experiments:"
    ls -d "$SCRIPT_DIR"/*/ | grep -v "output_docker\|build_docker\|input_custom" | xargs -n 1 basename
    exit 1
fi

# Detect architecture for MPI path
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
echo "Compiling MITgcm (NO RUN)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Arch:       $ARCH"
echo "  MPI:        $USE_MPI"
echo "  Make jobs:  -j $MAKE_JOBS"
echo "=========================================="
echo ""

# Create directories on host
BUILD_DIR="$SCRIPT_DIR/$EXPERIMENT/build_docker"
OUTPUT_DIR="$SCRIPT_DIR/$EXPERIMENT/output_docker"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Mounting directories:"
echo "  Build:  $EXPERIMENT/build_docker/"
echo "  Output: $EXPERIMENT/output_docker/"
echo ""

# Check for SIZE.h_mpi on host side (informational only)
if [ "$USE_MPI" = true ]; then
    MPI_INFO=$(get_mpi_info_from_size_h "$SCRIPT_DIR/$EXPERIMENT")
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
    SIZE_H_MPI_SOURCE="$SCRIPT_DIR/$EXPERIMENT/code/SIZE.h_mpi"
    SIZE_H_DEST="$SCRIPT_DIR/$EXPERIMENT/code/SIZE.h"

    echo "==> Copying SIZE.h_mpi to SIZE.h in code directory..."
    if cp "$SIZE_H_MPI_SOURCE" "$SIZE_H_DEST"; then
        echo "    Copied: code/SIZE.h_mpi -> code/SIZE.h"
        echo ""
    else
        echo "ERROR: Failed to copy SIZE.h_mpi to SIZE.h"
        exit 1
    fi
fi

# Compile in Docker using testreport (which works around assembler issues)
docker run --rm \
    -v "$BUILD_DIR:/build_output" \
    -v "$OUTPUT_DIR:/output" \
    mitgcm:latest bash -c "
    set -e
    cd /home/mitgcm/MITgcm/verification

    # Copy SIZE.h_mpi to SIZE.h in experiment's code/ dir BEFORE testreport runs
    if [ \"$USE_MPI\" = true ]; then
        if [ -f \"$EXPERIMENT/code/SIZE.h_mpi\" ]; then
            echo '==> Copying SIZE.h_mpi to SIZE.h in experiment code directory...'
            cp \"$EXPERIMENT/code/SIZE.h_mpi\" \"$EXPERIMENT/code/SIZE.h\"
            echo '    Copied: code/SIZE.h_mpi -> code/SIZE.h'
            echo ''
        else
            echo 'ERROR: SIZE.h_mpi not found in experiment code directory'
            exit 1
        fi
    fi

    echo '==> Compiling experiment with -j $MAKE_JOBS...'

    # Set MPI environment variables and use -mpi flag if MPI build
    # SIZE.h_mpi has already been copied to SIZE.h above, so testreport will use it
    if [ \"$USE_MPI\" = true ]; then
        export MPI=true
        export MPI_INC_DIR=/usr/lib/$MPI_ARCH/openmpi/include
        export MPIINCLUDEDIR=/usr/lib/$MPI_ARCH/openmpi/include
        if ! ./testreport -t $EXPERIMENT -optfile \$OPTFILE -mpi -j $MAKE_JOBS > /tmp/testreport.log 2>&1; then
            echo 'ERROR: testreport command failed!'
            echo ''
            echo 'Last 50 lines of testreport log:'
            tail -50 /tmp/testreport.log
            exit 1
        fi
    else
        if ! ./testreport -t $EXPERIMENT -optfile \$OPTFILE -j $MAKE_JOBS > /tmp/testreport.log 2>&1; then
            echo 'ERROR: testreport command failed!'
            echo ''
            echo 'Last 50 lines of testreport log:'
            tail -50 /tmp/testreport.log
            exit 1
        fi
    fi

    if [ ! -f $EXPERIMENT/build/mitgcmuv ]; then
        echo 'ERROR: Compilation failed - binary not created!'
        echo ''
        echo 'Last 50 lines of testreport log:'
        tail -50 /tmp/testreport.log
        exit 1
    fi

    echo '==> Compilation successful!'
    echo ''
    echo '==> Copying build files...'

    # Copy all build files to build_docker (suppress symlink warnings)
    cp -r $EXPERIMENT/build/* /build_output/ 2>&1 | grep -v 'dangling symlink' || true

    # Ensure binary is in both locations
    cp $EXPERIMENT/build/mitgcmuv /build_output/mitgcmuv
    cp $EXPERIMENT/build/mitgcmuv /output/mitgcmuv

    echo '✓ Binary saved to build_docker/mitgcmuv'
    echo '✓ Binary saved to output_docker/mitgcmuv'
    echo ''

    # Count and report files
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
ls -lh "$BUILD_DIR/mitgcmuv" 2>&1
echo ""
echo "Binary also copied to: $OUTPUT_DIR/mitgcmuv"
ls -lh "$OUTPUT_DIR/mitgcmuv" 2>&1
echo ""
echo "Build files: $(find "$BUILD_DIR" -type f | wc -l | tr -d ' ') files"
echo ""
echo "Next step: Run the model with"
if [ "$USE_MPI" = "true" ]; then
    if [ "$MPI_INFO" != "not_found" ]; then
        NPROCS=${MPI_INFO##*:}
        echo "  ./experiment_run_no_compile.sh $EXPERIMENT -mpi $NPROCS"
    else
        echo "  ./experiment_run_no_compile.sh $EXPERIMENT -mpi"
    fi
else
    echo "  ./experiment_run_no_compile.sh $EXPERIMENT"
fi
echo ""

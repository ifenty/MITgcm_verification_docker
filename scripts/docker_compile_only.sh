#!/bin/bash
#
# Compile MITgcm verification experiment (NO RUN)
#
# Usage: ./docker_compile_only.sh <experiment_name> [-j <jobs>]
#
# Options:
#   -j <jobs>   Number of parallel make jobs (default: 4)
#               Use -j 1 for serial build
#               Use -j 8 or -j 16 for faster builds on powerful machines
#
# Output:
#   - Build files saved to: <experiment>/build_docker/
#   - Binary saved to both:
#       <experiment>/build_docker/mitgcmuv
#       <experiment>/output_docker/mitgcmuv
#
# Examples:
#   ./docker_compile_only.sh 1D_ocean_ice_column
#   ./docker_compile_only.sh 1D_ocean_ice_column -j 8
#   ./docker_compile_only.sh 1D_ocean_ice_column -j 1  # serial

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check for help first
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi]"
    echo ""
    echo "Options:"
    echo "  -j <jobs>   Number of parallel make jobs (default: 4)"
    echo "              Examples: -j 1 (serial), -j 8 (fast), -j 16 (max)"
    echo "  -mpi        Use MPI-enabled build (requires MPI optfile)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Non-MPI, default -j 4"
    echo "  $0 1D_ocean_ice_column -j 8         # Non-MPI, fast"
    echo "  $0 tutorial_global_oce_latlon -mpi -j 8  # MPI-enabled"
    echo ""
    exit 0
fi

EXPERIMENT="${1:-1D_ocean_ice_column}"
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

# Determine optfile (ARM64 optfile handles MPI via environment variable, not separate file)
OPTFILE="linux_arm64_gfortran"

echo "=========================================="
echo "Compiling MITgcm (NO RUN)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Build opt:  $OPTFILE"
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

# Compile in Docker using testreport (which works around assembler issues)
docker run --rm \
    -v "$BUILD_DIR:/build_output" \
    -v "$OUTPUT_DIR:/output" \
    mitgcm:latest bash -c "
    set -e
    cd /home/mitgcm/MITgcm/verification

    echo '==> Running testreport to compile with -j $MAKE_JOBS...'

    # Build testreport command with optional MPI flag
    TESTREPORT_CMD=\"./testreport -t $EXPERIMENT -optfile ../tools/build_options/$OPTFILE -j $MAKE_JOBS\"

    if [ \"$USE_MPI\" = true ]; then
        export MPI_INC_DIR=/usr/lib/aarch64-linux-gnu/openmpi/include
        TESTREPORT_CMD=\"\$TESTREPORT_CMD -mpi\"
        echo '==> MPI enabled: using testreport -mpi flag'
        echo '==> MPI_INC_DIR='\$MPI_INC_DIR
    fi

    \$TESTREPORT_CMD > /tmp/testreport.log 2>&1

    if [ ! -f $EXPERIMENT/build/mitgcmuv ]; then
        echo 'ERROR: Compilation failed!'
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
echo "  ./run_no_compile.sh $EXPERIMENT"
echo ""

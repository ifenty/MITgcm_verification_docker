#!/bin/bash
#
# Run MITgcm using existing compiled binary (NO COMPILATION)
#
# Usage: ./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N] [-output <dir>]
#
# Options:
#   input_dir    Input directory (default: input)
#   -mpi N       Run with MPI using N processes
#   -output <dir> Output directory name.  Contains the compiled mitgcmuv binary (default: output_docker)
#
# Prerequisites: Must have mitgcmuv binary in output directory

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Find MITgcm root (parent of verification directory)
if [ -f "$SCRIPT_DIR/../verification/.gitignore" ]; then
    MITGCM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
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

# Check for help or no arguments
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-output <dir>]"
    echo ""
    echo "Options:"
    echo "  input_dir    Input directory (default: input)"
    echo "               Examples: input, input.seaice, input_ad"
    echo "  -mpi N       Run with MPI using N processes"
    echo "  -output <dir> Output directory name (default: output_docker)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Use default input and output dirs"
    echo "  $0 1D_ocean_ice_column input.seaice # Custom input dir"
    echo "  $0 lab_sea input -output output_validation  # Custom output dir"
    echo "  $0 tutorial_global_oce_latlon input -mpi 2  # MPI with 2 procs"
    echo ""
    echo "Prerequisites:"
    echo "  Must have mitgcmuv binary in output directory"
    echo "  Run experiment_compile.sh first if needed"
    echo "  Use same -output flag as used during compilation"
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-output <dir>]"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 lab_sea -output output_validation"
    echo "  $0 tutorial_global_oce_latlon input -mpi 2"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

EXPERIMENT="$1"
INPUT_DIR="input"
OUTPUT_DIR_NAME="output_docker"
USE_MPI=false
MPI_PROCS=1

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        -mpi)
            USE_MPI=true
            MPI_PROCS="${2:-1}"
            shift 2
            ;;
        -output)
            OUTPUT_DIR_NAME="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-output <dir>]"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
        *)
            # First non-flag argument is input_dir
            INPUT_DIR="$1"
            shift
            ;;
    esac
done

if [ ! -d "$VERIFICATION_DIR/$EXPERIMENT/$INPUT_DIR" ]; then
    echo "Error: Input directory not found: $VERIFICATION_DIR/$EXPERIMENT/$INPUT_DIR"
    echo ""
    echo "Available input directories for $EXPERIMENT:"
    ls -d "$VERIFICATION_DIR/$EXPERIMENT"/input* 2>/dev/null | xargs -n 1 basename || echo "  (none found)"
    exit 1
fi

OUTPUT_DIR="$VERIFICATION_DIR/$EXPERIMENT/$OUTPUT_DIR_NAME"
if [ ! -f "$OUTPUT_DIR/mitgcmuv" ]; then
    echo "Error: Binary not found at $OUTPUT_DIR/mitgcmuv"
    echo ""
    echo "Please compile first:"
    echo "  ./experiment_compile.sh $EXPERIMENT [-output $OUTPUT_DIR_NAME] [-j N] [-mpi]"
    echo ""
    echo "Or if using a different output directory, specify it:"
    echo "  $0 $EXPERIMENT -output <directory_name>"
    exit 1
fi

echo "=========================================="
echo "Running MITgcm (NO COMPILATION)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Input:      $INPUT_DIR"
echo "  Binary:     $(ls -lh "$OUTPUT_DIR/mitgcmuv" | awk '{print $5}')"
echo "  MPI:        $USE_MPI"
if [ "$USE_MPI" = true ]; then
    echo "  Processes:  $MPI_PROCS"
fi
echo "  Output:     $OUTPUT_DIR_NAME/"
echo "  MITgcm:     $MITGCM_ROOT"
echo "=========================================="
echo ""

# Run in Docker with MITgcm mounted from host
docker run --rm \
    -v "$MITGCM_ROOT:/mitgcm" \
    -v "$OUTPUT_DIR:/output" \
    mitgcm:latest bash -c "
    set -e
    cd /output

    echo 'Linking input files...'
    ln -sf /mitgcm/verification/$EXPERIMENT/$INPUT_DIR/* . 2>/dev/null || true

    echo 'Running model...'
    if [ \"$USE_MPI\" = true ]; then
        mpirun --allow-run-as-root -np $MPI_PROCS ./mitgcmuv
    else
        ./mitgcmuv
    fi

    echo ''
    echo 'Copying outputs...'
    # Outputs are already in /output (mounted), nothing to copy

    echo ''
    echo 'Complete!'
"

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR" | grep -v "^d" | grep -v "^total" | grep -v "mitgcmuv" | awk '{printf "  %-30s %8s\n", $9, $5}'
echo ""
echo "View output: less $OUTPUT_DIR/output.txt"
echo ""

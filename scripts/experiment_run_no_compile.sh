#!/bin/bash
#
# Run MITgcm using existing compiled binary (NO COMPILATION)
#
# Usage: ./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N]
#
# Options:
#   input_dir    Input directory (default: input)
#   -mpi N       Run with MPI using N processes
#
# Prerequisites: Must have mitgcmuv binary in output_docker/

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check for help first
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N]"
    echo ""
    echo "Options:"
    echo "  input_dir    Input directory (default: input)"
    echo "               Examples: input, input.seaice, input_ad"
    echo "  -mpi N       Run with MPI using N processes (default: 4)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Use default input dir"
    echo "  $0 1D_ocean_ice_column input.seaice # Custom input dir"
    echo "  $0 tutorial_global_oce_latlon input -mpi 8  # MPI with 8 procs"
    echo ""
    echo "Prerequisites:"
    echo "  Must have mitgcmuv binary in output_docker/"
    echo "  Run experiment_compile.sh first if needed"
    echo ""
    exit 0
fi

if [ -z "$1" ] || [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N]"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 tutorial_global_oce_latlon input -mpi 8"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

EXPERIMENT="$1"
INPUT_DIR="${2:-input}"
USE_MPI=false
MPI_PROCS=1

# Parse optional MPI argument
shift 2 2>/dev/null || shift $# 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        -mpi)
            USE_MPI=true
            MPI_PROCS="${2:-4}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [input_dir] [-mpi N]"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
    esac
done

if [ ! -d "$SCRIPT_DIR/$EXPERIMENT/$INPUT_DIR" ]; then
    echo "Error: Input directory not found: $SCRIPT_DIR/$EXPERIMENT/$INPUT_DIR"
    exit 1
fi

OUTPUT_DIR="$SCRIPT_DIR/$EXPERIMENT/output_docker"
mkdir -p "$OUTPUT_DIR"

BINARY="$OUTPUT_DIR/mitgcmuv"
if [ ! -f "$BINARY" ]; then
    echo "=========================================="
    echo "ERROR: Binary not found!"
    echo "=========================================="
    echo ""
    echo "Binary not found at: $BINARY"
    echo ""
    echo "You must compile once first. Run:"
    echo "  ./experiment_compile.sh $EXPERIMENT"
    echo ""
    exit 1
fi

echo "=========================================="
echo "Running MITgcm (NO COMPILATION)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Input:      $INPUT_DIR"
echo "  Binary:     $(du -h $BINARY | awk '{print $1}')"
echo "  MPI:        $USE_MPI"
if [ "$USE_MPI" = true ]; then
    echo "  Processes:  $MPI_PROCS"
fi
echo "  Output:     output_docker/"
echo "=========================================="
echo ""

docker run --rm \
    -v "$SCRIPT_DIR/$EXPERIMENT/$INPUT_DIR:/input:ro" \
    -v "$OUTPUT_DIR:/output" \
    -w /home/mitgcm \
    mitgcm:latest bash -c "
    set -e
    mkdir -p work
    cd work

    echo 'Linking input files...'
    for f in /input/*; do
        fname=\$(basename \$f)
        if [ -f \"\$f\" ]; then
            ln -sf \$f \$fname
        fi
    done

    echo 'Running model...'
    cp /output/mitgcmuv .
    chmod +x mitgcmuv

    if [ \"$USE_MPI\" = true ]; then
        echo 'Using MPI with $MPI_PROCS processes'
        mpirun --allow-run-as-root -np $MPI_PROCS ./mitgcmuv | tee /output/output.txt
    else
        ./mitgcmuv | tee /output/output.txt
    fi

    echo ''
    echo 'Copying outputs...'
    for pattern in '*.data' '*.meta' 'STD*' 'STDERR.*' '*.nc'; do
        cp \$pattern /output/ 2>/dev/null || true
    done

    echo ''
    echo 'Complete!'
"

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "Output files:"
ls -lht "$OUTPUT_DIR" | head -10 | awk 'NR>1 {printf "  %-25s %10s\n", $9, $5}'
echo ""
echo "View output: less $OUTPUT_DIR/output.txt"
echo ""

#!/bin/bash
#
# Run MITgcm using existing compiled binary (NO COMPILATION)
#
# Usage: ./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N] [-build <dir>] [-output <dir>] [-adm | -tlm]
#
# Options:
#   input_dir      Input directory (default: input, or input_ad with -adm/-tlm)
#   -mpi N         Run with MPI using N processes (must match the MPI build)
#   -build <dir>   Build directory holding the compiled binary (default: build_docker,
#                  or build_docker_adm / build_docker_tlm)
#   -output <dir>  Output (run) directory name (default: output_docker, or
#                  output_docker_adm / output_docker_tlm)
#   -adm           Run the TAF adjoint binary (mitgcmuv_ad) built with experiment_compile.sh -adm
#   -tlm           Run the TAF tangent-linear binary (mitgcmuv_ftl) built with -tlm
#
# Input files are staged the same way MITgcm's testreport does it:
#   - files from input_dir are linked into the output directory; for
#     input.<X>, files missing from input.<X> are taken from input/
#     (input_ad.<X> is layered on input_ad/ the same way)
#   - for MPI runs, <file>.mpi variants replace <file>
#   - an input_dir/prepare_run script, if present, is run in the output directory
# Symlinks and STDOUT/STDERR files left in the output directory by a previous
# run are removed first, so a new run never silently reuses an old input.
#
# Exit status is non-zero if the model does not end with
# "Execution ended Normally".
#
# Prerequisites: the binary in the build directory (run experiment_compile.sh first)

set -e

# Check for help or no arguments before anything that depends on being run
# from inside a MITgcm checkout, so -h always works (even from a bare clone).
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-build <dir>] [-output <dir>] [-adm | -tlm]"
    echo ""
    echo "Options:"
    echo "  input_dir     Input directory (default: input; input_ad with -adm/-tlm)"
    echo "                Examples: input, input.nlfs, input_custom, input_ad.som81"
    echo "                (input.<X> is layered on top of input/, and input_ad.<X> on top"
    echo "                of input_ad/, as testreport does)"
    echo "  -mpi N        Run with MPI using N processes (must equal the process"
    echo "                count the binary was compiled for; shown by experiment_compile.sh)"
    echo "  -build <dir>  Build directory name where binary is located (default: build_docker;"
    echo "                build_docker_adm / build_docker_tlm with -adm / -tlm)"
    echo "  -output <dir> Output directory name for model outputs (default: output_docker;"
    echo "                output_docker_adm / output_docker_tlm with -adm / -tlm)"
    echo "  -adm          Run the TAF adjoint (mitgcmuv_ad from experiment_compile.sh -adm)"
    echo "  -tlm          Run the TAF tangent linear (mitgcmuv_ftl from experiment_compile.sh -tlm)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column                       # Use defaults"
    echo "  $0 adjustment.cs-32x32x1 input.nlfs          # Secondary input dir"
    echo "  $0 lab_sea -output output_validation         # Custom output dir"
    echo "  $0 lab_sea -build build_validation -output output_validation  # Custom dirs"
    echo "  $0 tutorial_barotropic_gyre -mpi 4           # MPI with 4 procs"
    echo "  $0 1D_ocean_ice_column -adm                  # TAF adjoint, input_ad/"
    echo "  $0 tutorial_tracer_adjsens input_ad.som81 -tlm   # TLM, secondary input"
    echo ""
    echo "Prerequisites:"
    echo "  Must have the binary (mitgcmuv, mitgcmuv_ad or mitgcmuv_ftl) in build directory"
    echo "  Run experiment_compile.sh first if needed"
    echo "  Use same -build flag as used during compilation"
    echo ""
    echo "Exit status is non-zero if the model does not end normally."
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-build <dir>] [-output <dir>] [-adm | -tlm]"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 lab_sea -output output_validation"
    echo "  $0 tutorial_barotropic_gyre -mpi 4"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

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

EXPERIMENT="$1"
INPUT_DIR=""        # defaults depend on the kind of run (set after parsing)
OUTPUT_DIR_NAME=""
BUILD_DIR_NAME=""
KIND=forward        # forward | adm | tlm
USE_MPI=false
MPI_PROCS=1

# Require a value after an option; $1 = option name, $2 = value
require_value() {
    if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: $1 requires a value"
        echo "Try '$0 --help' for more information"
        exit 1
    fi
}

# Directory-name options must be plain names inside the experiment directory
require_simple_name() {
    if [[ "$2" == */* || "$2" == "." || "$2" == ".." ]]; then
        echo "Error: $1 must be a directory name inside the experiment (no '/'): $2"
        exit 1
    fi
}

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        -mpi)
            if [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: -mpi requires a process count (positive integer), got: '${2}'"
                echo "Try '$0 --help' for more information"
                exit 1
            fi
            USE_MPI=true
            MPI_PROCS="$2"
            shift 2
            ;;
        -output)
            require_value -output "$2"
            require_simple_name -output "$2"
            OUTPUT_DIR_NAME="$2"
            shift 2
            ;;
        -build)
            require_value -build "$2"
            require_simple_name -build "$2"
            BUILD_DIR_NAME="$2"
            shift 2
            ;;
        -adm|-tlm)
            if [ "$KIND" != forward ] && [ "$KIND" != "${1#-}" ]; then
                echo "Error: -adm and -tlm cannot be combined"
                exit 1
            fi
            KIND="${1#-}"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [input_dir] [-mpi N] [-build <dir>] [-output <dir>] [-adm | -tlm]"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
        *)
            # First non-flag argument is input_dir
            require_simple_name input_dir "$1"
            INPUT_DIR="$1"
            shift
            ;;
    esac
done

case "$KIND" in
    forward) BINARY=mitgcmuv;     BASE_INPUT=input;    SUFFIX="" ;;
    adm)     BINARY=mitgcmuv_ad;  BASE_INPUT=input_ad; SUFFIX="_adm" ;;
    tlm)     BINARY=mitgcmuv_ftl; BASE_INPUT=input_ad; SUFFIX="_tlm" ;;
esac
DEFAULT_BUILD_DIR_NAME="build_docker$SUFFIX"
[ -z "$INPUT_DIR" ] && INPUT_DIR="$BASE_INPUT"
[ -z "$BUILD_DIR_NAME" ] && BUILD_DIR_NAME="$DEFAULT_BUILD_DIR_NAME"
[ -z "$OUTPUT_DIR_NAME" ] && OUTPUT_DIR_NAME="output_docker$SUFFIX"
KIND_ARG=""
[ "$KIND" != forward ] && KIND_ARG=" -$KIND"

EXP_DIR="$VERIFICATION_DIR/$EXPERIMENT"

if [ ! -d "$EXP_DIR/$INPUT_DIR" ]; then
    echo "Error: Input directory not found: $EXP_DIR/$INPUT_DIR"
    echo ""
    echo "Available input directories for $EXPERIMENT:"
    found_inputs=$(ls -d "$EXP_DIR"/input* 2>/dev/null || true)
    if [ -n "$found_inputs" ]; then
        for d in $found_inputs; do echo "  $(basename "$d")"; done
    else
        echo "  (none found)"
    fi
    exit 1
fi

BUILD_DIR="$EXP_DIR/$BUILD_DIR_NAME"
OUTPUT_DIR="$EXP_DIR/$OUTPUT_DIR_NAME"

if [ ! -f "$BUILD_DIR/$BINARY" ]; then
    echo "Error: Binary not found at $BUILD_DIR/$BINARY"
    echo ""
    # A binary of another kind in this build dir means the -adm/-tlm flag is off
    for other in mitgcmuv mitgcmuv_ad mitgcmuv_ftl; do
        [ "$other" = "$BINARY" ] && continue
        if [ -f "$BUILD_DIR/$other" ]; then
            case "$other" in
                mitgcmuv)     hint="(no -adm/-tlm)" ;;
                mitgcmuv_ad)  hint="-adm" ;;
                mitgcmuv_ftl) hint="-tlm" ;;
            esac
            echo "$BUILD_DIR_NAME holds $other instead; run with $hint to use it."
            echo ""
        fi
    done
    TAF_HINT=""
    [ "$KIND" != forward ] && TAF_HINT=" -taf_dir /path/to/TAF"
    echo "Please compile first:"
    if [ "$BUILD_DIR_NAME" != "$DEFAULT_BUILD_DIR_NAME" ]; then
        echo "  ./experiment_compile.sh $EXPERIMENT$KIND_ARG$TAF_HINT -build $BUILD_DIR_NAME [-j N] [-mpi]"
    else
        echo "  ./experiment_compile.sh $EXPERIMENT$KIND_ARG$TAF_HINT [-j N] [-mpi]"
    fi
    exit 1
fi

# Check the requested MPI layout against what the binary was built for
# (build_info.txt is written by experiment_compile.sh)
if [ -f "$BUILD_DIR/build_info.txt" ]; then
    BUILT_MPI="$(sed -n 's/^MPI=//p' "$BUILD_DIR/build_info.txt")"
    BUILT_NPROCS="$(sed -n 's/^NPROCS=//p' "$BUILD_DIR/build_info.txt")"
    BUILT_KIND="$(sed -n 's/^KIND=//p' "$BUILD_DIR/build_info.txt")"
    if [ "${BUILT_KIND:-forward}" != "$KIND" ]; then
        echo "Error: $BUILD_DIR_NAME was compiled as a '${BUILT_KIND:-forward}' build, not '$KIND'."
        exit 1
    fi
    if [ "$BUILT_MPI" = "true" ] && [ "$USE_MPI" != true ]; then
        echo "Error: $BUILD_DIR_NAME/$BINARY was compiled with MPI for $BUILT_NPROCS processes."
        echo "Run it with:  $0 $EXPERIMENT$KIND_ARG -mpi $BUILT_NPROCS"
        exit 1
    fi
    if [ "$BUILT_MPI" != "true" ] && [ "$USE_MPI" = true ]; then
        echo "Error: $BUILD_DIR_NAME/$BINARY was compiled without MPI; -mpi $MPI_PROCS cannot be used."
        echo "Recompile with:  ./experiment_compile.sh $EXPERIMENT$KIND_ARG -mpi"
        exit 1
    fi
    if [ "$USE_MPI" = true ] && [ -n "$BUILT_NPROCS" ] && [ "$MPI_PROCS" != "$BUILT_NPROCS" ]; then
        echo "Error: -mpi $MPI_PROCS does not match the build, which was compiled for $BUILT_NPROCS processes."
        echo "Run it with:  $0 $EXPERIMENT$KIND_ARG -mpi $BUILT_NPROCS"
        exit 1
    fi
fi

# Input directories in priority order (testreport: input.<X> first, then
# input; likewise input_ad.<X>, then input_ad)
INPUT_DIRS=("$INPUT_DIR")
for base in input input_ad; do
    if [[ "$INPUT_DIR" == "$base".* ]] && [ -d "$EXP_DIR/$base" ]; then
        INPUT_DIRS+=("$base")
    fi
done

mkdir -p "$OUTPUT_DIR"

# Clear what a previous run left behind that would otherwise leak into this
# run: input symlinks (possibly from a different input dir) and stdout files.
find "$OUTPUT_DIR" -maxdepth 1 -type l -delete
rm -f "$OUTPUT_DIR"/output.txt "$OUTPUT_DIR"/mpirun.log "$OUTPUT_DIR"/STDOUT.* "$OUTPUT_DIR"/STDERR.*

# Link input files with relative links (valid both on the host and in the
# container, and the layout prepare_run scripts expect)
for dir in "${INPUT_DIRS[@]}"; do
    for src in "$EXP_DIR/$dir"/*; do
        [ -e "$src" ] || continue
        [ -d "$src" ] && continue
        name="$(basename "$src")"
        [ "$name" = "CVS" ] && continue
        if [ ! -e "$OUTPUT_DIR/$name" ] && [ ! -L "$OUTPUT_DIR/$name" ]; then
            ln -s "../$dir/$name" "$OUTPUT_DIR/$name"
        fi
    done
done

# MPI runs: <file>.mpi from the first input dir replaces <file>
if [ "$USE_MPI" = true ]; then
    for src in "$EXP_DIR/$INPUT_DIR"/*.mpi; do
        [ -e "$src" ] || continue
        name="$(basename "$src" .mpi)"
        if [ -L "$OUTPUT_DIR/$name" ] || [ ! -e "$OUTPUT_DIR/$name" ]; then
            rm -f "$OUTPUT_DIR/$name"
            ln -s "../$INPUT_DIR/$name.mpi" "$OUTPUT_DIR/$name"
        fi
    done
fi

# Copy binary from build directory to output directory
echo "Copying binary from $BUILD_DIR_NAME to $OUTPUT_DIR_NAME..."
rm -f "$OUTPUT_DIR/mitgcmuv" "$OUTPUT_DIR/mitgcmuv_ad" "$OUTPUT_DIR/mitgcmuv_ftl"
cp "$BUILD_DIR/$BINARY" "$OUTPUT_DIR/$BINARY"

# Record what produced this output (read by compare_results.sh)
cat > "$OUTPUT_DIR/run_info.txt" <<EOF
EXPERIMENT=$EXPERIMENT
KIND=$KIND
INPUT_DIR=$INPUT_DIR
BUILD_DIR=$BUILD_DIR_NAME
MPI=$USE_MPI
NPROCS=$MPI_PROCS
EOF

echo "=========================================="
echo "Running MITgcm (NO COMPILATION)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
if [ "$KIND" = adm ]; then
echo "  Kind:       adjoint (TAF)"
elif [ "$KIND" = tlm ]; then
echo "  Kind:       tangent linear (TAF)"
fi
echo "  Build:      $BUILD_DIR_NAME"
echo "  Input:      ${INPUT_DIRS[*]}"
echo "  Binary:     $BINARY ($(ls -lh "$OUTPUT_DIR/$BINARY" | awk '{print $5}'))"
echo "  MPI:        $USE_MPI"
if [ "$USE_MPI" = true ]; then
    echo "  Processes:  $MPI_PROCS"
fi
echo "  Output:     $OUTPUT_DIR_NAME/"
echo "  MITgcm:     $MITGCM_ROOT"
echo "=========================================="
echo ""

# Run in Docker with MITgcm mounted from host. The run directory lives inside
# the mounted tree, so relative paths used by prepare_run scripts resolve.
RUN_RC=0
docker run --rm \
    -v "$MITGCM_ROOT:/mitgcm" \
    -w "/mitgcm/verification/$EXPERIMENT/$OUTPUT_DIR_NAME" \
    mitgcm:latest bash -c "
    if [ -x prepare_run ]; then
        echo 'Running prepare_run...'
        ./prepare_run
    fi

    echo 'Running model...'
    if [ \"$USE_MPI\" = true ]; then
        mpirun --oversubscribe -np $MPI_PROCS ./$BINARY > mpirun.log 2>&1
    else
        ./$BINARY > output.txt 2>&1
    fi
" || RUN_RC=$?

# MPI runs write the model log to STDOUT.0000; keep a copy as output.txt so
# every run has its log in the same place.
if [ "$USE_MPI" = true ] && [ -f "$OUTPUT_DIR/STDOUT.0000" ]; then
    cp "$OUTPUT_DIR/STDOUT.0000" "$OUTPUT_DIR/output.txt"
fi

echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR" | grep -v "^d" | grep -v "^total" | grep -v "mitgcmuv" | grep -v "^l" | awk '{printf "  %-30s %8s\n", $9, $5}'
echo ""
echo "Model STDOUT saved to: $OUTPUT_DIR/output.txt"
echo "View output: less $OUTPUT_DIR/output.txt"
echo ""
if grep -q "===== KPP_VALIDATION_START" "$OUTPUT_DIR/output.txt" 2>/dev/null; then
    KPP_COUNT=$(grep -c "===== KPP_VALIDATION_START" "$OUTPUT_DIR/output.txt")
    echo "✓ KPP validation output detected ($KPP_COUNT timesteps)"
    echo ""
fi

# MITgcm stops with exit status 0 even on errors, so the log is the
# authoritative success signal.
if grep -q "Execution ended Normally" "$OUTPUT_DIR/output.txt" 2>/dev/null; then
    echo "=========================================="
    echo "Done! Model ended normally."
    echo "=========================================="
    echo ""
    exit 0
fi

echo "=========================================="
echo "ERROR: Model did not end normally"
echo "=========================================="
[ "$RUN_RC" -ne 0 ] && echo "  (run command exit status: $RUN_RC)"
echo ""
echo "Last lines of output.txt:"
tail -15 "$OUTPUT_DIR/output.txt" 2>/dev/null | sed 's/^/  /' || echo "  (no output.txt)"
if [ -f "$OUTPUT_DIR/mpirun.log" ] && [ -s "$OUTPUT_DIR/mpirun.log" ]; then
    echo ""
    echo "Last lines of mpirun.log:"
    tail -10 "$OUTPUT_DIR/mpirun.log" | sed 's/^/  /'
fi
echo ""
exit 1

#!/bin/bash
#
# Compile MITgcm verification experiment (NO RUN)
#
# Usage: ./experiment_compile.sh <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean]
#                                  [-adm | -tlm] [-taf_dir <path>]
#
# Options:
#   -j <jobs>     Number of parallel make jobs (default: 4)
#   -mpi          Compile with MPI support for nPx*nPy processes, read from
#                 the experiment's code/SIZE.h_mpi (code_ad/ with -adm/-tlm)
#   -mods <dir>   Use this code directory INSTEAD of the experiment's code/
#                 (code_ad/ with -adm/-tlm; MUST be an absolute path to an
#                 existing directory)
#   -build <dir>  Build directory name (default: build_docker, or
#                 build_docker_adm / build_docker_tlm)
#   -clean        Delete the host-side build directory before compiling
#   -adm          Build the TAF adjoint (make adall -> mitgcmuv_ad) from code_ad/
#   -tlm          Build the TAF tangent linear (make ftlall -> mitgcmuv_ftl) from code_ad/
#   -taf_dir <p>  TAF installation holding 'staf' (absolute path; required with
#                 -adm/-tlm unless $TAF_DIR is set). ~/.ssh is mounted read-only
#                 for the TAF server key.
#
# Every compile is a full rebuild: MITgcm's testreport (used here) always
# runs "make Clean" in <experiment>/build before building.
#
# Output:
#   - Build files and the binary are copied to <experiment>/<build-dir>/
#   - <experiment>/<build-dir>/build_info.txt records MPI and process count
#
# Examples:
#   ./experiment_compile.sh 1D_ocean_ice_column
#   ./experiment_compile.sh 1D_ocean_ice_column -j 8
#   ./experiment_compile.sh tutorial_barotropic_gyre -mpi -j 8
#   ./experiment_compile.sh 1D_ocean_ice_column -adm -taf_dir /path/to/TAF -j 8

set -e

# Check for help or no arguments before anything that depends on being run
# from inside a MITgcm checkout, so -h always works (even from a bare clone).
if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean] [-adm | -tlm] [-taf_dir <path>]"
    echo ""
    echo "Options:"
    echo "  -j <jobs>     Number of parallel make jobs (default: 4)"
    echo "                Examples: -j 1 (serial), -j 8 (fast), -j 16 (max)"
    echo "  -mpi          Compile with MPI for nPx*nPy processes (read from code/SIZE.h_mpi,"
    echo "                or code_ad/SIZE.h_mpi with -adm/-tlm)"
    echo "  -mods <dir>   Use this directory INSTEAD of the experiment's code/ (code_ad/ with"
    echo "                -adm/-tlm; absolute path; it must contain every file that directory"
    echo "                would, not just the changed ones)"
    echo "  -build <dir>  Build directory name (default: build_docker; build_docker_adm or"
    echo "                build_docker_tlm with -adm/-tlm)"
    echo "  -clean        Delete the host-side build directory first"
    echo "  -adm          Build the TAF adjoint model (mitgcmuv_ad) from code_ad/"
    echo "  -tlm          Build the TAF tangent-linear model (mitgcmuv_ftl) from code_ad/"
    echo "  -taf_dir <p>  TAF installation containing 'staf' (absolute path). Required with"
    echo "                -adm/-tlm unless the TAF_DIR environment variable is set."
    echo "                ~/.ssh is mounted read-only so staf can reach the TAF server."
    echo ""
    echo "Every compile is a full rebuild (testreport always runs 'make Clean')."
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column              # Non-MPI, default -j 4"
    echo "  $0 1D_ocean_ice_column -j 8         # Non-MPI, 8 make jobs"
    echo "  $0 1D_ocean_ice_column -clean -j 8  # Also wipe build_docker/ first"
    echo "  $0 tutorial_barotropic_gyre -mpi -j 8     # MPI-enabled"
    echo "  $0 lab_sea -mods /full/path/to/code_validation -j 8  # Custom code"
    echo "  $0 lab_sea -build build_validation -j 8  # Custom build directory"
    echo "  $0 1D_ocean_ice_column -adm -taf_dir /path/to/TAF -j 8   # TAF adjoint"
    echo "  $0 1D_ocean_ice_column -tlm -taf_dir /path/to/TAF -j 8   # TAF tangent linear"
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean] [-adm | -tlm] [-taf_dir <path>]"
    echo ""
    echo "Examples:"
    echo "  $0 lab_sea -j 8"
    echo "  $0 tutorial_barotropic_gyre -mpi -j 12"
    echo "  $0 lab_sea -mods /full/path/to/code_validation -j 8"
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

# Read nPx and nPy from a SIZE.h-style file; prints "npx:npy:total" or "not_found"
get_mpi_info_from_size_h() {
    local size_h="$1"
    if [ ! -f "$size_h" ]; then
        echo "not_found"
        return
    fi
    # Same pattern testreport uses: "     &           nPx =   2,"
    local npx npy
    npx=$(grep -i "^ *& *nPx *=" "$size_h" | head -1 | sed 's/.*= *//; s/[^0-9].*//')
    npy=$(grep -i "^ *& *nPy *=" "$size_h" | head -1 | sed 's/.*= *//; s/[^0-9].*//')
    if [ -z "$npx" ] || [ -z "$npy" ]; then
        echo "not_found"
        return
    fi
    echo "$npx:$npy:$((npx * npy))"
}

# Require a value after an option; $1 = option name, $2 = value
require_value() {
    if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: $1 requires a value"
        echo "Use -h or --help for more information"
        exit 1
    fi
}

EXPERIMENT="$1"
MAKE_JOBS=4  # Default to 4 parallel jobs
USE_MPI=false
MODS_DIR=""
BUILD_DIR_NAME=""  # Default depends on the kind of build (set after parsing)
CLEAN_BUILD=false
KIND=forward      # forward | adm | tlm
TAF_DIR="${TAF_DIR:-}"   # -taf_dir overrides the environment
TAF_DIR_GIVEN=false

# Parse remaining arguments
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        -j)
            if [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: -j requires a positive integer (got: '${2}')"
                exit 1
            fi
            MAKE_JOBS="$2"
            shift 2
            ;;
        -mpi)
            USE_MPI=true
            shift
            ;;
        -mods)
            require_value -mods "$2"
            MODS_DIR="$2"
            if [[ "$MODS_DIR" != /* ]]; then
                echo "ERROR: -mods path must be an absolute path"
                echo "Provided: $MODS_DIR"
                echo ""
                echo "Example: -mods /full/path/to/code_validation"
                exit 1
            fi
            if [ ! -d "$MODS_DIR" ]; then
                echo "ERROR: -mods directory does not exist: $MODS_DIR"
                exit 1
            fi
            MODS_DIR="${MODS_DIR%/}"
            shift 2
            ;;
        -build)
            require_value -build "$2"
            if [[ "$2" == */* || "$2" == "." || "$2" == ".." ]]; then
                echo "Error: -build must be a directory name inside the experiment (no '/'): $2"
                exit 1
            fi
            BUILD_DIR_NAME="$2"
            shift 2
            ;;
        -clean)
            CLEAN_BUILD=true
            shift
            ;;
        -adm|-tlm)
            if [ "$KIND" != forward ] && [ "$KIND" != "${1#-}" ]; then
                echo "Error: -adm and -tlm cannot be combined (compile each separately)"
                exit 1
            fi
            KIND="${1#-}"
            shift
            ;;
        -taf_dir)
            require_value -taf_dir "$2"
            TAF_DIR="$2"
            TAF_DIR_GIVEN=true
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [-j <jobs>] [-mpi] [-mods <dir>] [-build <dir>] [-clean] [-adm | -tlm] [-taf_dir <path>]"
            echo "Use -h or --help for more information"
            exit 1
            ;;
    esac
done

# Forward builds use code/ and mitgcmuv; TAF builds use code_ad/ and the
# binaries MITgcm's adall / ftlall make targets produce.
case "$KIND" in
    forward) CODE_SUBDIR=code;    BINARY=mitgcmuv;     TESTREPORT_KIND_ARG="" ;;
    adm)     CODE_SUBDIR=code_ad; BINARY=mitgcmuv_ad;  TESTREPORT_KIND_ARG="-adm" ;;
    tlm)     CODE_SUBDIR=code_ad; BINARY=mitgcmuv_ftl; TESTREPORT_KIND_ARG="-tlm" ;;
esac
DEFAULT_BUILD_DIR_NAME="build_docker"
[ "$KIND" != forward ] && DEFAULT_BUILD_DIR_NAME="build_docker_$KIND"
[ -z "$BUILD_DIR_NAME" ] && BUILD_DIR_NAME="$DEFAULT_BUILD_DIR_NAME"

if [ "$KIND" = forward ] && [ "$TAF_DIR_GIVEN" = true ]; then
    echo "Error: -taf_dir is only used with -adm or -tlm"
    exit 1
fi

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

# TAF builds: the experiment needs code_ad/ (unless -mods replaces it) and
# staf needs a TAF installation plus the TAF server key in ~/.ssh.
TAF_MOUNT_ARGS=()
TAF_ENV_ARGS=()
if [ "$KIND" != forward ]; then
    if [ -z "$MODS_DIR" ] && [ ! -d "$VERIFICATION_DIR/$EXPERIMENT/code_ad" ]; then
        echo "Error: -$KIND needs $EXPERIMENT/code_ad/, which does not exist"
        echo "       (only experiments with adjoint code can be built with -adm/-tlm)"
        exit 1
    fi
    if [ -z "$TAF_DIR" ]; then
        echo "Error: -$KIND needs a TAF installation: pass -taf_dir <path> (or set TAF_DIR)"
        exit 1
    fi
    if [[ "$TAF_DIR" != /* ]]; then
        echo "Error: -taf_dir path must be absolute (got: $TAF_DIR)"
        exit 1
    fi
    TAF_DIR="${TAF_DIR%/}"
    if [ ! -x "$TAF_DIR/staf" ]; then
        echo "Error: no executable 'staf' in TAF directory: $TAF_DIR"
        exit 1
    fi
    if [ ! -d "$HOME/.ssh" ]; then
        echo "Error: ~/.ssh not found; staf needs the TAF server key (~/.ssh/taf)"
        exit 1
    fi
    [ -f "$HOME/.ssh/taf" ] || \
        echo "Warning: ~/.ssh/taf (the key staf uses) not found; TAF will likely fail"
    # ~/.ssh is mounted read-only, so ssh inside the container cannot record a
    # new host key: the TAF server must already be in known_hosts.
    if command -v ssh-keygen > /dev/null 2>&1 && \
       ! ssh-keygen -F fastopt.de -f "$HOME/.ssh/known_hosts" > /dev/null 2>&1; then
        echo "Warning: fastopt.de is not in ~/.ssh/known_hosts; staf will fail inside"
        echo "         the container. Run '$TAF_DIR/staf -test' once on this host first."
    fi
    TAF_MOUNT_ARGS=(-v "$TAF_DIR:/taf" -v "$HOME/.ssh:/home/mitgcm/.ssh:ro")
    TAF_ENV_ARGS=(-e "PATH=/taf:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mitgcm/tools")
fi

# MPI process count comes from SIZE.h_mpi (in -mods dir if given, else code/
# or code_ad/)
MPI_NPROCS=1
if [ "$USE_MPI" = true ]; then
    if [ -n "$MODS_DIR" ]; then
        SIZE_H_MPI="$MODS_DIR/SIZE.h_mpi"
    else
        SIZE_H_MPI="$VERIFICATION_DIR/$EXPERIMENT/$CODE_SUBDIR/SIZE.h_mpi"
    fi
    MPI_INFO=$(get_mpi_info_from_size_h "$SIZE_H_MPI")
    if [ "$MPI_INFO" = "not_found" ]; then
        echo "ERROR: -mpi flag requires SIZE.h_mpi (with nPx and nPy) in:"
        echo "       $SIZE_H_MPI"
        echo "       Cannot proceed with MPI build."
        exit 1
    fi
    NPX=$(echo "$MPI_INFO" | cut -d: -f1)
    NPY=$(echo "$MPI_INFO" | cut -d: -f2)
    MPI_NPROCS=$(echo "$MPI_INFO" | cut -d: -f3)
fi

echo "=========================================="
echo "Compiling MITgcm (NO RUN)"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Arch:       $ARCH"
if [ "$KIND" = adm ]; then
echo "  Kind:       adjoint (TAF, code_ad/ -> $BINARY)"
elif [ "$KIND" = tlm ]; then
echo "  Kind:       tangent linear (TAF, code_ad/ -> $BINARY)"
fi
if [ "$USE_MPI" = true ]; then
echo "  MPI:        true ($MPI_NPROCS processes: nPx=$NPX x nPy=$NPY from SIZE.h_mpi)"
else
echo "  MPI:        false"
fi
echo "  Make jobs:  -j $MAKE_JOBS"
if [ -n "$MODS_DIR" ]; then
echo "  Mods:       $MODS_DIR"
fi
if [ "$KIND" != forward ]; then
echo "  TAF:        $TAF_DIR"
fi
echo "  MITgcm:     $MITGCM_ROOT"
echo "=========================================="
echo ""

BUILD_DIR="$VERIFICATION_DIR/$EXPERIMENT/$BUILD_DIR_NAME"

if [ "$CLEAN_BUILD" = true ] && [ -d "$BUILD_DIR" ]; then
    echo "Cleaning build directory (user requested): $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
# Old build files are replaced by this build
rm -f "$BUILD_DIR/mitgcmuv" "$BUILD_DIR/mitgcmuv_ad" "$BUILD_DIR/mitgcmuv_ftl" "$BUILD_DIR/build_info.txt"

echo "Mounting directories:"
echo "  MITgcm: $MITGCM_ROOT -> /mitgcm (read-write)"
echo "  Build:  $BUILD_DIR -> /build_output (read-write)"
if [ "$KIND" != forward ]; then
echo "  TAF:    $TAF_DIR -> /taf (on PATH), ~/.ssh -> /home/mitgcm/.ssh (read-only)"
fi

# Mods directory: symlinks (at any depth) are dereferenced into a temp copy,
# since the container cannot follow links that point outside the mount.
MODS_MOUNT_ARGS=()
TEMP_MODS_DIR=""
cleanup_temp_mods() {
    if [ -n "$TEMP_MODS_DIR" ] && [ -d "$TEMP_MODS_DIR" ]; then
        rm -rf "$TEMP_MODS_DIR"
    fi
}
trap cleanup_temp_mods EXIT

if [ -n "$MODS_DIR" ]; then
    if find "$MODS_DIR" -type l | grep -q .; then
        TEMP_MODS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mitgcm_mods.XXXXXX")"
        (cd "$MODS_DIR" && tar ch .) | tar xC "$TEMP_MODS_DIR"
        echo "  Mods:   $MODS_DIR (symlinks dereferenced into $TEMP_MODS_DIR) -> /mods_dir"
        MODS_MOUNT_ARGS=(-v "$TEMP_MODS_DIR:/mods_dir")
    else
        echo "  Mods:   $MODS_DIR -> /mods_dir"
        MODS_MOUNT_ARGS=(-v "$MODS_DIR:/mods_dir")
    fi
fi
echo ""

TESTREPORT_MPI_ARG=""
if [ "$USE_MPI" = true ]; then
    # testreport's plain -mpi means 2 processes and rewrites SIZE.h_mpi to
    # fit; -MPI=N keeps the full nPx*nPy decomposition from SIZE.h_mpi.
    TESTREPORT_MPI_ARG="-MPI=$MPI_NPROCS"
fi

# Compile in Docker with MITgcm mounted from host
COMPILE_RC=0
docker run --rm \
    -v "$MITGCM_ROOT:/mitgcm" \
    -v "$BUILD_DIR:/build_output" \
    "${MODS_MOUNT_ARGS[@]}" \
    "${TAF_MOUNT_ARGS[@]}" \
    "${TAF_ENV_ARGS[@]}" \
    mitgcm:latest bash -c "
    cd /mitgcm/verification
    EXP_DIR=/mitgcm/verification/$EXPERIMENT

    export OPTFILE=/mitgcm/tools/build_options/$OPTFILE

    restore_code() {
        if [ -n \"$MODS_DIR\" ] && [ -d \"\$EXP_DIR/${CODE_SUBDIR}_orig\" ]; then
            echo '==> Restoring original $CODE_SUBDIR/ directory'
            rm -rf \"\$EXP_DIR/$CODE_SUBDIR\"
            mv \"\$EXP_DIR/${CODE_SUBDIR}_orig\" \"\$EXP_DIR/$CODE_SUBDIR\"
        fi
        # testreport output dirs are named tr_<hostname>_<date>_<n>
        rm -rf /mitgcm/verification/tr_\$(hostname)_*
    }
    trap restore_code EXIT
    trap 'exit 130' INT TERM

    echo '==> Compiling experiment with -j $MAKE_JOBS...'

    # If -mods is specified, temporarily replace code/ (code_ad/) with mods
    if [ -n \"$MODS_DIR\" ]; then
        if [ -d \"\$EXP_DIR/${CODE_SUBDIR}_orig\" ]; then
            echo ''
            echo 'ERROR: Found leftover ${CODE_SUBDIR}_orig/ from previous interrupted run'
            echo '       This indicates the script was interrupted before cleanup.'
            echo ''
            echo 'To fix, manually restore the original code directory:'
            echo '  cd $EXPERIMENT'
            echo '  rm -rf $CODE_SUBDIR'
            echo '  mv ${CODE_SUBDIR}_orig $CODE_SUBDIR'
            echo ''
            trap - EXIT
            exit 1
        fi
        echo '==> Using custom code directory (temporarily replacing $CODE_SUBDIR/)'
        if [ -d \"\$EXP_DIR/$CODE_SUBDIR\" ]; then
            mv \"\$EXP_DIR/$CODE_SUBDIR\" \"\$EXP_DIR/${CODE_SUBDIR}_orig\"
        fi
        cp -rp /mods_dir \"\$EXP_DIR/$CODE_SUBDIR\"
    fi

    if [ \"$USE_MPI\" = true ]; then
        export MPI_INC_DIR=/usr/lib/$MPI_ARCH/openmpi/include
        export MPIINCLUDEDIR=/usr/lib/$MPI_ARCH/openmpi/include
    fi

    TESTREPORT_CMD=\"./testreport -t $EXPERIMENT -optfile \$OPTFILE -norun $TESTREPORT_KIND_ARG $TESTREPORT_MPI_ARG -j $MAKE_JOBS\"
    echo \"Running: \$TESTREPORT_CMD\"
    \$TESTREPORT_CMD > /tmp/compile.log 2>&1 || true
    cp /tmp/compile.log /build_output/compile.log

    if [ ! -f $EXPERIMENT/build/$BINARY ]; then
        echo 'ERROR: Compilation failed - $BINARY not created!'
        echo ''
        echo 'Last 50 lines of log:'
        tail -50 /tmp/compile.log
        # testreport keeps make's output in build/make.tr_log (TAF errors land there)
        if [ -f $EXPERIMENT/build/make.tr_log ]; then
            cp $EXPERIMENT/build/make.tr_log /build_output/make.tr_log
            echo ''
            echo 'Last 30 lines of make output ($BUILD_DIR_NAME/make.tr_log):'
            tail -30 $EXPERIMENT/build/make.tr_log
        fi
        echo ''
        echo 'Full log saved to: $BUILD_DIR_NAME/compile.log'
        exit 1
    fi

    # After successful compilation, save mods as reference copy
    if [ -n \"$MODS_DIR\" ]; then
        echo '==> Saving mods directory as reference (code_validation/)'
        rm -rf \"\$EXP_DIR/code_validation\"
        cp -rp /mods_dir \"\$EXP_DIR/code_validation\"
    fi

    echo '==> Compilation successful! Log: $BUILD_DIR_NAME/compile.log'
    echo '==> Copying build files...'
    cp -r $EXPERIMENT/build/* /build_output/ 2>&1 | grep -v 'dangling symlink' || true
    cp $EXPERIMENT/build/$BINARY /build_output/$BINARY
    echo \"Copied \$(find /build_output -type f | wc -l) build files\"
" || COMPILE_RC=$?

if [ "$COMPILE_RC" -ne 0 ] || [ ! -f "$BUILD_DIR/$BINARY" ]; then
    echo ""
    echo "=========================================="
    echo "Compilation FAILED"
    echo "=========================================="
    echo "Log: $BUILD_DIR/compile.log"
    exit 1
fi

cat > "$BUILD_DIR/build_info.txt" <<EOF
EXPERIMENT=$EXPERIMENT
KIND=$KIND
BINARY=$BINARY
MPI=$USE_MPI
NPROCS=$MPI_NPROCS
MODS_DIR=$MODS_DIR
ARCH=$ARCH
OPTFILE=$OPTFILE
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo ""
echo "=========================================="
echo "Compilation Complete!"
echo "=========================================="
echo ""
echo "Build directory: $BUILD_DIR"
ls -lh "$BUILD_DIR/$BINARY"
echo ""
echo "Compilation log: $BUILD_DIR/compile.log"
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

RUN_ARGS=""
[ "$KIND" != forward ] && RUN_ARGS="$RUN_ARGS -$KIND"
[ "$BUILD_DIR_NAME" != "$DEFAULT_BUILD_DIR_NAME" ] && RUN_ARGS="$RUN_ARGS -build $BUILD_DIR_NAME"
[ "$USE_MPI" = true ] && RUN_ARGS="$RUN_ARGS -mpi $MPI_NPROCS"
echo "Next step: Run the model with"
echo "  ./experiment_run_no_compile.sh $EXPERIMENT$RUN_ARGS"
echo ""

#!/bin/bash
#
# Run an interactive shell in the MITgcm Docker container
#
# Usage: ./docker_run_interactive.sh [options]
#
# Run './docker_run_interactive.sh -h' for detailed help
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Directory holding the real scripts (this file may be a symlink)
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_PATH" ]; do
    LINK_DIR="$( cd -P "$( dirname "$SCRIPT_PATH" )" && pwd )"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$LINK_DIR/$SCRIPT_PATH"
done
REAL_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_PATH" )" && pwd )"

# Function to show comprehensive help
show_help() {
    cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MITgcm Docker Interactive Shell
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    ./docker_run_interactive.sh [options]

OPTIONS:
    -code <path>        Mount custom code directory
    -taf_dir <path>     Mount TAF directory for adjoint builds
    -dereference        Dereference symlinks in custom code directory
    -h, --help          Show this help message

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DETAILED OPTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-code <path>
    Mount a custom code directory into the container at /custom_code.

    Requirements:
    • Path MUST be absolute (e.g., /Users/you/project/code)
    • Directory must exist
    • Use with genmake2 -mods=/custom_code inside container

    Use case:
    • Override experiment source files (e.g., modified kpp_calc.F)
    • Add instrumentation for debugging/validation
    • Test alternative parameterizations

    Example:
        ./docker_run_interactive.sh -code /path/to/custom/code

    Inside container:
        cd lab_sea/build
        ../../../tools/genmake2 -mods=/custom_code -optfile=$OPTFILE
        make depend && make

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-taf_dir <path>
    Mount TAF (Tangent linear and Adjoint Model Compiler) directory.

    Requirements:
    • Path MUST be absolute
    • Directory should contain the 'staf' executable (a warning is
      printed if it does not)
    • Requires SSH keys in ~/.ssh for license validation

    What it does:
    • Mounts TAF directory at /taf in container
    • Adds /taf to PATH (makes 'staf' command available)
    • Mounts ~/.ssh (read-only) for license key access

    Use case:
    • Generate adjoint code (make adall -> mitgcmuv_ad)
    • Generate tangent linear code (make ftlall -> mitgcmuv_ftl)
    • Debugging TAF builds by hand. For routine adjoint/TLM builds, use
      experiment_compile.sh -adm / -tlm instead (no interactive shell).

    Example:
        ./docker_run_interactive.sh -taf_dir /Users/you/TAF

    Inside container:
        which staf              # Check TAF is available
        staf -test              # Check the TAF server accepts your key
        cd lab_sea/build
        ../../../tools/genmake2 -mods=../code_ad -optfile=$OPTFILE
        make depend
        make adall              # Build adjoint (mitgcmuv_ad)

    Security:
    • ~/.ssh mounted read-only (container cannot modify SSH config)
    • Because of that, the TAF server (fastopt.de) must already be in
      ~/.ssh/known_hosts: run 'staf -test' once on the host first

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-dereference
    Dereference symlinks in custom code directory before mounting.

    When to use:
    • Your custom code directory contains symlinks
    • Symlinks point to files OUTSIDE the code directory
    • Example: ln -s /MITgcm/pkg/kpp/kpp_calc.F kpp_calc.F

    What it does:
    • Detects symlinks in -code directory
    • Creates temporary directory
    • Copies files with symlinks dereferenced (actual file content)
    • Mounts temp directory instead of original
    • Cleans up temp directory when done

    Why needed:
    Docker containers are isolated - they can only access mounted directories.
    If your code directory has symlinks pointing outside (e.g., to MITgcm
    source), Docker cannot follow them and files appear missing.

    Dereferencing converts symlinks to real files with actual content.

    Example:
        # Your code has: kpp_calc.F -> /MITgcm/pkg/kpp/kpp_calc.F
        ./docker_run_interactive.sh -code /path/to/code -dereference

        # Inside Docker, kpp_calc.F is a real file (not symlink)

    Performance:
    • Adds ~1 second to startup time
    • Negligible compared to compilation time (2-3 minutes)

    What is dereferencing?

        BEFORE (symlink):
            code/kpp_calc.F -> /MITgcm/pkg/kpp/kpp_calc.F  (50 bytes, pointer)

        AFTER (dereferenced):
            code/kpp_calc.F  (45 KB, actual Fortran source code)

    Check if you have symlinks:
        cd /path/to/your/code
        ls -l
        # Look for lines starting with 'l' (symlink) instead of '-' (file)
        # or: find . -type l

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Basic interactive shell (no custom code):
    ./docker_run_interactive.sh

2. With custom code (no symlinks):
    ./docker_run_interactive.sh -code /Users/you/project/kpp_mods

3. With custom code (has symlinks):
    ./docker_run_interactive.sh -code /Users/you/project/kpp_mods -dereference

4. With TAF support:
    ./docker_run_interactive.sh -taf_dir /Users/you/TAF

5. Custom code + TAF:
    ./docker_run_interactive.sh -code /path/to/code -taf_dir /path/to/TAF

6. Custom code with symlinks + TAF:
    ./docker_run_interactive.sh -code /path/to/code -dereference -taf_dir /path/to/TAF

7. Non-interactive (commands piped on stdin, no terminal needed):
    echo 'cd 1D_ocean_ice_column && ls' | ./docker_run_interactive.sh
   The piped commands are the shell's stdin, so a command that reads stdin
   (e.g. testreport) swallows the ones after it; give it '< /dev/null':
    echo './testreport -adm -t 1D_ocean_ice_column -of $OPTFILE < /dev/null' |
        ./docker_run_interactive.sh -taf_dir /path/to/TAF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INSIDE THE CONTAINER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You start in: /mitgcm/verification

Environment variables:
    OPTFILE           Path to build options file for your architecture
    MITGCM_ROOT       /mitgcm
    MITGCM_ROOTDIR    /mitgcm

Build with custom code:
    cd <experiment>/build
    ../../../tools/genmake2 -mods=/custom_code -optfile=$OPTFILE
    make depend
    make

Build with standard code:
    cd <experiment>/build
    ../../../tools/genmake2 -mods=../code -optfile=$OPTFILE
    make depend
    make

If TAF is available (adjoint code lives in <experiment>/code_ad):
    which staf                  # Verify TAF in PATH
    cd <experiment>/build
    ../../../tools/genmake2 -mods=../code_ad -optfile=$OPTFILE
    make depend
    make adall                  # Build adjoint        -> mitgcmuv_ad
    make ftlall                 # Build tangent linear -> mitgcmuv_ftl
    Or run MITgcm's own test:   ./testreport -adm -t <experiment> -of $OPTFILE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"File not found" errors with custom code:
    → Your code directory may have symlinks pointing outside
    → Solution: Add -dereference flag

"staf: command not found":
    → TAF directory not mounted or doesn't contain staf
    → Solution: Check path with -taf_dir and verify staf exists

TAF license errors:
    → SSH keys not accessible or invalid
    → Check: ~/.ssh directory exists and contains the key staf uses (~/.ssh/taf)
    → Check: Key permissions (usually 600 for private keys)
    → "Host key verification failed": fastopt.de is missing from
      ~/.ssh/known_hosts; run 'staf -test' once on the host

Path must be absolute:
    → Relative paths like ./code or ../project/code are rejected
    → Solution: Use full path starting with / (e.g., /Users/you/...)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MORE INFORMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    README.md                    - Full guide, including symlink dereferencing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# Parse arguments (before locating MITgcm, so -h works anywhere)
CUSTOM_CODE_DIR=""
TAF_DIR=""
DEREFERENCE=false
TEMP_DIRS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -code)
            CUSTOM_CODE_DIR="$2"
            if [[ ! "$CUSTOM_CODE_DIR" = /* ]]; then
                echo "Error: -code path must be absolute (starting with /)"
                echo "Got: $CUSTOM_CODE_DIR"
                exit 1
            fi
            if [[ ! -d "$CUSTOM_CODE_DIR" ]]; then
                echo "Error: Code directory does not exist: $CUSTOM_CODE_DIR"
                exit 1
            fi
            shift 2
            ;;
        -taf_dir)
            TAF_DIR="$2"
            if [[ ! "$TAF_DIR" = /* ]]; then
                echo "Error: -taf_dir path must be absolute (starting with /)"
                echo "Got: $TAF_DIR"
                exit 1
            fi
            if [[ ! -d "$TAF_DIR" ]]; then
                echo "Error: TAF directory does not exist: $TAF_DIR"
                exit 1
            fi
            if [[ ! -f "$TAF_DIR/staf" ]]; then
                echo "Warning: staf executable not found in $TAF_DIR"
            fi
            shift 2
            ;;
        -dereference)
            DEREFERENCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
    esac
done

# Find MITgcm root (parent of verification directory), same as the other scripts
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
        echo "Run this script from MITgcm/verification/ (after setup_links.sh)"
        exit 1
    fi
fi

# Handle dereferencing if requested
CODE_DIR_TO_MOUNT="$CUSTOM_CODE_DIR"
if [[ "$DEREFERENCE" == true ]] && [[ -n "$CUSTOM_CODE_DIR" ]]; then
    # Check if directory has symlinks
    if [ -d "$CUSTOM_CODE_DIR" ] && find "$CUSTOM_CODE_DIR" -type l 2>/dev/null | grep -q .; then
        echo "Detected symlinks in code directory: $CUSTOM_CODE_DIR"

        # Create temp directory
        TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/docker_code_$(basename "$CUSTOM_CODE_DIR").XXXXXX")"

        # Copy with dereferencing (-L flag)
        echo "  Dereferencing to: $TEMP_DIR"
        cp -RL "$CUSTOM_CODE_DIR"/. "$TEMP_DIR/"

        # Track for cleanup
        TEMP_DIRS+=("$TEMP_DIR")

        # Use temp directory instead
        CODE_DIR_TO_MOUNT="$TEMP_DIR"
        echo "  ✓ Will mount: $TEMP_DIR (dereferenced)"
        echo ""
    else
        echo "No symlinks detected in code directory (or directory empty)"
        echo "  Using original directory: $CUSTOM_CODE_DIR"
        echo ""
    fi
elif [[ "$DEREFERENCE" == true ]] && [[ -z "$CUSTOM_CODE_DIR" ]]; then
    echo "Warning: -dereference flag ignored (no -code directory specified)"
    echo ""
fi

# Trap to cleanup temp directories on exit
cleanup() {
    if [ ${#TEMP_DIRS[@]} -gt 0 ]; then
        echo ""
        echo "Cleaning up temporary directories..."
        for dir in "${TEMP_DIRS[@]}"; do
            rm -rf "$dir"
            echo "  Removed: $dir"
        done
    fi
}
trap cleanup EXIT

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

# Build image if it doesn't exist (same build as docker_build.sh)
if ! docker image inspect mitgcm:latest >/dev/null 2>&1; then
    echo "Image mitgcm:latest not found. Building it with docker_build.sh..."
    "$REAL_SCRIPT_DIR/docker_build.sh"
fi

echo ""
echo "Starting interactive bash shell..."
echo "You are in: /mitgcm/verification (mounted from host)"
echo ""
echo "Mounted directories:"
echo "  /mitgcm -> $MITGCM_ROOT"
if [[ -n "$CODE_DIR_TO_MOUNT" ]]; then
    if [[ "$CODE_DIR_TO_MOUNT" != "$CUSTOM_CODE_DIR" ]]; then
        echo "  /custom_code -> $CODE_DIR_TO_MOUNT (dereferenced from $CUSTOM_CODE_DIR)"
    else
        echo "  /custom_code -> $CODE_DIR_TO_MOUNT"
    fi
fi
if [[ -n "$TAF_DIR" ]]; then
    echo "  /taf -> $TAF_DIR"
    if [[ -d "$HOME/.ssh" ]]; then
        echo "  /home/mitgcm/.ssh -> $HOME/.ssh (read-only)"
    fi
fi
echo ""
echo "Environment variables set:"
echo "  OPTFILE=/mitgcm/tools/build_options/$OPTFILE"
if [[ -n "$TAF_DIR" ]]; then
    echo "  PATH includes /taf (staf available)"
fi
echo ""
echo "To run the test manually:"
echo "  ./testreport -t 1D_ocean_ice_column -optfile \$OPTFILE"
echo ""
if [[ -n "$CODE_DIR_TO_MOUNT" ]]; then
    echo "To build with custom code:"
    echo "  cd 1D_ocean_ice_column/build"
    echo "  ../../../tools/genmake2 -mods=/custom_code -optfile=\$OPTFILE"
    echo "  make depend"
    echo "  make"
    echo ""
fi
if [[ -n "$TAF_DIR" ]]; then
    echo "TAF available:"
    echo "  staf command is in PATH"
    echo "  Use for adjoint/tangent linear builds (make adall, make ftlall)"
    echo ""
fi
echo "Or to build normally:"
echo "  cd 1D_ocean_ice_column/build"
echo "  ../../../tools/genmake2 -mods=../code -optfile=\$OPTFILE"
echo "  make depend"
echo "  make"
echo "  cd ../run"
echo "  ln -s ../input/* ."
echo "  ln -s ../build/mitgcmuv ."
echo "  ./mitgcmuv"
echo ""

# Build docker mount arguments
MOUNT_ARGS=(-v "$MITGCM_ROOT:/mitgcm")
if [[ -n "$CODE_DIR_TO_MOUNT" ]]; then
    MOUNT_ARGS+=(-v "$CODE_DIR_TO_MOUNT:/custom_code")
fi
if [[ -n "$TAF_DIR" ]]; then
    MOUNT_ARGS+=(-v "$TAF_DIR:/taf")
    # Mount ~/.ssh for TAF license key (read-only for security)
    if [[ -d "$HOME/.ssh" ]]; then
        MOUNT_ARGS+=(-v "$HOME/.ssh:/home/mitgcm/.ssh:ro")
        [[ -f "$HOME/.ssh/taf" ]] || \
            echo "Warning: ~/.ssh/taf (the key staf uses) not found; TAF will likely fail"
        # ~/.ssh is read-only in the container, so ssh there cannot record a
        # new host key: the TAF server must already be in known_hosts.
        if command -v ssh-keygen > /dev/null 2>&1 && \
           ! ssh-keygen -F fastopt.de -f "$HOME/.ssh/known_hosts" > /dev/null 2>&1; then
            echo "Warning: fastopt.de is not in ~/.ssh/known_hosts; staf will fail in the"
            echo "         container. Run '$TAF_DIR/staf -test' once on this host first."
        fi
    else
        echo "Warning: ~/.ssh directory not found, TAF may not have access to license key"
    fi
fi

# Build environment arguments (OPTFILE is also set by the image's .bashrc,
# but that is only read by interactive shells)
ENV_ARGS=(-e "OPTFILE=/mitgcm/tools/build_options/$OPTFILE")
if [[ -n "$TAF_DIR" ]]; then
    # Add /taf to PATH
    ENV_ARGS+=(-e "PATH=/taf:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mitgcm/tools")
fi

# Allocate a terminal only when stdin is one; piped commands
# (e.g. echo 'make' | ./docker_run_interactive.sh) run non-interactively.
if [ -t 0 ]; then
    TTY_ARGS=(-it)
    SHELL_ARGS=()
else
    TTY_ARGS=(-i)
    SHELL_ARGS=(-s)
    echo "(stdin is not a terminal: running piped commands non-interactively)"
fi

docker run --rm "${TTY_ARGS[@]}" \
    --platform "$PLATFORM" \
    "${MOUNT_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    -w /mitgcm/verification \
    mitgcm:latest \
    /bin/bash "${SHELL_ARGS[@]}"

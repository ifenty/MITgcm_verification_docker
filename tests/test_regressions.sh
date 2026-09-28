#!/bin/bash
#
# Regression tests for bugs found in the scripts (no Docker required).
#
# A mock 'docker' executable is put first on PATH. It records every call in
# $MOCK_DOCKER_LOG and simulates the container side:
#   - compile (script mentions testreport): creates mitgcmuv in the /build_output
#     mount, or fails when MOCK_COMPILE=fail
#   - run (script mentions mitgcmuv): writes output.txt (serial) or
#     STDOUT.0000 + mpirun.log (MPI) in the -w directory; MOCK_RUN selects
#     normal | abnormal | crash
#   - image inspect: succeeds unless MOCK_IMAGE_MISSING=1
# A throwaway MITgcm-like tree is built in a temp directory and the scripts
# are linked into it with setup_links.sh, the same way a user installs them.
#
# Usage: tests/test_regressions.sh [-v]     (-v prints output of passing tests too)
#
# Deliberately no 'set -e': failing checks are counted, not fatal.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
VERBOSE=false
[ "$1" = "-v" ] && VERBOSE=true

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

test_count=0
pass_count=0
fail_count=0

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/mitgcm_docker_regress.XXXXXX")"
MITGCM="$SANDBOX/MITgcm"
VER="$MITGCM/verification"
OUT="$SANDBOX/last_output.txt"
export MOCK_DOCKER_LOG="$SANDBOX/docker_calls.log"
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$TMPDIR"

cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# check <name> <command-string that must succeed>
check() {
    local name="$1"; shift
    test_count=$((test_count + 1))
    if eval "$*" >> "$OUT.check" 2>&1; then
        echo -e "  ${GREEN}PASS${NC}  $name"
        pass_count=$((pass_count + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $name"
        echo "        check: $*"
        echo "        last command output:"
        sed 's/^/          /' "$OUT" | tail -25
        fail_count=$((fail_count + 1))
    fi
}

# run_cmd <command...>: run, capture output in $OUT and exit code in $RC
run_cmd() {
    : > "$OUT"
    "$@" > "$OUT" 2>&1 < /dev/null
    RC=$?
    if [ "$VERBOSE" = true ]; then sed 's/^/        | /' "$OUT"; fi
}

out_has() { grep -q -- "$1" "$OUT"; }

# Write a MITgcm-style monitor log.
# write_mon <file> <n_records> [scale] [extra-awk-per-value]
#   scale multiplies every value (1 = reference values)
write_mon() {
    local f="$1" n="$2" scale="${3:-1}"
    awk -v n="$n" -v s="$scale" 'BEGIN {
        for (i = 1; i <= n; i++) {
            printf "(PID.TID 0000.0001) %%MON time_tsnumber                =   %d\n", i
            printf "(PID.TID 0000.0001) %%MON cg2d_init_res                =   %.13E\n", s * (1.0 + i / 7.0)
            printf "(PID.TID 0000.0001) %%MON dynstat_theta_mean           =   %.13E\n", s * (10.0 + i / 3.0)
            printf "(PID.TID 0000.0001) %%MON dynstat_eta_mean             =   %.13E\n", s * 3.0e-21
            printf "(PID.TID 0000.0001) %%MON seaice_heff_mean             =   %.13E\n", s * (0.5 + i / 11.0)
        }
        print "PROGRAM MAIN: Execution ended Normally"
    }' > "$f"
}

# Build a fresh fake MITgcm tree and install the scripts into it
make_tree() {
    rm -rf "$MITGCM"
    mkdir -p "$MITGCM/model" "$MITGCM/tools/build_options" "$VER"
    touch "$VER/.gitignore"
    touch "$MITGCM/tools/build_options/linux_amd64_gfortran" "$MITGCM/tools/build_options/linux_arm64_gfortran"
    mkdir -p "$VER/1D_ocean_ice_column/code" "$VER/1D_ocean_ice_column/input" "$VER/1D_ocean_ice_column/results"
    # experiment with MPI + secondary input dir
    local e="$VER/exp_mpi"
    mkdir -p "$e/code" "$e/input" "$e/input.alt" "$e/results"
    cat > "$e/code/SIZE.h" <<'EOF'
      PARAMETER (
     &           sNx =  62,
     &           sNy =  62,
     &           nPx =   1,
     &           nPy =   1,
     &           Nr  =   1)
EOF
    cat > "$e/code/SIZE.h_mpi" <<'EOF'
C     nPx :: No. of processes to use in X.
      PARAMETER (
     &           sNx =  31,
     &           sNy =  31,
     &           nPx =   2,
     &           nPy =   2,
     &           Nr  =   1)
EOF
    echo "base data" > "$e/input/data"
    echo "base eedata" > "$e/input/eedata"
    echo "only in input" > "$e/input/bathy.bin"
    echo "exch2 mpi" > "$e/input/data.exch2.mpi"
    echo "exch2 serial" > "$e/input/data.exch2"
    echo "alt data" > "$e/input.alt/data"
    echo "only in input" > "$e/input/data.kpp"
    mkdir -p "$e/input_nokpp"; echo "nokpp data" > "$e/input_nokpp/data"
    write_mon "$e/results/output.txt" 5
    write_mon "$e/results/output.alt.txt" 5 2
    "$SCRIPTS_DIR/setup_links.sh" "$VER" > "$SANDBOX/setup.log" 2>&1 < /dev/null
}

# The mock docker
make_mock_docker() {
    mkdir -p "$SANDBOX/bin"
    cat > "$SANDBOX/bin/docker" <<'MOCK'
#!/bin/bash
printf '%q ' "$@" >> "$MOCK_DOCKER_LOG"; echo >> "$MOCK_DOCKER_LOG"
case "$1" in
    image) [ "$MOCK_IMAGE_MISSING" = 1 ] && exit 1; exit 0 ;;
    build) exit 0 ;;
    run) ;;
    *) exit 0 ;;
esac
shift
MOUNTS=(); WORKDIR=""; SCRIPT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -v) MOUNTS+=("$2"); shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -e|--platform) shift 2 ;;
        -c) SCRIPT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
# container path -> host path using the -v mounts
to_host() {
    local p="$1" m src dst
    for m in "${MOUNTS[@]}"; do
        src="${m%%:*}"; dst="${m#*:}"; dst="${dst%%:*}"
        case "$p" in "$dst"|"$dst"/*) echo "$src${p#$dst}"; return ;; esac
    done
    echo "$p"
}
if [[ "$SCRIPT" == *testreport* ]]; then
    echo "$SCRIPT" > "$(dirname "$MOCK_DOCKER_LOG")/last_compile_script.txt"
    [ "$MOCK_COMPILE" = fail ] && { echo "mock compile failure"; exit 1; }
    B="$(to_host /build_output)"
    printf '#!/bin/bash\necho mock\n' > "$B/mitgcmuv"; chmod +x "$B/mitgcmuv"
    echo "mock compile log" > "$B/compile.log"
    exit 0
fi
if [[ "$SCRIPT" == *mitgcmuv* ]]; then
    D="$(to_host "$WORKDIR")"
    ls -la "$D" > "$(dirname "$MOCK_DOCKER_LOG")/run_dir_listing.txt"
    case "${MOCK_RUN:-normal}" in
        normal)   END="PROGRAM MAIN: Execution ended Normally" ;;
        abnormal) END="STOP ABNORMAL END: PROGRAM MAIN" ;;
        crash)    END="Segmentation fault" ;;
    esac
    if [[ "$SCRIPT" == *'[ "true" = true ]'* ]]; then   # the run script's USE_MPI test
        { echo "(PID.TID 0000.0001) %MON cg2d_init_res = 1.0E+00"; echo "$END"; } > "$D/STDOUT.0000"
        echo "mpirun console" > "$D/mpirun.log"
    else
        { echo "(PID.TID 0000.0001) %MON cg2d_init_res = 1.0E+00"; echo "$END"; } > "$D/output.txt"
    fi
    [ "${MOCK_RUN:-normal}" = crash ] && exit 139
    exit 0
fi
exit 0
MOCK
    chmod +x "$SANDBOX/bin/docker"
    export PATH="$SANDBOX/bin:$PATH"
}

make_mock_docker
make_tree

echo "=========================================="
echo "Regression Tests (mock docker)"
echo "=========================================="
echo "Sandbox: $SANDBOX"

# ---------------------------------------------------------------------------
echo ""
echo "=== compare_results.sh: comparison correctness ==="
# ---------------------------------------------------------------------------
E="$VER/exp_mpi"
cd "$VER"

# Bug: tr_cmpnum stopped after 999 lines and reported 99 digits = PASS
write_mon "$E/results/output.txt" 400            # 2000 %MON lines
mkdir -p "$E/out_big"
write_mon "$E/out_big/output.txt" 400 1.01      # every value off by 1%
run_cmd ./compare_results.sh exp_mpi out_big
check "long output (>999 %MON lines) perturbed by 1% FAILS" '[ $RC -ne 0 ] && out_has "Status:.*FAIL"'

write_mon "$E/out_big/output.txt" 400
run_cmd ./compare_results.sh exp_mpi out_big
check "long identical output PASSES with 16 digits" '[ $RC -eq 0 ] && out_has "Matching digits: 16"'

write_mon "$E/results/output.txt" 5
mkdir -p "$E/out_bad"
: > "$E/out_bad/output.txt"
run_cmd ./compare_results.sh exp_mpi out_bad
check "empty output FAILS (N/O)" '[ $RC -ne 0 ] && out_has "N/O"'

write_mon "$E/out_bad/output.txt" 3
run_cmd ./compare_results.sh exp_mpi out_bad
check "truncated output (fewer records) FAILS" '[ $RC -ne 0 ] && out_has "line count differs"'

write_mon "$E/out_bad/output.txt" 5
sed -i.bak 's/\(cg2d_init_res *= *\).*/\1NaN/' "$E/out_bad/output.txt"
run_cmd ./compare_results.sh exp_mpi out_bad
check "NaN output FAILS" '[ $RC -ne 0 ] && out_has "NaN"'

# Bug: near-zero diagnostics that are not the deciding variable failed runs
write_mon "$E/out_bad/output.txt" 5
sed -i.bak 's/\(dynstat_eta_mean *= *\).*/\1-4.2385525173611E-21/' "$E/out_bad/output.txt"
printf 'PS PS Etaav\n' > "$E/input/tr_checklist"
run_cmd ./compare_results.sh exp_mpi out_bad
check "differing near-zero non-deciding variable does not fail the run" '[ $RC -eq 0 ] && out_has "Etaav.* 0"'
rm -f "$E/input/tr_checklist"

# Bug: default threshold was 13 (testreport uses 10)
awk '/cg2d_init_res/ { $NF = sprintf("%.13E", $NF * (1 + 3e-11)) } { print }' "$E/results/output.txt" > "$E/out_bad/output.txt"
run_cmd ./compare_results.sh exp_mpi out_bad
check "default --match is 10 (testreport default): an 11-digit match PASSES" '[ $RC -eq 0 ] && out_has "Required:        10"'
run_cmd ./compare_results.sh exp_mpi out_bad --match 13
check "--match 13 on the same output FAILS" '[ $RC -ne 0 ]'

# tr_checklist first entry decides pass/fail
write_mon "$E/out_bad/output.txt" 5
sed -i.bak 's/\(seaice_heff_mean *= *\).*/\19.9E+00/' "$E/out_bad/output.txt"
run_cmd ./compare_results.sh exp_mpi out_bad
check "default checklist (PS) ignores a bad seaice field" '[ $RC -eq 0 ]'
ln -sf ../input/tr_checklist "$E/out_bad/tr_checklist"; printf 'hSIav PS\n' > "$E/input/tr_checklist"
run_cmd ./compare_results.sh exp_mpi out_bad
check "tr_checklist 'hSIav' makes the bad seaice field decide: FAIL" '[ $RC -ne 0 ] && out_has "> hSIav"'
rm -f "$E/input/tr_checklist" "$E/out_bad/tr_checklist"

# Bug: MPI runs have the monitor output only in STDOUT.0000
mkdir -p "$E/out_mpi"; echo "mpirun console only" > "$E/out_mpi/output.txt"
write_mon "$E/out_mpi/STDOUT.0000" 5
run_cmd ./compare_results.sh exp_mpi out_mpi
check "MPI output: falls back to STDOUT.0000 when output.txt has no %MON" '[ $RC -eq 0 ] && out_has "STDOUT.0000"'

# input.<X> runs compare against results/output.<X>.txt
mkdir -p "$E/out_alt"; write_mon "$E/out_alt/output.txt" 5 2; echo "INPUT_DIR=input.alt" > "$E/out_alt/run_info.txt"
run_cmd ./compare_results.sh exp_mpi out_alt
check "input.alt run is compared with results/output.alt.txt" '[ $RC -eq 0 ] && out_has "results/output.alt.txt"'

# Bug: only worked when run from inside verification/
cd "$SANDBOX"
write_mon "$E/out_big/output.txt" 5
run_cmd "$VER/compare_results.sh" exp_mpi out_big
check "works when run from outside verification/" '[ $RC -eq 0 ]'
cd "$VER"

# Bug: flags with missing values exited silently
run_cmd ./compare_results.sh exp_mpi --match
check "--match without value prints an error" '[ $RC -ne 0 ] && out_has "requires"'
run_cmd ./compare_results.sh exp_mpi --match abc
check "--match abc prints an error" '[ $RC -ne 0 ] && out_has "requires"'

check "compare_results.sh no longer needs a host C compiler" '! grep -qE "\\\$CC|gcc" "$SCRIPTS_DIR/compare_results.sh"'

# ---------------------------------------------------------------------------
echo ""
echo "=== experiment_compile.sh ==="
# ---------------------------------------------------------------------------
cp "$E/code/SIZE.h" "$SANDBOX/SIZE.h.orig"
: > "$MOCK_DOCKER_LOG"
run_cmd ./experiment_compile.sh exp_mpi -mpi -j 2
check "-mpi compile succeeds" '[ $RC -eq 0 ]'
# Bug: -mpi copied SIZE.h_mpi over code/SIZE.h and never restored it
check "-mpi leaves code/SIZE.h unchanged" 'cmp -s "$E/code/SIZE.h" "$SANDBOX/SIZE.h.orig"'
# Bug: testreport -mpi means 2 procs; must pass -MPI=nPx*nPy
check "-mpi passes -MPI=4 (nPx*nPy from SIZE.h_mpi) to testreport" 'grep -q -- "-MPI=4" "$SANDBOX/last_compile_script.txt"'
check "-mpi reports 4 processes" 'out_has "4 processes"'
check "build_info.txt records MPI=true NPROCS=4" 'grep -q "^MPI=true" "$E/build_docker/build_info.txt" && grep -q "^NPROCS=4" "$E/build_docker/build_info.txt"'
check "next-step hint includes -mpi 4" 'out_has "experiment_run_no_compile.sh exp_mpi -mpi 4"'

run_cmd ./experiment_compile.sh exp_mpi -j 2 -build build_custom
check "compile log path message uses the -build name" 'grep -q "build_custom/compile.log" "$SANDBOX/last_compile_script.txt"'
check "testreport tr_<hostname>_* output dirs are cleaned up in the container" 'grep -q "tr_\\\$(hostname)_" "$SANDBOX/last_compile_script.txt"'

# Bug: nonexistent -mods dir reached docker (which creates it as root)
: > "$MOCK_DOCKER_LOG"
run_cmd ./experiment_compile.sh exp_mpi -mods "$SANDBOX/no_such_mods"
check "nonexistent -mods dir is rejected before docker runs" '[ $RC -ne 0 ] && out_has "does not exist" && [ ! -s "$MOCK_DOCKER_LOG" ]'

# Bug: temp dereference dir leaked when compilation failed
mkdir -p "$SANDBOX/mods_links/sub"
ln -s "$E/code/SIZE.h" "$SANDBOX/mods_links/SIZE.h"
ln -s "$E/code/SIZE.h" "$SANDBOX/mods_links/sub/nested.h"
MOCK_COMPILE=fail run_cmd ./experiment_compile.sh exp_mpi -mods "$SANDBOX/mods_links"
check "failed compile returns non-zero" '[ $RC -ne 0 ] && out_has "FAILED"'
check "failed compile removes the dereferenced temp mods dir" '[ -z "$(ls -A "$TMPDIR")" ]'
run_cmd ./experiment_compile.sh exp_mpi -mods "$SANDBOX/mods_links"
check "symlinks in -mods subdirectories are dereferenced too" 'out_has "symlinks dereferenced"'
check "successful compile removes the temp mods dir" '[ -z "$(ls -A "$TMPDIR")" ]'

# Bug: options without values exited silently
run_cmd ./experiment_compile.sh exp_mpi -j
check "-j without value prints an error" '[ $RC -ne 0 ] && out_has "-j requires"'
run_cmd ./experiment_compile.sh exp_mpi -build
check "-build without value prints an error" '[ $RC -ne 0 ] && out_has "requires a value"'
run_cmd ./experiment_compile.sh exp_mpi -mods
check "-mods without value prints an error" '[ $RC -ne 0 ] && out_has "requires a value"'
run_cmd ./experiment_compile.sh 1D_ocean_ice_column -mpi
check "-mpi without SIZE.h_mpi is rejected" '[ $RC -ne 0 ] && out_has "requires SIZE.h_mpi"'

# ---------------------------------------------------------------------------
echo ""
echo "=== experiment_run_no_compile.sh ==="
# ---------------------------------------------------------------------------
run_cmd ./experiment_compile.sh exp_mpi -j 2          # serial build in build_docker
run_cmd ./experiment_run_no_compile.sh exp_mpi -output out_stale
check "serial run succeeds" '[ $RC -eq 0 ] && out_has "ended normally"'
check "input links are relative (valid on host and in container)" '[ "$(readlink "$E/out_stale/data")" = "../input/data" ] && [ -e "$E/out_stale/data" ]'
check "run_info.txt records the input dir" 'grep -q "^INPUT_DIR=input$" "$E/out_stale/run_info.txt"'

# Bug: symlinks from a previous run's input dir leaked into the next run
run_cmd ./experiment_run_no_compile.sh exp_mpi input_nokpp -output out_stale
check "switching input dir removes stale links from the previous run" '[ ! -e "$E/out_stale/data.kpp" ] && [ ! -L "$E/out_stale/data.kpp" ]'
check "... and links the new input dir" '[ "$(readlink "$E/out_stale/data")" = "../input_nokpp/data" ]'

# input.<X> is layered over input/ (testreport linkdata)
run_cmd ./experiment_run_no_compile.sh exp_mpi input.alt -output out_alt2
check "input.alt: files from input.alt take precedence" '[ "$(readlink "$E/out_alt2/data")" = "../input.alt/data" ]'
check "input.alt: files missing from input.alt come from input" '[ "$(readlink "$E/out_alt2/bathy.bin")" = "../input/bathy.bin" ]'
check "serial run does not use *.mpi variants" '[ "$(readlink "$E/out_alt2/data.exch2")" = "../input/data.exch2" ]'

# Bug: model failures were reported as success
MOCK_RUN=abnormal run_cmd ./experiment_run_no_compile.sh exp_mpi -output out_fail
check "STOP ABNORMAL END gives non-zero exit" '[ $RC -ne 0 ] && out_has "did not end normally"'
MOCK_RUN=crash run_cmd ./experiment_run_no_compile.sh exp_mpi -output out_fail
check "crashing binary gives non-zero exit" '[ $RC -ne 0 ] && out_has "exit status: 139"'

# Bug: MPI process count was not checked
run_cmd ./experiment_run_no_compile.sh exp_mpi -mpi 2
check "serial build + -mpi is rejected" '[ $RC -ne 0 ] && out_has "compiled without MPI"'
run_cmd ./experiment_compile.sh exp_mpi -mpi -j 2
run_cmd ./experiment_run_no_compile.sh exp_mpi -mpi 2
check "MPI build (4 procs) + -mpi 2 is rejected with a hint" '[ $RC -ne 0 ] && out_has "-mpi 4"'
run_cmd ./experiment_run_no_compile.sh exp_mpi
check "MPI build run without -mpi is rejected" '[ $RC -ne 0 ] && out_has "compiled with MPI for 4"'
run_cmd ./experiment_run_no_compile.sh exp_mpi -mpi 4 -output out_mpi2
check "MPI build + -mpi 4 succeeds" '[ $RC -eq 0 ]'
check "MPI run: output.txt is a copy of STDOUT.0000" 'cmp -s "$E/out_mpi2/output.txt" "$E/out_mpi2/STDOUT.0000"'
check "MPI run: data.exch2.mpi replaces data.exch2" '[ "$(readlink "$E/out_mpi2/data.exch2")" = "../input/data.exch2.mpi" ]'
check "MPI run: mpirun is called with -np 4" 'grep -q "mpirun --oversubscribe -np 4" "$MOCK_DOCKER_LOG"'

# Bug: options without values exited silently
run_cmd ./experiment_run_no_compile.sh exp_mpi -mpi
check "-mpi without N prints an error" '[ $RC -ne 0 ] && out_has "-mpi requires"'
run_cmd ./experiment_run_no_compile.sh exp_mpi -output
check "-output without value prints an error" '[ $RC -ne 0 ] && out_has "requires a value"'
run_cmd ./experiment_run_no_compile.sh exp_nonexistent
check "unknown experiment: clean error, no 'basename: missing operand'" '[ $RC -ne 0 ] && out_has "(none found)" && ! out_has "missing operand"'

# ---------------------------------------------------------------------------
echo ""
echo "=== docker_run_interactive.sh ==="
# ---------------------------------------------------------------------------
mkdir -p "$SANDBOX/home/.ssh" "$SANDBOX/taf"; touch "$SANDBOX/taf/staf"
: > "$MOCK_DOCKER_LOG"
HOME="$SANDBOX/home" run_cmd ./docker_run_interactive.sh -taf_dir "$SANDBOX/taf"
# Bug: ~/.ssh was mounted read-write although documented as read-only
check "-taf_dir mounts ~/.ssh read-only (:ro)" 'grep -q "/home/mitgcm/.ssh:ro" "$MOCK_DOCKER_LOG"'
check "-taf_dir puts /taf first on PATH" 'grep -q "PATH=/taf:" "$MOCK_DOCKER_LOG"'
check "non-terminal stdin uses 'docker run -i' (not -it)" 'grep -q "run --rm -i " "$MOCK_DOCKER_LOG"'
check "OPTFILE is passed into the container" 'grep -q "OPTFILE=/mitgcm/tools/build_options/linux_" "$MOCK_DOCKER_LOG"'
check "MITgcm root is mounted at /mitgcm" 'grep -q -- "-v $MITGCM:/mitgcm" "$MOCK_DOCKER_LOG"'

# Bug: fallback image build lacked the architecture-specific build setup
: > "$MOCK_DOCKER_LOG"
MOCK_IMAGE_MISSING=1 run_cmd ./docker_run_interactive.sh
check "missing image is built via docker_build.sh (repo Dockerfile)" 'grep -q "^build -t mitgcm:latest -f Dockerfile" "$MOCK_DOCKER_LOG" && out_has "Building Docker image"'

mkdir -p "$SANDBOX/code_links"; ln -s "$E/code/SIZE.h" "$SANDBOX/code_links/SIZE.h"
run_cmd ./docker_run_interactive.sh -code "$SANDBOX/code_links" -dereference
check "-dereference removes its temp dir on exit" 'out_has "Removed:" && [ -z "$(ls -A "$TMPDIR")" ]'

run_cmd ./docker_run_interactive.sh -h
check "-h prints help" '[ $RC -eq 0 ] && out_has "USAGE"'

# ---------------------------------------------------------------------------
echo ""
echo "=== Dockerfile / docker_build.sh / setup_links.sh ==="
# ---------------------------------------------------------------------------
check "Dockerfile has no hard-coded aarch64 MPI default" '! grep -q "aarch64-linux-gnu" "$PROJECT_ROOT/Dockerfile"'
check "Dockerfile derives the OpenMPI include dir from uname -m" 'grep -q "uname -m)-linux-gnu/openmpi/include" "$PROJECT_ROOT/Dockerfile"'
: > "$MOCK_DOCKER_LOG"
run_cmd ./docker_build.sh
check "docker_build.sh builds mitgcm:latest from the repo Dockerfile" '[ $RC -eq 0 ] && grep -q "^build -t mitgcm:latest -f Dockerfile" "$MOCK_DOCKER_LOG"'
check "setup_links.sh linked all scripts" 'for s in experiment_compile.sh experiment_run_no_compile.sh docker_build.sh docker_run_interactive.sh compare_results.sh; do [ -L "$VER/$s" ] || exit 1; done'
run_cmd "$SCRIPTS_DIR/setup_links.sh" "$VER"
check "setup_links.sh is idempotent" '[ $RC -eq 0 ] && out_has "already linked"'

# ---------------------------------------------------------------------------
echo ""
echo "=== README consistency ==="
# ---------------------------------------------------------------------------
README="$PROJECT_ROOT/README.md"
check "README does not promise incremental compilation" '! grep -qi "incremental" "$README"'
check "README documents --match default of 10" 'grep -q "default \`10\`" "$README"'
check "README does not claim a host gcc is not needed while requiring it" '! grep -q "tr_cmpnum" "$README"'
check "README MPI section uses -mpi 4 for tutorial_barotropic_gyre" 'grep -q "tutorial_barotropic_gyre -mpi 4" "$README"'
check "README -mods example copies the full code/ directory" 'grep -q "cp -r lab_sea/code" "$README"'

# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "  Total:  $test_count"
echo -e "  ${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "  ${RED}Failed: $fail_count${NC}"
    exit 1
fi
echo "  Failed: 0"
echo ""
echo -e "${GREEN}All regression tests passed!${NC}"
exit 0

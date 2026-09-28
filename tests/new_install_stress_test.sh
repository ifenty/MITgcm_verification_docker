#!/bin/bash
#
# New-install stress test for MITgcm_verification_docker.
#
# Clones MITgcm into a fresh work directory, installs these tools into it the
# way a new user would (setup_links.sh, docker_build.sh), then exercises every
# documented behaviour with real Docker builds and runs, and cross-checks
# compare_results.sh against MITgcm's own testreport.
#
# Documentation (options, check catalogue, output format, triage):
#   VERIFY_NEW_INSTALL_README.md (repository root)
#
# Exit status: 0 = all checks passed (skips allowed), 1 = at least one check
# failed, 2 = could not start (bad options or missing prerequisites).

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

MITGCM_SRC="https://github.com/MITgcm/MITgcm.git"
MITGCM_REF=""
WORKDIR=""
JOBS=""
SKIP_BUILD=false
CLEANUP=false
TAF_DIR=""
GROUPS_SELECTED="SER MPI INP CMP MOD INT TAF"
ALL_GROUPS="SER MPI INP CMP MOD INT TAF"

# Experiments used (all small; each compiles in well under a minute)
EXP_SERIAL="1D_ocean_ice_column"          # serial, seaice/kpp, tr_checklist hSIav
EXP_MPI="tutorial_barotropic_gyre"        # SIZE.h_mpi 2x2 = 4 processes
EXP_INPUT="adjustment.cs-32x32x1"         # prepare_run + input.nlfs + data.exch2.mpi
EXP_TAF="1D_ocean_ice_column"             # code_ad/ + input_ad/, adjoint and TLM references

usage() {
    cat <<EOF
Usage: $0 [options]

End-to-end "new install" test: fresh MITgcm clone -> setup_links.sh ->
docker_build.sh -> compile/run/compare real experiments -> verify results
against testreport. See VERIFY_NEW_INSTALL_README.md.

Options:
  --mitgcm-src <url|path>  MITgcm git repository to clone
                           (default: $MITGCM_SRC)
  --mitgcm-ref <ref>       Branch or tag to check out (default: repository default)
  --workdir <dir>          Work directory (default: new temp dir). Must not
                           already contain a MITgcm/ subdirectory.
  --jobs <N>               make -j value (default: CPUs available, max 16)
  --groups <G,G,...>       Only run these check groups: $ALL_GROUPS
                           (PRE, INS and FIN always run; CMP implies SER)
  --skip-build             Reuse the existing mitgcm:latest image instead of
                           running docker_build.sh (INS-05 then only verifies it)
  --taf-dir <path>         TAF installation (directory holding staf) for the TAF
                           group; without it the TAF checks are skipped. Needs a
                           working TAF server key in ~/.ssh.
  --cleanup                Delete the MITgcm clone at the end if every check
                           passed (logs and summaries are kept)
  --list                   List all checks and exit
  -h, --help               Show this help

Outputs (in the work directory):
  summary.tsv   one line per check: id, status, seconds, description, detail
  summary.json  the same, as JSON
  logs/<ID>.log full output of each check
EOF
}

list_checks() {
    cat <<'EOF'
ID      GROUP  DESCRIPTION
PRE-01  PRE    Prerequisites: docker daemon reachable, git available
INS-01  INS    Fresh MITgcm clone
INS-02  INS    setup_links.sh installs script symlinks and README link (no Dockerfile copy)
INS-03  INS    setup_links.sh re-run is idempotent
INS-04  INS    Every script's -h/--help exits 0 and prints usage
INS-05  INS    docker_build.sh builds mitgcm:latest with gfortran, mpirun, MPI headers
SER-01  SER    Serial compile: binary, compile.log, build_info.txt, no tr_* leftovers
SER-02  SER    Serial run: exit 0, "Execution ended Normally", run_info.txt
SER-03  SER    compare_results.sh PASS and digits == testreport's digits
MPI-01  MPI    MPI compile: NPROCS = nPx*nPy from SIZE.h_mpi, code/ untouched
MPI-02  MPI    MPI run with -mpi N: normal end, N STDOUT files, output.txt = STDOUT.0000
MPI-03  MPI    MPI compare PASS and digits == testreport -MPI=N digits
MPI-04  MPI    Wrong -mpi N and missing -mpi are rejected with the right hint
INP-01  INP    prepare_run is executed; compare == testreport for input/
INP-02  INP    input.nlfs layered over input/; compared with output.nlfs.txt == testreport
INP-03  INP    Re-using an output dir with another input dir cannot reuse stale inputs;
               a model error gives a non-zero exit
CMP-01  CMP    compare_results.sh negative controls: 1% perturbed, truncated,
               NaN and empty output all FAIL; identical copy PASSes
CMP-02  CMP    compare_results.sh works when run from outside verification/
MOD-01  MOD    -mods (symlinks + instrumented source) with -build/-output: change is
               compiled in, code/ restored, code_validation/ saved, temp dir removed
MOD-02  MOD    -mods with a compile error: non-zero exit, code/ restored, temp removed
MOD-03  MOD    -mods with a nonexistent directory is rejected and nothing is created
INT-01  INT    docker_run_interactive.sh with piped commands: mounts, OPTFILE,
               a manual genmake2/make build works
INT-02  INT    -code with symlinks: dangling without -dereference, real files with it
INT-03  INT    -taf_dir: staf on PATH, ~/.ssh mounted read-only
TAF-01  TAF    -adm compile (real TAF, needs --taf-dir): mitgcmuv_ad, KIND=adm,
               code_ad/ untouched, no tr_* leftovers
TAF-02  TAF    -adm run + compare PASS and digits == testreport -adm digits
TAF-03  TAF    -tlm compile/run + compare PASS and digits == testreport -tlm digits
FIN-01  FIN    MITgcm clone left clean: no tracked-file changes, no code*_orig/, no tr_* dirs
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mitgcm-src) MITGCM_SRC="$2"; shift 2 ;;
        --mitgcm-ref) MITGCM_REF="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --groups) GROUPS_SELECTED="$(echo "$2" | tr ',' ' ' | tr '[:lower:]' '[:upper:]')"; shift 2 ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --taf-dir) TAF_DIR="$2"; shift 2 ;;
        --cleanup) CLEANUP=true; shift ;;
        --list) list_checks; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; echo "Try '$0 --help'"; exit 2 ;;
    esac
done

for g in $GROUPS_SELECTED; do
    [[ " $ALL_GROUPS " == *" $g "* ]] || { echo "Unknown group: $g (valid: $ALL_GROUPS)"; exit 2; }
done
[[ " $GROUPS_SELECTED " == *" CMP "* && " $GROUPS_SELECTED " != *" SER "* ]] && GROUPS_SELECTED="SER $GROUPS_SELECTED"

if [ -n "$TAF_DIR" ]; then
    [[ "$TAF_DIR" == /* ]] || TAF_DIR="$(cd "$TAF_DIR" 2>/dev/null && pwd)"
    [ -x "$TAF_DIR/staf" ] || { echo "--taf-dir: no executable staf in '$TAF_DIR'"; exit 2; }
fi
# testreport oracle runs of TAF builds need TAF and the TAF server key
TAF_DOCKER_ARGS=()
[ -n "$TAF_DIR" ] && TAF_DOCKER_ARGS=(-v "$TAF_DIR:/taf" -v "$HOME/.ssh:/home/mitgcm/.ssh:ro"
    -e "PATH=/taf:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mitgcm/tools")

if [ -z "$JOBS" ]; then
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    [ "$JOBS" -gt 16 ] && JOBS=16
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "--jobs must be a positive integer"; exit 2; }

if [ -z "$WORKDIR" ]; then
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/mitgcm_stress.XXXXXX")"
else
    mkdir -p "$WORKDIR" || exit 2
    WORKDIR="$(cd "$WORKDIR" && pwd)"
    if [ -e "$WORKDIR/MITgcm" ]; then
        echo "Error: $WORKDIR/MITgcm already exists; choose an empty --workdir"
        exit 2
    fi
fi

MITGCM="$WORKDIR/MITgcm"
V="$MITGCM/verification"
LOGS="$WORKDIR/logs"
FIX="$WORKDIR/fixtures"
SUMMARY_TSV="$WORKDIR/summary.tsv"
SUMMARY_JSON="$WORKDIR/summary.json"
mkdir -p "$LOGS" "$FIX" "$WORKDIR/tmp"
# Scripts create temp dirs under $TMPDIR; keep them where leftovers can be checked
export TMPDIR="$WORKDIR/tmp"

case "$(uname -m)" in
    arm64|aarch64) OPTFILE_NAME="linux_arm64_gfortran" ;;
    *)             OPTFILE_NAME="linux_amd64_gfortran" ;;
esac

# ---------------------------------------------------------------------------
# Framework
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
[ -t 1 ] || { GREEN=''; RED=''; YELLOW=''; NC=''; }

N_PASS=0; N_FAIL=0; N_SKIP=0
printf 'id\tstatus\tseconds\tdescription\tdetail\n' > "$SUMMARY_TSV"
JSON_ROWS=""

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\n' '  '; }

# status lookup without associative arrays (bash 3.2 compatible)
set_status() { eval "STATUS_${1//-/_}=$2"; }
get_status() { eval "echo \${STATUS_${1//-/_}:-NOTRUN}"; }

# run_check <ID> <group> <description> <function> [required check IDs...]
run_check() {
    local id="$1" group="$2" desc="$3" fn="$4"; shift 4
    local status detail="" start end secs dep
    DETAIL=""
    if [[ "$group" != PRE && "$group" != INS && "$group" != FIN && " $GROUPS_SELECTED " != *" $group "* ]]; then
        status=SKIP; detail="group $group not selected"
    elif [ "$group" = TAF ] && [ -z "$TAF_DIR" ]; then
        status=SKIP; detail="needs --taf-dir <path>"
    else
        for dep in "$@"; do
            if [ "$(get_status "$dep")" != PASS ]; then
                status=SKIP; detail="requires $dep ($(get_status "$dep"))"
                break
            fi
        done
    fi
    start=$(date +%s)
    if [ -z "$status" ]; then
        printf '%-7s %s ... ' "$id" "$desc"
        {
            echo "### $id: $desc"
            echo "### started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$LOGS/$id.log"
        if "$fn" >> "$LOGS/$id.log" 2>&1; then
            status=PASS
        else
            status=FAIL
        fi
        detail="$DETAIL"
        echo "### result: $status ${detail}" >> "$LOGS/$id.log"
    else
        printf '%-7s %s ... ' "$id" "$desc"
    fi
    end=$(date +%s); secs=$((end - start))
    set_status "$id" "$status"
    case $status in
        PASS) N_PASS=$((N_PASS + 1)); echo -e "${GREEN}PASS${NC} (${secs}s)${detail:+  $detail}" ;;
        FAIL) N_FAIL=$((N_FAIL + 1)); echo -e "${RED}FAIL${NC} (${secs}s)  ${detail}  [log: logs/$id.log]" ;;
        SKIP) N_SKIP=$((N_SKIP + 1)); echo -e "${YELLOW}SKIP${NC}  $detail" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$secs" "$desc" "$(printf '%s' "$detail" | tr '\t\n' '  ')" >> "$SUMMARY_TSV"
    JSON_ROWS="$JSON_ROWS${JSON_ROWS:+,
}    {\"id\": \"$id\", \"group\": \"$group\", \"status\": \"$status\", \"seconds\": $secs, \"description\": \"$(json_escape "$desc")\", \"detail\": \"$(json_escape "$detail")\", \"log\": \"logs/$id.log\"}"
}

# fail <message>: record why a check failed (use as: cond || fail "msg" || return 1)
fail() { DETAIL="$1"; echo "CHECK FAILED: $1"; return 1; }

# note <message>: informational detail for a passing check
note() { DETAIL="$1"; echo "NOTE: $1"; }

# Run a command, logging it; returns its exit status
x() { echo "+ $*"; "$@"; }

# Digits reported by compare_results.sh output file ("N/O" if none)
digits_of() { sed -n 's/^ *Matching digits: \([0-9N/O]*\).*/\1/p' "$1" | head -1; }

# testreport oracle: prints "<test-name> <digits>" for each test it ran.
# $1 experiment, $2.. extra testreport arguments
# Log: logs/oracle_<exp>.log, or logs/oracle_<exp>_<kind>.log for -adm / -tlm
oracle() {
    local exp="$1"; shift
    local log="$LOGS/oracle_${exp}.log"
    [[ " $* " == *" -adm "* ]] && log="$LOGS/oracle_${exp}_adm.log"
    [[ " $* " == *" -tlm "* ]] && log="$LOGS/oracle_${exp}_tlm.log"
    docker run --rm -v "$MITGCM:/mitgcm" "${TAF_DOCKER_ARGS[@]}" mitgcm:latest bash -c "
        cd /mitgcm/verification
        ./testreport -t $exp -optfile /mitgcm/tools/build_options/$OPTFILE_NAME -j $JOBS $* > /tmp/tr.log 2>&1
        cat /tmp/tr.log
        rm -rf tr_\$(hostname)_*
    " > "$log" 2>&1
    # summary lines look like: "Y Y Y Y>13<16 16 ... pass  tutorial_barotropic_gyre"
    # (adjoint runs append "  (e=0, w=0, ...)", which is dropped first)
    sed 's/  *(e=.*)$//' "$log" | awk 'NF >= 2 && ($(NF-1) == "pass" || $(NF-1) == "FAIL" || $(NF-1) == "N/O") && match($0, />[ 0-9]+</) {
            d = substr($0, RSTART + 1, RLENGTH - 2); gsub(/ /, "", d); print $NF, d }'
}

# Lookup from oracle output: $1 = oracle lines, $2 = test name
oracle_digits() { echo "$1" | awk -v n="$2" '$1 == n { print $2 }'; }

git_tracked_changes() { git -C "$MITGCM" status --porcelain --untracked-files=no; }

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_PRE_01() {
    x docker info > /dev/null || fail "docker daemon not reachable (is Docker running?)" || return 1
    x git --version || fail "git not found" || return 1
    x bash --version | head -1
    note "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null), arch $(uname -m), jobs $JOBS"
}

check_INS_01() {
    local args=(--depth 1)
    [ -n "$MITGCM_REF" ] && args+=(--branch "$MITGCM_REF")
    local src="$MITGCM_SRC"
    # --depth needs a URL for local repositories
    [ -d "$src" ] && src="file://$(cd "$src" && pwd)"
    x git clone "${args[@]}" "$src" "$MITGCM" || fail "git clone failed: $MITGCM_SRC" || return 1
    [ -d "$V/$EXP_SERIAL" ] || fail "clone has no verification/$EXP_SERIAL" || return 1
    note "MITgcm $(git -C "$MITGCM" rev-parse --short HEAD) from $MITGCM_SRC"
}

check_INS_02() {
    x "$REPO_ROOT/scripts/setup_links.sh" "$V" < /dev/null || fail "setup_links.sh exited non-zero" || return 1
    local s
    for s in experiment_compile.sh experiment_run_no_compile.sh docker_build.sh docker_run_interactive.sh compare_results.sh; do
        [ -L "$V/$s" ] && [ -x "$V/$s" ] || fail "$s not linked" || return 1
        [ "$(readlink "$V/$s")" = "$REPO_ROOT/scripts/$s" ] || fail "$s links to $(readlink "$V/$s")" || return 1
    done
    # docker_build.sh builds from the repo's Dockerfile; no copy belongs here
    [ ! -e "$V/Dockerfile" ] || fail "a Dockerfile was copied into verification/" || return 1
    # MITgcm ships its own verification/README.md; setup_links must not replace it
    [ -e "$V/README.md" ] || fail "README.md missing" || return 1
}

check_INS_03() {
    x "$REPO_ROOT/scripts/setup_links.sh" "$V" < /dev/null > "$FIX/setup2.log" 2>&1 || { cat "$FIX/setup2.log"; fail "second run exited non-zero"; return 1; }
    cat "$FIX/setup2.log"
    grep -q "already linked" "$FIX/setup2.log" || fail "second run did not report existing links" || return 1
}

check_INS_04() {
    local s
    cd "$V" || return 1
    for s in experiment_compile.sh experiment_run_no_compile.sh docker_build.sh docker_run_interactive.sh compare_results.sh; do
        for h in -h --help; do
            ./$s $h > "$FIX/help.txt" 2>&1 < /dev/null || { cat "$FIX/help.txt"; fail "$s $h exited non-zero"; return 1; }
            grep -qiE "usage" "$FIX/help.txt" || fail "$s $h printed no usage" || return 1
        done
    done
    "$REPO_ROOT/scripts/setup_links.sh" -h > "$FIX/help.txt" 2>&1 || fail "setup_links.sh -h exited non-zero" || return 1
}

check_INS_05() {
    cd "$V" || return 1
    if [ "$SKIP_BUILD" = true ]; then
        x docker image inspect mitgcm:latest > /dev/null || fail "--skip-build given but mitgcm:latest does not exist" || return 1
        note "image not rebuilt (--skip-build)"
    else
        x ./docker_build.sh || fail "docker_build.sh failed" || return 1
    fi
    x docker run --rm mitgcm:latest bash -c 'gfortran --version | head -1; mpirun --version | head -1; test -f "$MPI_INC_DIR/mpi.h" && echo "mpi.h found in $MPI_INC_DIR"' > "$FIX/image.txt" 2>&1
    cat "$FIX/image.txt"
    grep -q "GNU Fortran" "$FIX/image.txt" || fail "gfortran missing in image" || return 1
    grep -q "Open MPI" "$FIX/image.txt" || fail "mpirun missing in image" || return 1
    grep -q "mpi.h found" "$FIX/image.txt" || fail "MPI_INC_DIR does not contain mpi.h" || return 1
}

check_SER_01() {
    cd "$V" || return 1
    x ./experiment_compile.sh "$EXP_SERIAL" -j "$JOBS" || fail "compile exited non-zero" || return 1
    local b="$V/$EXP_SERIAL/build_docker"
    [ -x "$b/mitgcmuv" ] || fail "no binary in build_docker/" || return 1
    [ -s "$b/compile.log" ] || fail "no compile.log" || return 1
    grep -q "^MPI=false" "$b/build_info.txt" || fail "build_info.txt missing or not MPI=false" || return 1
    [ -z "$(find "$V" -maxdepth 1 -type d -name 'tr_*')" ] || fail "testreport tr_* directories left in verification/" || return 1
}

check_SER_02() {
    cd "$V" || return 1
    x ./experiment_run_no_compile.sh "$EXP_SERIAL" || fail "run exited non-zero" || return 1
    local o="$V/$EXP_SERIAL/output_docker"
    grep -q "Execution ended Normally" "$o/output.txt" || fail "output.txt lacks 'Execution ended Normally'" || return 1
    grep -q "^INPUT_DIR=input$" "$o/run_info.txt" || fail "run_info.txt missing" || return 1
}

check_SER_03() {
    cd "$V" || return 1
    ./compare_results.sh "$EXP_SERIAL" > "$FIX/ser_cmp.txt" 2>&1; local rc=$?
    cat "$FIX/ser_cmp.txt"
    [ $rc -eq 0 ] || fail "compare_results.sh FAIL (digits $(digits_of "$FIX/ser_cmp.txt"))" || return 1
    local ours ref orc
    ours="$(digits_of "$FIX/ser_cmp.txt")"
    orc="$(oracle "$EXP_SERIAL")"; echo "oracle: $orc"
    ref="$(oracle_digits "$orc" "$EXP_SERIAL")"
    [ -n "$ref" ] || fail "testreport produced no result (see logs/oracle_$EXP_SERIAL.log)" || return 1
    [ "$ours" = "$ref" ] || fail "compare_results.sh says $ours digits, testreport says $ref" || return 1
    note "$ours digits (testreport: $ref)"
}

MPI_NPROCS=""
check_MPI_01() {
    cd "$V" || return 1
    local sz="$V/$EXP_MPI/code/SIZE.h_mpi" npx npy
    npx=$(grep "^ *& *nPx *=" "$sz" | sed 's/.*= *//; s/[^0-9].*//')
    npy=$(grep "^ *& *nPy *=" "$sz" | sed 's/.*= *//; s/[^0-9].*//')
    MPI_NPROCS=$((npx * npy))
    echo "SIZE.h_mpi: nPx=$npx nPy=$npy -> $MPI_NPROCS processes"
    x ./experiment_compile.sh "$EXP_MPI" -mpi -j "$JOBS" > "$FIX/mpi_compile.txt" 2>&1; local rc=$?
    cat "$FIX/mpi_compile.txt"
    [ $rc -eq 0 ] || fail "MPI compile exited non-zero" || return 1
    local info="$V/$EXP_MPI/build_docker/build_info.txt"
    grep -q "^MPI=true" "$info" || fail "build_info.txt not MPI=true" || return 1
    grep -q "^NPROCS=$MPI_NPROCS$" "$info" || fail "build_info.txt NPROCS != $MPI_NPROCS" || return 1
    grep -q "experiment_run_no_compile.sh $EXP_MPI -mpi $MPI_NPROCS" "$FIX/mpi_compile.txt" || fail "next-step hint lacks -mpi $MPI_NPROCS" || return 1
    [ -z "$(git_tracked_changes | grep "$EXP_MPI/code")" ] || fail "MPI compile modified tracked files in $EXP_MPI/code: $(git_tracked_changes)" || return 1
    note "$MPI_NPROCS processes"
}

check_MPI_02() {
    cd "$V" || return 1
    x ./experiment_run_no_compile.sh "$EXP_MPI" -mpi "$MPI_NPROCS" || fail "MPI run exited non-zero" || return 1
    local o="$V/$EXP_MPI/output_docker" n
    n=$(ls "$o"/STDOUT.* 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" = "$MPI_NPROCS" ] || fail "$n STDOUT files, expected $MPI_NPROCS" || return 1
    cmp -s "$o/output.txt" "$o/STDOUT.0000" || fail "output.txt is not a copy of STDOUT.0000" || return 1
    grep -q "Execution ended Normally" "$o/output.txt" || fail "model did not end normally" || return 1
}

check_MPI_03() {
    cd "$V" || return 1
    ./compare_results.sh "$EXP_MPI" > "$FIX/mpi_cmp.txt" 2>&1; local rc=$?
    cat "$FIX/mpi_cmp.txt"
    [ $rc -eq 0 ] || fail "compare_results.sh FAIL (digits $(digits_of "$FIX/mpi_cmp.txt"))" || return 1
    local ours ref orc
    ours="$(digits_of "$FIX/mpi_cmp.txt")"
    orc="$(oracle "$EXP_MPI" "-MPI=$MPI_NPROCS" "-command 'mpirun --oversubscribe -np TR_NPROC ./mitgcmuv'")"; echo "oracle: $orc"
    ref="$(oracle_digits "$orc" "$EXP_MPI")"
    [ -n "$ref" ] || fail "testreport produced no result (see logs/oracle_$EXP_MPI.log)" || return 1
    [ "$ours" = "$ref" ] || fail "compare_results.sh says $ours digits, testreport says $ref" || return 1
    note "$ours digits (testreport: $ref)"
}

check_MPI_04() {
    cd "$V" || return 1
    local wrong=$((MPI_NPROCS == 2 ? 3 : 2))
    ./experiment_run_no_compile.sh "$EXP_MPI" -mpi "$wrong" -output output_stress_wrongnp > "$FIX/w.txt" 2>&1 && { cat "$FIX/w.txt"; fail "-mpi $wrong was accepted"; return 1; }
    cat "$FIX/w.txt"
    grep -q -- "-mpi $MPI_NPROCS" "$FIX/w.txt" || fail "error does not suggest -mpi $MPI_NPROCS" || return 1
    ./experiment_run_no_compile.sh "$EXP_MPI" -output output_stress_wrongnp > "$FIX/w.txt" 2>&1 && { cat "$FIX/w.txt"; fail "MPI build run without -mpi was accepted"; return 1; }
    cat "$FIX/w.txt"
    grep -q "compiled with MPI" "$FIX/w.txt" || fail "no 'compiled with MPI' error" || return 1
}

INP_ORACLE=""
check_INP_01() {
    cd "$V" || return 1
    x ./experiment_compile.sh "$EXP_INPUT" -j "$JOBS" || fail "compile exited non-zero" || return 1
    x ./experiment_run_no_compile.sh "$EXP_INPUT" || fail "run exited non-zero" || return 1
    local o="$V/$EXP_INPUT/output_docker"
    if [ -f "$V/$EXP_INPUT/input/prepare_run" ]; then
        [ -L "$o/tile001.mitgrid" ] && [ -e "$o/tile001.mitgrid" ] || fail "prepare_run did not link tile001.mitgrid" || return 1
    fi
    ./compare_results.sh "$EXP_INPUT" > "$FIX/inp_cmp.txt" 2>&1; local rc=$?
    cat "$FIX/inp_cmp.txt"
    [ $rc -eq 0 ] || fail "compare FAIL" || return 1
    INP_ORACLE="$(oracle "$EXP_INPUT")"; echo "oracle: $INP_ORACLE"
    local ours ref
    ours="$(digits_of "$FIX/inp_cmp.txt")"; ref="$(oracle_digits "$INP_ORACLE" "$EXP_INPUT")"
    [ -n "$ref" ] || fail "testreport produced no result" || return 1
    [ "$ours" = "$ref" ] || fail "compare_results.sh says $ours digits, testreport says $ref" || return 1
    note "$ours digits (testreport: $ref)"
}

check_INP_02() {
    cd "$V" || return 1
    x ./experiment_run_no_compile.sh "$EXP_INPUT" input.nlfs -output output_stress_nlfs || fail "input.nlfs run exited non-zero" || return 1
    local o="$V/$EXP_INPUT/output_stress_nlfs"
    [ "$(readlink "$o/data")" = "../input.nlfs/data" ] || fail "data not taken from input.nlfs" || return 1
    [ "$(readlink "$o/bathy_f2.bin")" = "../input/bathy_f2.bin" ] || fail "bathy_f2.bin not taken from input/" || return 1
    ./compare_results.sh "$EXP_INPUT" output_stress_nlfs > "$FIX/nlfs_cmp.txt" 2>&1; local rc=$?
    cat "$FIX/nlfs_cmp.txt"
    grep -q "results/output.nlfs.txt" "$FIX/nlfs_cmp.txt" || fail "not compared against results/output.nlfs.txt" || return 1
    [ $rc -eq 0 ] || fail "compare FAIL" || return 1
    local ours ref
    ours="$(digits_of "$FIX/nlfs_cmp.txt")"; ref="$(oracle_digits "$INP_ORACLE" "$EXP_INPUT.nlfs")"
    [ -n "$ref" ] || fail "no testreport result for $EXP_INPUT.nlfs" || return 1
    [ "$ours" = "$ref" ] || fail "compare_results.sh says $ours digits, testreport says $ref" || return 1
    note "$ours digits (testreport: $ref)"
}

check_INP_03() {
    cd "$V" || return 1
    local e="$V/$EXP_SERIAL"
    rm -rf "$e/input_stress_nokpp"
    cp -r "$e/input" "$e/input_stress_nokpp" && rm -f "$e/input_stress_nokpp/data.kpp"
    x ./experiment_run_no_compile.sh "$EXP_SERIAL" -output output_stress_stale || fail "first run failed" || return 1
    [ -L "$e/output_stress_stale/data.kpp" ] || fail "first run did not link data.kpp" || return 1
    x ./experiment_run_no_compile.sh "$EXP_SERIAL" input_stress_nokpp -output output_stress_stale > "$FIX/stale.txt" 2>&1; local rc=$?
    cat "$FIX/stale.txt"
    [ ! -e "$e/output_stress_stale/data.kpp" ] || fail "data.kpp from the previous input dir is still present" || return 1
    [ $rc -ne 0 ] || fail "model without data.kpp should fail, but the script exited 0" || return 1
    grep -q "did not end normally" "$FIX/stale.txt" || fail "no 'did not end normally' message" || return 1
    grep -q "data.kpp" "$e/output_stress_stale/output.txt" || fail "failure is not about the missing data.kpp" || return 1
    rm -rf "$e/input_stress_nokpp"
}

check_CMP_01() {
    cd "$V" || return 1
    local e="$V/$EXP_SERIAL" src="$V/$EXP_SERIAL/output_docker/output.txt" d rc
    [ -f "$src" ] || fail "no serial output to derive controls from" || return 1
    for d in identical perturbed truncated nan empty; do mkdir -p "$e/output_stress_$d"; done
    cp "$src" "$e/output_stress_identical/output.txt"
    awk '/%MON/ { v = $NF + 0; if (v != 0) $NF = sprintf("%.13E", v * 1.01) } { print }' "$src" > "$e/output_stress_perturbed/output.txt"
    head -n $(( $(wc -l < "$src") / 2 )) "$src" > "$e/output_stress_truncated/output.txt"
    awk '/%MON/ { $NF = "NaN" } { print }' "$src" > "$e/output_stress_nan/output.txt"
    : > "$e/output_stress_empty/output.txt"
    ./compare_results.sh "$EXP_SERIAL" output_stress_identical > "$FIX/c.txt" 2>&1; rc=$?; cat "$FIX/c.txt"
    [ $rc -eq 0 ] || fail "identical copy did not PASS" || return 1
    for d in perturbed truncated nan empty; do
        ./compare_results.sh "$EXP_SERIAL" "output_stress_$d" > "$FIX/c.txt" 2>&1; rc=$?; cat "$FIX/c.txt"
        [ $rc -ne 0 ] || fail "$d output PASSED (must FAIL)" || return 1
    done
}

check_CMP_02() {
    cd "$WORKDIR" || return 1
    x "$V/compare_results.sh" "$EXP_SERIAL" || fail "compare from outside verification/ failed" || return 1
}

check_MOD_01() {
    cd "$V" || return 1
    local e="$V/$EXP_SERIAL" m="$FIX/mods_links" f last
    rm -rf "$m"; mkdir -p "$m"
    for f in "$e"/code/*; do ln -s "$f" "$m/"; done
    last=$(grep -n "^      RETURN" "$MITGCM/model/src/packages_boot.F" | tail -1 | cut -d: -f1)
    [ -n "$last" ] || fail "cannot find RETURN in packages_boot.F" || return 1
    awk -v l="$last" 'NR == l { print "      PRINT *, \"STRESS_TEST_MODS_MARKER\"" } { print }' \
        "$MITGCM/model/src/packages_boot.F" > "$m/packages_boot.F"
    x ./experiment_compile.sh "$EXP_SERIAL" -mods "$m" -build build_stress_mods -j "$JOBS" || fail "mods compile exited non-zero" || return 1
    [ -z "$(git_tracked_changes)" ] || fail "tracked files changed after -mods compile: $(git_tracked_changes)" || return 1
    [ ! -d "$e/code_orig" ] || fail "code_orig/ left behind" || return 1
    [ -f "$e/code_validation/packages_boot.F" ] && [ ! -L "$e/code_validation/SIZE.h" ] || fail "code_validation/ not saved with real files" || return 1
    [ -z "$(ls -A "$TMPDIR")" ] || fail "temp files left in \$TMPDIR: $(ls "$TMPDIR")" || return 1
    x ./experiment_run_no_compile.sh "$EXP_SERIAL" -build build_stress_mods -output output_stress_mods || fail "run of mods build failed" || return 1
    grep -q STRESS_TEST_MODS_MARKER "$e/output_stress_mods/output.txt" || fail "instrumented source was not compiled in" || return 1
    ! grep -q STRESS_TEST_MODS_MARKER "$e/output_docker/output.txt" || fail "default build contains the mods change" || return 1
    x ./compare_results.sh "$EXP_SERIAL" output_stress_mods || fail "mods run (print only) no longer matches reference" || return 1
}

check_MOD_02() {
    cd "$V" || return 1
    local e="$V/$EXP_SERIAL" m="$FIX/mods_broken"
    rm -rf "$m"; cp -RL "$FIX/mods_links" "$m" 2>/dev/null || cp -R "$e/code" "$m"
    ln -s "$e/code/SIZE.h" "$m/link_to_force_dereference.h"
    printf '      THIS IS NOT FORTRAN\n' > "$m/stress_broken.F"
    x ./experiment_compile.sh "$EXP_SERIAL" -mods "$m" -build build_stress_broken -j "$JOBS" && { fail "broken code compiled successfully"; return 1; }
    [ -z "$(git_tracked_changes)" ] || fail "tracked files changed after failed compile" || return 1
    [ ! -d "$e/code_orig" ] || fail "code_orig/ left behind after failed compile" || return 1
    [ ! -f "$e/code/stress_broken.F" ] || fail "code/ not restored after failed compile" || return 1
    [ -z "$(ls -A "$TMPDIR")" ] || fail "temp files left in \$TMPDIR after failed compile: $(ls "$TMPDIR")" || return 1
    [ -s "$e/build_stress_broken/compile.log" ] || fail "no compile.log for the failed build" || return 1
}

check_MOD_03() {
    cd "$V" || return 1
    local p="$WORKDIR/does_not_exist/mods"
    ./experiment_compile.sh "$EXP_SERIAL" -mods "$p" > "$FIX/m3.txt" 2>&1 && { cat "$FIX/m3.txt"; fail "nonexistent -mods accepted"; return 1; }
    cat "$FIX/m3.txt"
    grep -q "does not exist" "$FIX/m3.txt" || fail "no 'does not exist' error" || return 1
    [ ! -e "$WORKDIR/does_not_exist" ] || fail "nonexistent -mods path was created" || return 1
}

# Run piped commands through docker_run_interactive.sh; output lines tagged OUT
interactive() { printf '%s\n' "$1" | "$V/docker_run_interactive.sh" "${@:2}"; }

check_INT_01() {
    cd "$V" || return 1
    interactive 'echo "OUT pwd=$(pwd)"; echo "OUT optfile=$OPTFILE"; test -d /mitgcm/model && echo "OUT mitgcm_mounted"
mkdir -p /tmp/b && cd /tmp/b && genmake2 -rootdir=/mitgcm -mods=/mitgcm/verification/'"$EXP_MPI"'/code -optfile=$OPTFILE > g.log 2>&1 && make depend > d.log 2>&1 && make -j '"$JOBS"' > m.log 2>&1 && test -x mitgcmuv && echo "OUT manual_build_ok"' > "$FIX/int1.txt" 2>&1
    cat "$FIX/int1.txt"
    grep -q "OUT pwd=/mitgcm/verification" "$FIX/int1.txt" || fail "shell does not start in /mitgcm/verification" || return 1
    grep -q "OUT optfile=/mitgcm/tools/build_options/$OPTFILE_NAME" "$FIX/int1.txt" || fail "OPTFILE not set" || return 1
    grep -q "OUT mitgcm_mounted" "$FIX/int1.txt" || fail "MITgcm not mounted" || return 1
    grep -q "OUT manual_build_ok" "$FIX/int1.txt" || fail "manual genmake2/make build failed" || return 1
}

check_INT_02() {
    cd "$V" || return 1
    local c="$FIX/code_links" f
    rm -rf "$c"; mkdir -p "$c"
    for f in "$V/$EXP_MPI"/code/*; do ln -s "$f" "$c/"; done
    local cmd='for f in /custom_code/*; do if [ -L "$f" ] && [ ! -e "$f" ]; then echo "OUT dangling $f"; elif [ -f "$f" ] && [ ! -L "$f" ]; then echo "OUT real $f"; fi; done'
    interactive "$cmd" -code "$c" > "$FIX/int2a.txt" 2>&1; cat "$FIX/int2a.txt"
    grep -q "OUT dangling" "$FIX/int2a.txt" || fail "expected dangling symlinks without -dereference" || return 1
    interactive "$cmd" -code "$c" -dereference > "$FIX/int2b.txt" 2>&1; cat "$FIX/int2b.txt"
    grep -q "OUT dangling" "$FIX/int2b.txt" && { fail "dangling symlinks despite -dereference"; return 1; }
    grep -q "OUT real /custom_code/SIZE.h" "$FIX/int2b.txt" || fail "SIZE.h not a real file with -dereference" || return 1
    [ -z "$(ls -A "$TMPDIR")" ] || fail "dereference temp dir not removed: $(ls "$TMPDIR")" || return 1
}

check_INT_03() {
    cd "$V" || return 1
    local h="$FIX/home" t="$FIX/taf"
    mkdir -p "$h/.ssh" "$t"
    echo "fake key" > "$h/.ssh/id_stress_test"
    printf '#!/bin/bash\necho "MOCK STAF $*"\n' > "$t/staf"; chmod +x "$t/staf"
    HOME="$h" interactive 'echo "OUT staf=$(which staf)"; staf -v | sed "s/^/OUT /"; test -r /home/mitgcm/.ssh/id_stress_test && echo "OUT ssh_readable"; touch /home/mitgcm/.ssh/write_test 2>/dev/null && echo "OUT ssh_WRITABLE" || echo "OUT ssh_readonly"' -taf_dir "$t" > "$FIX/int3.txt" 2>&1
    cat "$FIX/int3.txt"
    grep -q "OUT staf=/taf/staf" "$FIX/int3.txt" || fail "staf not on PATH" || return 1
    grep -q "OUT MOCK STAF -v" "$FIX/int3.txt" || fail "staf did not run" || return 1
    grep -q "OUT ssh_readable" "$FIX/int3.txt" || fail "~/.ssh not readable in container" || return 1
    grep -q "OUT ssh_readonly" "$FIX/int3.txt" || fail "~/.ssh is writable in the container" || return 1
    [ ! -e "$h/.ssh/write_test" ] || fail "container wrote into ~/.ssh" || return 1
}

# TAF checks: $1 = adm | tlm
taf_compile() {
    local kind="$1" bin
    [ "$kind" = adm ] && bin=mitgcmuv_ad || bin=mitgcmuv_ftl
    x ./experiment_compile.sh "$EXP_TAF" -"$kind" -taf_dir "$TAF_DIR" -j "$JOBS" || fail "-$kind compile exited non-zero" || return 1
    local b="$V/$EXP_TAF/build_docker_$kind"
    [ -x "$b/$bin" ] || fail "no $bin in build_docker_$kind/" || return 1
    grep -q "^KIND=$kind$" "$b/build_info.txt" || fail "build_info.txt missing KIND=$kind" || return 1
    grep -qi "generated by TAF" "$b/compile.log" "$V/$EXP_TAF/build/make.tr_log" 2>/dev/null || \
        grep -q "staf" "$V/$EXP_TAF/build/make.tr_log" || fail "no sign of TAF in the build log" || return 1
    # tracked files unchanged and nothing added (a -mods swap would show here too)
    [ -z "$(git -C "$MITGCM" status --porcelain -- "verification/$EXP_TAF/code_ad")" ] || fail "code_ad/ changed during the build" || return 1
    [ -z "$(find "$V" -maxdepth 1 -type d -name 'tr_*')" ] || fail "testreport tr_* directories left in verification/" || return 1
}

taf_run_compare() {
    local kind="$1"
    x ./experiment_run_no_compile.sh "$EXP_TAF" -"$kind" || fail "-$kind run exited non-zero" || return 1
    local o="$V/$EXP_TAF/output_docker_$kind"
    grep -q "^KIND=$kind$" "$o/run_info.txt" || fail "run_info.txt missing KIND=$kind" || return 1
    grep -q "^INPUT_DIR=input_ad$" "$o/run_info.txt" || fail "run did not default to input_ad" || return 1
    ./compare_results.sh "$EXP_TAF" -"$kind" > "$FIX/taf_${kind}_cmp.txt" 2>&1; local rc=$?
    cat "$FIX/taf_${kind}_cmp.txt"
    [ $rc -eq 0 ] || fail "compare_results.sh -$kind FAIL (digits $(digits_of "$FIX/taf_${kind}_cmp.txt"))" || return 1
    grep -q "results/output_$kind.txt" "$FIX/taf_${kind}_cmp.txt" || fail "not compared with results/output_$kind.txt" || return 1
    local ours ref orc
    ours="$(digits_of "$FIX/taf_${kind}_cmp.txt")"
    orc="$(oracle "$EXP_TAF" -"$kind")"; echo "oracle: $orc"
    ref="$(oracle_digits "$orc" "$EXP_TAF")"
    [ -n "$ref" ] || fail "testreport -$kind produced no result (see logs/oracle_${EXP_TAF}_$kind.log)" || return 1
    [ "$ours" = "$ref" ] || fail "compare_results.sh says $ours digits, testreport -$kind says $ref" || return 1
    note "$ours digits (testreport -$kind: $ref)"
}

check_TAF_01() { cd "$V" || return 1; taf_compile adm; }
check_TAF_02() { cd "$V" || return 1; taf_run_compare adm; }
check_TAF_03() { cd "$V" || return 1; taf_compile tlm && taf_run_compare tlm; }

check_FIN_01() {
    [ -d "$MITGCM" ] || fail "no MITgcm clone" || return 1
    local changes; changes="$(git_tracked_changes)"
    echo "tracked changes: ${changes:-none}"
    [ -z "$changes" ] || fail "tracked files modified: $(echo $changes)" || return 1
    [ -z "$(find "$V" -maxdepth 2 -type d -name 'code*_orig')" ] || fail "code_orig/ or code_ad_orig/ directory left behind" || return 1
    [ -z "$(find "$V" -maxdepth 1 -type d -name 'tr_*')" ] || fail "tr_* directories left in verification/" || return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "=========================================="
echo "MITgcm_verification_docker new-install stress test"
echo "=========================================="
echo "  Repository: $REPO_ROOT ($(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')$(git -C "$REPO_ROOT" diff --quiet 2>/dev/null || echo ', with local changes'))"
echo "  MITgcm:     $MITGCM_SRC${MITGCM_REF:+ @ $MITGCM_REF}"
echo "  Work dir:   $WORKDIR"
echo "  Groups:     PRE INS $GROUPS_SELECTED FIN"
echo "  make -j:    $JOBS"
echo "=========================================="
STARTED=$(date +%s)

run_check PRE-01 PRE "Prerequisites (docker, git)"                         check_PRE_01
run_check INS-01 INS "Fresh MITgcm clone"                                  check_INS_01 PRE-01
run_check INS-02 INS "setup_links.sh installs tools"                       check_INS_02 INS-01
run_check INS-03 INS "setup_links.sh re-run is idempotent"                 check_INS_03 INS-02
run_check INS-04 INS "All scripts: -h/--help"                              check_INS_04 INS-02
run_check INS-05 INS "docker_build.sh builds a working image"              check_INS_05 INS-02
run_check SER-01 SER "Serial compile ($EXP_SERIAL)"                        check_SER_01 INS-05
run_check SER-02 SER "Serial run"                                          check_SER_02 SER-01
run_check SER-03 SER "Serial compare == testreport"                        check_SER_03 SER-02
run_check MPI-01 MPI "MPI compile ($EXP_MPI), code/ untouched"             check_MPI_01 INS-05
run_check MPI-02 MPI "MPI run with -mpi N"                                 check_MPI_02 MPI-01
run_check MPI-03 MPI "MPI compare == testreport -MPI=N"                    check_MPI_03 MPI-02
run_check MPI-04 MPI "Wrong/missing -mpi N rejected"                       check_MPI_04 MPI-01
run_check INP-01 INP "prepare_run + compare == testreport ($EXP_INPUT)"    check_INP_01 INS-05
run_check INP-02 INP "input.nlfs layering + compare == testreport"         check_INP_02 INP-01
run_check INP-03 INP "No stale inputs; model errors give non-zero exit"    check_INP_03 SER-01
run_check CMP-01 CMP "compare_results.sh negative controls"                check_CMP_01 SER-02
run_check CMP-02 CMP "compare_results.sh from outside verification/"       check_CMP_02 SER-02
run_check MOD-01 MOD "-mods with symlinks, -build, -output"                check_MOD_01 INS-05
run_check MOD-02 MOD "-mods compile error: code/ restored, no temp left"   check_MOD_02 INS-05
run_check MOD-03 MOD "-mods nonexistent dir rejected"                      check_MOD_03 INS-02
run_check INT-01 INT "Interactive (piped): mounts, OPTFILE, manual build"  check_INT_01 INS-05
run_check INT-02 INT "Interactive -code with/without -dereference"         check_INT_02 INS-05
run_check INT-03 INT "Interactive -taf_dir: staf on PATH, ~/.ssh read-only" check_INT_03 INS-05
run_check TAF-01 TAF "-adm compile with real TAF ($EXP_TAF)"              check_TAF_01 INS-05
run_check TAF-02 TAF "-adm run + compare == testreport -adm"              check_TAF_02 TAF-01
run_check TAF-03 TAF "-tlm compile/run + compare == testreport -tlm"      check_TAF_03 INS-05
run_check FIN-01 FIN "MITgcm clone left clean"                             check_FIN_01 INS-01

TOTAL_SECS=$(( $(date +%s) - STARTED ))
if [ $N_FAIL -gt 0 ]; then OVERALL=FAIL; else OVERALL=PASS; fi

cat > "$SUMMARY_JSON" <<EOF
{
  "overall": "$OVERALL",
  "passed": $N_PASS,
  "failed": $N_FAIL,
  "skipped": $N_SKIP,
  "seconds": $TOTAL_SECS,
  "workdir": "$(json_escape "$WORKDIR")",
  "repository_commit": "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)",
  "repository_dirty": $(git -C "$REPO_ROOT" diff --quiet 2>/dev/null && echo false || echo true),
  "mitgcm_source": "$(json_escape "$MITGCM_SRC")",
  "mitgcm_commit": "$(git -C "$MITGCM" rev-parse HEAD 2>/dev/null)",
  "arch": "$(uname -m)",
  "checks": [
$JSON_ROWS
  ]
}
EOF

echo "=========================================="
echo -e "Result: $([ $OVERALL = PASS ] && echo "${GREEN}PASS${NC}" || echo "${RED}FAIL${NC}")  ($N_PASS passed, $N_FAIL failed, $N_SKIP skipped, ${TOTAL_SECS}s)"
echo "  Summary: $SUMMARY_TSV"
echo "           $SUMMARY_JSON"
echo "  Logs:    $LOGS/"
echo "=========================================="

if [ "$CLEANUP" = true ] && [ $N_FAIL -eq 0 ]; then
    rm -rf "$MITGCM" "$FIX" "$WORKDIR/tmp"
    echo "Removed the MITgcm clone and fixtures (--cleanup)."
fi

[ $N_FAIL -eq 0 ]

#!/bin/bash
#
# Compare MITgcm output against reference results, the same way MITgcm's
# own testreport does.
#
# Usage: ./compare_results.sh <experiment> [output_dir] [--match N] [--ref <file>] [-adm | -tlm]
#
# Options:
#   output_dir    Output directory to compare (default: output_docker, or
#                 output_docker_adm / output_docker_tlm with -adm / -tlm)
#   --match N     Minimum matching digits required for PASS (default: 10,
#                 the same default as testreport)
#   --ref <file>  Reference file name inside <experiment>/results/
#                 (default: picked from the input directory used for the run)
#   -adm | -tlm   Compare a TAF adjoint / tangent-linear run. Normally not
#                 needed: the kind is read from the run's run_info.txt.
#
# Returns:
#   0 = PASS (the checked variable has sufficient digit agreement)
#   1 = FAIL (insufficient agreement, no comparison possible, or missing files)
#
# Algorithm (ported from testreport's testoutput_run/testoutput_var):
#   - The variable list comes from tr_checklist (linked into the output
#     directory from the input directory), or testreport's default
#     "PS PS T+ S+ U+ V+ pt1+ ... pt5+". The FIRST entry is the variable
#     that decides PASS/FAIL; the rest are reported for information.
#   - Each variable (e.g. dynstat_theta_mean) is compared as its own time
#     series. Digits of agreement for a series = -max over lines of
#     rint(log10(relative error)), capped at 16 for identical values
#     (22 when every value is exactly zero in both files).
#   - A series cannot be compared ("N/O", shown as 99 by testreport) if it
#     has fewer than 2 lines, a different number of lines than the
#     reference, or NaN/Inf values. N/O on the deciding variable is a FAIL.
#   - Adjoint runs are checked against results/output_adm[.<X>].txt with the
#     default list "admGrd admCst admGrd admFwd T+ S+ U+ V+" (gradient check
#     plus adjoint-field stats, e.g. dynstat_adtheta_*); tangent-linear runs
#     against results/output_tlm[.<X>].txt with "tlmGrd tlmCst tlmGrd tlmFwd".
#     As in testreport, TLM runs rename adm* entries of tr_checklist to tlm*,
#     and tr_checklist.adm / tr_checklist.tlm override tr_checklist.

set -e

if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>] [-adm | -tlm]"
    echo ""
    echo "Compare MITgcm output against reference results using the same"
    echo "per-variable algorithm as MITgcm's testreport."
    echo ""
    echo "Options:"
    echo "  output_dir    Output directory to compare (default: output_docker;"
    echo "                output_docker_adm / output_docker_tlm with -adm / -tlm)"
    echo "  --match N     Minimum matching digits required for PASS (default: 10)"
    echo "  --ref <file>  Reference file in <experiment>/results/ (default: output.txt,"
    echo "                or output.<X>.txt when the run used input directory input.<X>;"
    echo "                output_adm[.<X>].txt / output_tlm[.<X>].txt for TAF runs)"
    echo "  -adm | -tlm   Compare a TAF adjoint / tangent-linear run (normally detected"
    echo "                from the run's run_info.txt; the flag also picks the default"
    echo "                output directory)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column                    # Compare output_docker"
    echo "  $0 tutorial_barotropic_gyre output_mpi    # Compare another output dir"
    echo "  $0 lab_sea output_docker --match 12       # Require 12 digits"
    echo "  $0 1D_ocean_ice_column -adm               # Compare output_docker_adm"
    echo ""
    echo "Returns:"
    echo "  0 = PASS (sufficient digit agreement)"
    echo "  1 = FAIL (insufficient agreement or missing files)"
    echo ""
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>] [-adm | -tlm]"
    echo ""
    echo "Example:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 1D_ocean_ice_column output_docker --match 13"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

EXPERIMENT="${1}"
OUTPUT_DIR=""
MATCH_DIGITS=10
REF_NAME=""
KIND_FLAG=""

shift 1
while [[ $# -gt 0 ]]; do
    case $1 in
        --match)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --match requires a non-negative integer (got: '${2}')"
                exit 1
            fi
            MATCH_DIGITS="$2"
            shift 2
            ;;
        --ref)
            if [[ -z "$2" ]]; then
                echo "Error: --ref requires a file name"
                exit 1
            fi
            REF_NAME="$2"
            shift 2
            ;;
        -adm|-tlm)
            if [ -n "$KIND_FLAG" ] && [ "$KIND_FLAG" != "${1#-}" ]; then
                echo "Error: -adm and -tlm cannot be combined"
                exit 1
            fi
            KIND_FLAG="${1#-}"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>] [-adm | -tlm]"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
        *)
            OUTPUT_DIR="$1"
            shift
            ;;
    esac
done

# Locate the verification directory: the current directory if it holds the
# experiment, otherwise the MITgcm checkout this script is linked into.
if [ -d "./$EXPERIMENT" ]; then
    VERIFICATION_DIR="$(pwd)"
else
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    VERIFICATION_DIR=""
    SEARCH_DIR="$SCRIPT_DIR"
    for i in {1..6}; do
        if [ -f "$SEARCH_DIR/verification/.gitignore" ] || \
           { [ -d "$SEARCH_DIR/verification" ] && [ -d "$SEARCH_DIR/model" ]; }; then
            VERIFICATION_DIR="$SEARCH_DIR/verification"
            break
        fi
        SEARCH_DIR="$(dirname "$SEARCH_DIR")"
    done
    if [ -z "$VERIFICATION_DIR" ] || [ ! -d "$VERIFICATION_DIR/$EXPERIMENT" ]; then
        VERIFICATION_DIR="$(pwd)"
    fi
fi

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="output_docker"
    [ -n "$KIND_FLAG" ] && OUTPUT_DIR="output_docker_$KIND_FLAG"
fi

EXP_DIR="$VERIFICATION_DIR/$EXPERIMENT"
OUT_DIR="$EXP_DIR/$OUTPUT_DIR"

# What produced this output? (run_info.txt is written by
# experiment_run_no_compile.sh; runs recorded before TAF support are forward)
RUN_KIND=""
INPUT_DIR=""
if [ -f "$OUT_DIR/run_info.txt" ]; then
    INPUT_DIR="$(sed -n 's/^INPUT_DIR=//p' "$OUT_DIR/run_info.txt" | head -1)"
    RUN_KIND="$(sed -n 's/^KIND=//p' "$OUT_DIR/run_info.txt" | head -1)"
    RUN_KIND="${RUN_KIND:-forward}"
fi
if [ -n "$KIND_FLAG" ] && [ -n "$RUN_KIND" ] && [ "$KIND_FLAG" != "$RUN_KIND" ]; then
    echo "Error: -$KIND_FLAG given, but $OUTPUT_DIR holds a '$RUN_KIND' run (see run_info.txt)"
    exit 1
fi
KIND="${KIND_FLAG:-${RUN_KIND:-forward}}"

case "$KIND" in
    forward) BASE_INPUT=input;    REF_PREFIX=output ;;
    adm)     BASE_INPUT=input_ad; REF_PREFIX=output_adm ;;
    tlm)     BASE_INPUT=input_ad; REF_PREFIX=output_tlm ;;
esac
[ -z "$INPUT_DIR" ] && INPUT_DIR="$BASE_INPUT"

# Reference file: testreport pairs input.<X> with results/output.<X>.txt,
# and input_ad.<X> with results/output_adm.<X>.txt / output_tlm.<X>.txt
if [ -z "$REF_NAME" ]; then
    if [[ "$INPUT_DIR" == "$BASE_INPUT".* ]]; then
        REF_NAME="$REF_PREFIX.${INPUT_DIR#$BASE_INPUT.}.txt"
    else
        REF_NAME="$REF_PREFIX.txt"
    fi
fi
REFERENCE_FILE="$EXP_DIR/results/$REF_NAME"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/compare_results.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ ! -f "$REFERENCE_FILE" ] && [ -f "$REFERENCE_FILE.gz" ]; then
    gzip -cd "$REFERENCE_FILE.gz" > "$TMP_DIR/reference.txt"
    REFERENCE_FILE="$TMP_DIR/reference.txt"
fi

if [ ! -f "$REFERENCE_FILE" ]; then
    echo "=========================================="
    echo "ERROR: Reference output not found"
    echo "=========================================="
    echo ""
    echo "Expected: $EXP_DIR/results/$REF_NAME"
    echo ""
    echo "This experiment may not have reference results."
    exit 1
fi

# Model output: output.txt, or STDOUT.0000 for MPI runs whose output.txt
# holds only launcher messages.
OUTPUT_FILE="$OUT_DIR/output.txt"
if { [ ! -f "$OUTPUT_FILE" ] || ! grep -q "%MON" "$OUTPUT_FILE"; } && [ -f "$OUT_DIR/STDOUT.0000" ]; then
    OUTPUT_FILE="$OUT_DIR/STDOUT.0000"
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "=========================================="
    echo "ERROR: Output file not found"
    echo "=========================================="
    echo ""
    echo "Expected: $OUT_DIR/output.txt"
    echo ""
    echo "Run the model first:"
    if [ "$KIND" = forward ]; then
        echo "  ./experiment_run_no_compile.sh $EXPERIMENT"
    else
        echo "  ./experiment_run_no_compile.sh $EXPERIMENT -$KIND"
    fi
    exit 1
fi

# Variable checklist: tr_checklist from the run directory (linked from the
# input dir), falling back to the input dirs, then testreport's default.
find_checklist() {
    local f
    for f in "$OUT_DIR/$1" "$EXP_DIR/$INPUT_DIR/$1" "$EXP_DIR/$BASE_INPUT/$1"; do
        if [ -r "$f" ]; then echo "$f"; return; fi
    done
}
CHECKLIST_FILE="$(find_checklist tr_checklist)"
if [ -n "$CHECKLIST_FILE" ]; then
    LIST_CHK="$(cat "$CHECKLIST_FILE")"
else
    case "$KIND" in
        forward) LIST_CHK="PS PS T+ S+ U+ V+ pt1+ pt2+ pt3+ pt4+ pt5+" ;;
        adm)     LIST_CHK="admGrd admCst admGrd admFwd T+ S+ U+ V+" ;;
        tlm)     LIST_CHK="admGrd admCst admGrd admFwd" ;;
    esac
fi
# TAF runs (as testreport): TLM reuses the adjoint list with adm* -> tlm*;
# tr_checklist.adm / tr_checklist.tlm replace the list when present.
if [ "$KIND" = tlm ]; then
    LIST_CHK="$(echo $LIST_CHK | sed 's/^adm/tlm/; s/ adm/ tlm/g')"
fi
if [ "$KIND" != forward ]; then
    KIND_CHECKLIST="$(find_checklist "tr_checklist.$KIND")"
    if [ -n "$KIND_CHECKLIST" ]; then
        CHECKLIST_FILE="$KIND_CHECKLIST"
        LIST_CHK="$(cat "$CHECKLIST_FILE")"
    fi
fi

# First entry decides PASS/FAIL; expand "X+" into Xmn Xmx Xav Xsd
SELECTED_VAR="$(echo $LIST_CHK | awk '{print $1}')"
LIST_VAR=""
for tok in $(echo $LIST_CHK | awk '{for(i=2;i<=NF;i++) print $i}'); do
    if [[ "$tok" == *+ ]]; then
        b="${tok%+}"
        LIST_VAR="$LIST_VAR ${b}mn ${b}mx ${b}av ${b}sd"
    else
        LIST_VAR="$LIST_VAR $tok"
    fi
done

# Drop passive-tracer entries the reference has no output for (forward only,
# as in testreport)
for n in 1 2 3 4 5 6 7 8 9; do
    [ "$KIND" = forward ] || break
    if [[ " $LIST_VAR " == *" pt${n}"* ]] && ! grep -q "trcstat_ptracer0${n}" "$REFERENCE_FILE"; then
        LIST_VAR="$(echo "$LIST_VAR" | sed "s/ pt${n}..//g")"
    fi
done

# Make sure the deciding variable is checked exactly once
if [[ " $LIST_VAR " != *" $SELECTED_VAR "* ]]; then
    LIST_VAR=" $SELECTED_VAR$LIST_VAR"
fi

# Monitor-field prefix of adjoint / tangent-linear variables (testreport's kd):
# e.g. dynstat_adtheta_min, dynstat_g_theta_min
case "$KIND" in
    adm) kd="ad" ;;
    tlm) kd="g_" ;;
    *)   kd="" ;;
esac

# Map a testreport checklist code to the text searched for in the output
var_pattern() {
    case $1 in
        PS)     echo "cg2d_init_res" ;;
        admCst) echo "ADM  ref_cost_function" ;;
        admGrd) echo "ADM  adjoint_gradient" ;;
        admFwd) echo "ADM  finite-diff_grad" ;;
        tlmCst) echo "TLM  ref_cost_function" ;;
        tlmGrd) echo "TLM  tangent-lin_grad" ;;
        tlmFwd) echo "TLM  finite-diff_grad" ;;
        Tmn) echo "dynstat_${kd}theta_min" ;;  Tmx) echo "dynstat_${kd}theta_max" ;;
        Tav) echo "dynstat_${kd}theta_mean" ;; Tsd) echo "dynstat_${kd}theta_sd" ;;
        Smn) echo "dynstat_${kd}salt_min" ;;   Smx) echo "dynstat_${kd}salt_max" ;;
        Sav) echo "dynstat_${kd}salt_mean" ;;  Ssd) echo "dynstat_${kd}salt_sd" ;;
        Umn) echo "dynstat_${kd}uvel_min" ;;   Umx) echo "dynstat_${kd}uvel_max" ;;
        Uav) echo "dynstat_${kd}uvel_mean" ;;  Usd) echo "dynstat_${kd}uvel_sd" ;;
        Vmn) echo "dynstat_${kd}vvel_min" ;;   Vmx) echo "dynstat_${kd}vvel_max" ;;
        Vav) echo "dynstat_${kd}vvel_mean" ;;  Vsd) echo "dynstat_${kd}vvel_sd" ;;
        Etamn) echo "dynstat_${kd}eta_min" ;;  Etamx) echo "dynstat_${kd}eta_max" ;;
        Etaav) echo "dynstat_${kd}eta_mean" ;; Etasd) echo "dynstat_${kd}eta_sd" ;;
        Qntmn) echo "forcing_qnet_min" ;; Qntmx) echo "forcing_qnet_max" ;;
        Qntav) echo "forcing_qnet_mean" ;; Qntsd) echo "forcing_qnet_sd" ;;
        aSImn) echo "seaice_${kd}area_min" ;;  aSImx) echo "seaice_${kd}area_max" ;;
        aSIav) echo "seaice_${kd}area_mean" ;; aSIsd) echo "seaice_${kd}area_sd" ;;
        hSImn) echo "seaice_${kd}heff_min" ;;  hSImx) echo "seaice_${kd}heff_max" ;;
        hSIav) echo "seaice_${kd}heff_mean" ;; hSIsd) echo "seaice_${kd}heff_sd" ;;
        uSImn) echo "seaice_${kd}uice_min" ;;  uSImx) echo "seaice_${kd}uice_max" ;;
        uSIav) echo "seaice_${kd}uice_mean" ;; uSIsd) echo "seaice_${kd}uice_sd" ;;
        vSImn) echo "seaice_${kd}vice_min" ;;  vSImx) echo "seaice_${kd}vice_max" ;;
        vSIav) echo "seaice_${kd}vice_mean" ;; vSIsd) echo "seaice_${kd}vice_sd" ;;
        AthSiG) echo "thSI_Ice_Area_G" ;; AthSiS) echo "thSI_Ice_Area_S" ;;
        AthSiN) echo "thSI_Ice_Area_N" ;; HthSiG) echo "thSI_IceH_ave_G" ;;
        HthSiS) echo "thSI_IceH_ave_S" ;; HthSiN) echo "thSI_IceH_ave_N" ;;
        HthMxS) echo "thSI_IceH_max_S" ;; HthMxN) echo "thSI_IceH_max_N" ;;
        sbo_M) echo "sbo_mass" ;;         sboFW) echo "sbo_mass_fw" ;;
        sboAc) echo "sbo_zoamc" ;;        sboAp) echo "sbo_zoamp" ;;
        StrmIc) echo "STREAMICE_FP_ERR" ;;
        pt[1-9]mn) echo "trcstat_${kd}ptracer0${1:2:1}_min" ;;
        pt[1-9]mx) echo "trcstat_${kd}ptracer0${1:2:1}_max" ;;
        pt[1-9]av) echo "trcstat_${kd}ptracer0${1:2:1}_mean" ;;
        pt[1-9]sd) echo "trcstat_${kd}ptracer0${1:2:1}_sd" ;;
        *) echo "" ;;
    esac
}

# Digits of agreement for one variable; prints "<digits> <note>"
compare_var() {
    local pat="$1"
    grep -F -- "$pat" "$OUTPUT_FILE" | sed 's/.*=//' > "$TMP_DIR/a.txt" || true
    grep -F -- "$pat" "$REFERENCE_FILE" | sed 's/.*=//' > "$TMP_DIR/b.txt" || true
    local na nb
    na=$(wc -l < "$TMP_DIR/a.txt" | tr -d ' ')
    nb=$(wc -l < "$TMP_DIR/b.txt" | tr -d ' ')
    if [ "$na" -lt 2 ]; then echo "99 output has $na line(s)"; return; fi
    if [ "$nb" -lt 2 ]; then echo "99 reference has $nb line(s)"; return; fi
    if [ "$na" -ne "$nb" ]; then echo "99 line count differs: output $na, reference $nb"; return; fi
    if grep -qi "nan" "$TMP_DIR/a.txt"; then echo "99 output contains NaN"; return; fi
    if grep -qi "inf" "$TMP_DIR/a.txt"; then echo "99 output contains Inf"; return; fi
    paste -d' ' "$TMP_DIR/b.txt" "$TMP_DIR/a.txt" | awk '
        function rint(x) { return (x >= 0) ? int(x + 0.5) : -int(-x + 0.5) }
        BEGIN { best = -22 }
        {
            a = $1 + 0; b = $2 + 0
            abave = 0.5 * ((a < 0 ? -a : a) + (b < 0 ? -b : b))
            if (abave > 0) {
                d = a - b; if (d < 0) d = -d
                relerr = d / abave
                cmplin = (relerr > 0) ? rint(log(relerr) / log(10)) : -16
                if (cmplin > best) best = cmplin
            }
        }
        END { print -best, "" }'
}

echo "=========================================="
echo "Comparing Results"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
if [ "$KIND" = adm ]; then
echo "  Kind:       adjoint (TAF)"
elif [ "$KIND" = tlm ]; then
echo "  Kind:       tangent linear (TAF)"
fi
echo "  Reference:  results/$REF_NAME"
echo "  Output:     $OUTPUT_DIR/$(basename "$OUTPUT_FILE")"
if [ -n "$CHECKLIST_FILE" ]; then
echo "  Checklist:  $LIST_CHK  (from ${CHECKLIST_FILE#$EXP_DIR/})"
else
echo "  Checklist:  $LIST_CHK  (testreport default)"
fi
echo "  Match req:  $MATCH_DIGITS digits (on '$SELECTED_VAR')"
echo "=========================================="
echo ""
printf "  %-8s %-24s %s\n" "Var" "Monitor field" "Digits"
printf "  %-8s %-24s %s\n" "---" "-------------" "------"

SELECTED_DIGITS=99
SELECTED_NOTE="variable not recognized"
for code in $LIST_VAR; do
    pat="$(var_pattern "$code")"
    if [ -z "$pat" ]; then
        digits=99; note="not recognized"
    else
        read -r digits note <<< "$(compare_var "$pat")"
    fi
    shown="$digits"; [ "$digits" = "99" ] && shown="N/O"
    marker=" "; [ "$code" = "$SELECTED_VAR" ] && marker=">"
    printf "%s %-8s %-24s %s%s\n" " $marker" "$code" "${pat:--}" "$shown" "${note:+  ($note)}"
    if [ "$code" = "$SELECTED_VAR" ]; then
        SELECTED_DIGITS="$digits"; SELECTED_NOTE="$note"
    fi
done

echo ""
echo "=========================================="
echo "Results"
echo "=========================================="
echo ""
if [ "$SELECTED_DIGITS" = "99" ]; then
    echo "  Matching digits: N/O (no comparison possible: ${SELECTED_NOTE:-unknown})"
else
    echo "  Matching digits: $SELECTED_DIGITS"
fi
echo "  Required:        $MATCH_DIGITS"
echo ""

if [ "$SELECTED_DIGITS" != "99" ] && [ "$SELECTED_DIGITS" -ge "$MATCH_DIGITS" ]; then
    echo "  Status:          ✓ PASS"
    echo ""
    echo "=========================================="
    echo "Output matches reference results!"
    echo "=========================================="
    exit 0
else
    echo "  Status:          ✗ FAIL"
    echo ""
    echo "=========================================="
    echo "Output differs from reference"
    echo "=========================================="
    echo ""
    echo "This could indicate:"
    echo "  - The model run failed or stopped early (check the end of the output)"
    echo "  - Numerical differences from compiler/platform"
    echo "  - Different parameter settings"
    echo "  - Code modifications"
    echo ""
    exit 1
fi

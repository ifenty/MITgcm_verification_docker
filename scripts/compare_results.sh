#!/bin/bash
#
# Compare MITgcm output against reference results, the same way MITgcm's
# own testreport does.
#
# Usage: ./compare_results.sh <experiment> [output_dir] [--match N] [--ref <file>]
#
# Options:
#   output_dir    Output directory to compare (default: output_docker)
#   --match N     Minimum matching digits required for PASS (default: 10,
#                 the same default as testreport)
#   --ref <file>  Reference file name inside <experiment>/results/
#                 (default: picked from the input directory used for the run)
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

set -e

if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
    echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>]"
    echo ""
    echo "Compare MITgcm output against reference results using the same"
    echo "per-variable algorithm as MITgcm's testreport."
    echo ""
    echo "Options:"
    echo "  output_dir    Output directory to compare (default: output_docker)"
    echo "  --match N     Minimum matching digits required for PASS (default: 10)"
    echo "  --ref <file>  Reference file in <experiment>/results/ (default: output.txt,"
    echo "                or output.<X>.txt when the run used input directory input.<X>)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column                    # Compare output_docker"
    echo "  $0 tutorial_barotropic_gyre output_mpi    # Compare another output dir"
    echo "  $0 lab_sea output_docker --match 12       # Require 12 digits"
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
    echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>]"
    echo ""
    echo "Example:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 1D_ocean_ice_column output_docker --match 13"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

EXPERIMENT="${1}"
OUTPUT_DIR="output_docker"
MATCH_DIGITS=10
REF_NAME=""

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
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [output_dir] [--match N] [--ref <file>]"
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

EXP_DIR="$VERIFICATION_DIR/$EXPERIMENT"
OUT_DIR="$EXP_DIR/$OUTPUT_DIR"

# Which input directory produced this output? (written by experiment_run_no_compile.sh)
INPUT_DIR="input"
if [ -f "$OUT_DIR/run_info.txt" ]; then
    INPUT_DIR="$(sed -n 's/^INPUT_DIR=//p' "$OUT_DIR/run_info.txt" | head -1)"
    [ -z "$INPUT_DIR" ] && INPUT_DIR="input"
fi

# Reference file: testreport pairs input.<X> with results/output.<X>.txt
if [ -z "$REF_NAME" ]; then
    if [[ "$INPUT_DIR" == input.* ]]; then
        REF_NAME="output.${INPUT_DIR#input.}.txt"
    else
        REF_NAME="output.txt"
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
    echo "  ./experiment_run_no_compile.sh $EXPERIMENT"
    exit 1
fi

# Variable checklist: tr_checklist from the run directory (linked from the
# input dir), falling back to the input dirs, then testreport's default.
CHECKLIST_FILE=""
for f in "$OUT_DIR/tr_checklist" "$EXP_DIR/$INPUT_DIR/tr_checklist" "$EXP_DIR/input/tr_checklist"; do
    if [ -r "$f" ]; then CHECKLIST_FILE="$f"; break; fi
done
if [ -n "$CHECKLIST_FILE" ]; then
    LIST_CHK="$(cat "$CHECKLIST_FILE")"
else
    LIST_CHK="PS PS T+ S+ U+ V+ pt1+ pt2+ pt3+ pt4+ pt5+"
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

# Drop passive-tracer entries the reference has no output for
for n in 1 2 3 4 5 6 7 8 9; do
    if [[ " $LIST_VAR " == *" pt${n}"* ]] && ! grep -q "trcstat_ptracer0${n}" "$REFERENCE_FILE"; then
        LIST_VAR="$(echo "$LIST_VAR" | sed "s/ pt${n}..//g")"
    fi
done

# Make sure the deciding variable is checked exactly once
if [[ " $LIST_VAR " != *" $SELECTED_VAR "* ]]; then
    LIST_VAR=" $SELECTED_VAR$LIST_VAR"
fi

# Map a testreport checklist code to the text searched for in the output
var_pattern() {
    case $1 in
        PS)     echo "cg2d_init_res" ;;
        Tmn) echo "dynstat_theta_min" ;;  Tmx) echo "dynstat_theta_max" ;;
        Tav) echo "dynstat_theta_mean" ;; Tsd) echo "dynstat_theta_sd" ;;
        Smn) echo "dynstat_salt_min" ;;   Smx) echo "dynstat_salt_max" ;;
        Sav) echo "dynstat_salt_mean" ;;  Ssd) echo "dynstat_salt_sd" ;;
        Umn) echo "dynstat_uvel_min" ;;   Umx) echo "dynstat_uvel_max" ;;
        Uav) echo "dynstat_uvel_mean" ;;  Usd) echo "dynstat_uvel_sd" ;;
        Vmn) echo "dynstat_vvel_min" ;;   Vmx) echo "dynstat_vvel_max" ;;
        Vav) echo "dynstat_vvel_mean" ;;  Vsd) echo "dynstat_vvel_sd" ;;
        Etamn) echo "dynstat_eta_min" ;;  Etamx) echo "dynstat_eta_max" ;;
        Etaav) echo "dynstat_eta_mean" ;; Etasd) echo "dynstat_eta_sd" ;;
        Qntmn) echo "forcing_qnet_min" ;; Qntmx) echo "forcing_qnet_max" ;;
        Qntav) echo "forcing_qnet_mean" ;; Qntsd) echo "forcing_qnet_sd" ;;
        aSImn) echo "seaice_area_min" ;;  aSImx) echo "seaice_area_max" ;;
        aSIav) echo "seaice_area_mean" ;; aSIsd) echo "seaice_area_sd" ;;
        hSImn) echo "seaice_heff_min" ;;  hSImx) echo "seaice_heff_max" ;;
        hSIav) echo "seaice_heff_mean" ;; hSIsd) echo "seaice_heff_sd" ;;
        uSImn) echo "seaice_uice_min" ;;  uSImx) echo "seaice_uice_max" ;;
        uSIav) echo "seaice_uice_mean" ;; uSIsd) echo "seaice_uice_sd" ;;
        vSImn) echo "seaice_vice_min" ;;  vSImx) echo "seaice_vice_max" ;;
        vSIav) echo "seaice_vice_mean" ;; vSIsd) echo "seaice_vice_sd" ;;
        AthSiG) echo "thSI_Ice_Area_G" ;; AthSiS) echo "thSI_Ice_Area_S" ;;
        AthSiN) echo "thSI_Ice_Area_N" ;; HthSiG) echo "thSI_IceH_ave_G" ;;
        HthSiS) echo "thSI_IceH_ave_S" ;; HthSiN) echo "thSI_IceH_ave_N" ;;
        HthMxS) echo "thSI_IceH_max_S" ;; HthMxN) echo "thSI_IceH_max_N" ;;
        sbo_M) echo "sbo_mass" ;;         sboFW) echo "sbo_mass_fw" ;;
        sboAc) echo "sbo_zoamc" ;;        sboAp) echo "sbo_zoamp" ;;
        StrmIc) echo "STREAMICE_FP_ERR" ;;
        pt[1-9]mn) echo "trcstat_ptracer0${1:2:1}_min" ;;
        pt[1-9]mx) echo "trcstat_ptracer0${1:2:1}_max" ;;
        pt[1-9]av) echo "trcstat_ptracer0${1:2:1}_mean" ;;
        pt[1-9]sd) echo "trcstat_ptracer0${1:2:1}_sd" ;;
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

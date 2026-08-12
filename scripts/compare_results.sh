#!/bin/bash
#
# Compare MITgcm output against reference results
#
# Usage: ./compare_results.sh <experiment> [output_dir] [--match N]
#
# Options:
#   output_dir    Output directory to compare (default: output_docker)
#   --match N     Minimum matching digits required for PASS (default: 13)
#
# Returns:
#   0 = PASS (sufficient digit agreement)
#   1 = FAIL (insufficient agreement or missing files)

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check for help first
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 <experiment_name> [output_dir] [--match N]"
    echo ""
    echo "Compare MITgcm output against reference results"
    echo ""
    echo "Options:"
    echo "  output_dir    Output directory to compare (default: output_docker)"
    echo "  --match N     Minimum matching digits required for PASS (default: 13)"
    echo ""
    echo "Examples:"
    echo "  $0 1D_ocean_ice_column                    # Compare output_docker"
    echo "  $0 1D_ocean_ice_column output_docker_mpi # Compare MPI output"
    echo "  $0 lab_sea output_docker --match 12      # Require 12 digits"
    echo ""
    echo "Returns:"
    echo "  0 = PASS (sufficient digit agreement)"
    echo "  1 = FAIL (insufficient agreement or missing files)"
    echo ""
    exit 0
fi

if [ -z "$1" ] || [[ "$1" == -* ]]; then
    echo "Error: experiment name is required"
    echo ""
    echo "Usage: $0 <experiment_name> [output_dir] [--match N]"
    echo ""
    echo "Example:"
    echo "  $0 1D_ocean_ice_column"
    echo "  $0 1D_ocean_ice_column output_docker --match 13"
    echo ""
    echo "Try '$0 --help' for more information"
    exit 1
fi

EXPERIMENT="${1}"
OUTPUT_DIR="${2:-output_docker}"
MATCH_DIGITS=13

# Parse optional match argument
shift 2 2>/dev/null || shift $# 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --match)
            MATCH_DIGITS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <experiment_name> [output_dir] [--match N]"
            echo "Try '$0 --help' for more information"
            exit 1
            ;;
    esac
done

REFERENCE_FILE="./$EXPERIMENT/results/output.txt"
OUTPUT_FILE="./$EXPERIMENT/$OUTPUT_DIR/output.txt"

if [ ! -f "$REFERENCE_FILE" ]; then
    echo "=========================================="
    echo "ERROR: Reference output not found"
    echo "=========================================="
    echo ""
    echo "Expected: $REFERENCE_FILE"
    echo ""
    echo "This experiment may not have reference results."
    exit 1
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "=========================================="
    echo "ERROR: Output file not found"
    echo "=========================================="
    echo ""
    echo "Expected: $OUTPUT_FILE"
    echo ""
    echo "Run the model first:"
    echo "  ./run_no_compile.sh $EXPERIMENT"
    exit 1
fi

echo "=========================================="
echo "Comparing Results"
echo "=========================================="
echo "  Experiment: $EXPERIMENT"
echo "  Reference:  results/output.txt"
echo "  Output:     $OUTPUT_DIR/output.txt"
echo "  Match req:  $MATCH_DIGITS digits"
echo "=========================================="
echo ""

# Create comparison program (same as testreport uses)
CC="${CC:-gcc}"
cat > /tmp/tr_cmpnum_$$.c <<'EOF'
#include <stdio.h>
#include <math.h>
int main( int argc, char** argv )  {
  int linnum,cmplin,best,lncnt;
  double a,b,abave,relerr;
  best = -22;
  lncnt = 0;
  while( 1 & ( (lncnt+=1) < 999 ) )  {
    scanf("%d", &linnum);
    if (linnum == -1)  break;
    scanf("%lf", &a);  scanf("%lf", &b);
    abave = 0.5*(fabs(a)+fabs(b));
    if ( abave == abave ) {
      if (abave > 0.0) {
        relerr=fabs(a-b)/abave;
        if (relerr > 0.0) { cmplin = (int)rint(log10(relerr)); }
        else { cmplin = -16 ; }
        best = (best > cmplin) ? best : cmplin; }
      else { cmplin = -22 ; }
      }
   else {
      break; }
  }
  if (lncnt == 999) best=-29;
  if (linnum != -1) best=-99;
  printf("%d\n", -best);
  return 0;
}
EOF

$CC -o /tmp/tr_cmpnum_$$ /tmp/tr_cmpnum_$$.c -lm 2>&1 || {
    echo "ERROR: Failed to compile comparison program"
    rm -f /tmp/tr_cmpnum_$$*
    exit 1
}

# Extract monitor output lines (%MON lines) from both files
grep "%MON" "$REFERENCE_FILE" | sed 's/%MON//' > /tmp/reference_mon_$$.txt
grep "%MON" "$OUTPUT_FILE" | sed 's/%MON//' > /tmp/output_mon_$$.txt

# Compare the monitor statistics
echo "Comparing monitor output statistics..."
echo ""

# Create input for comparison program
awk 'BEGIN { line = 0 }
{
    if ($1 != "" && $2 != "") {
        ref_line[line] = $0
        ref_val[line] = $NF
        line++
    }
}
END {
    for (i = 0; i < line; i++) {
        getline < "/tmp/output_mon_'$$'.txt"
        out_val = $NF
        printf "%d %s %s\n", i, ref_val[i], out_val
    }
    printf "-1 0 0\n"
}' /tmp/reference_mon_$$.txt > /tmp/compare_input_$$.txt

# Run comparison
DIGITS=$(/tmp/tr_cmpnum_$$ < /tmp/compare_input_$$.txt)

# Cleanup
rm -f /tmp/tr_cmpnum_$$* /tmp/reference_mon_$$* /tmp/output_mon_$$* /tmp/compare_input_$$*

echo "=========================================="
echo "Results"
echo "=========================================="
echo ""
echo "  Matching digits: $DIGITS"
echo "  Required:        $MATCH_DIGITS"
echo ""

if [ "$DIGITS" -ge "$MATCH_DIGITS" ]; then
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
    echo "  - Numerical differences from compiler/platform"
    echo "  - Different parameter settings"
    echo "  - Code modifications"
    echo ""
    exit 1
fi

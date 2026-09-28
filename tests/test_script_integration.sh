#!/bin/bash
#
# Integration test for experiment_run_no_compile.sh and compare_results.sh
# Tests actual script execution with various argument combinations
#
# Deliberately no 'set -e': run_test/run_test_with_message return 1 on a
# failing test by design, and the script tallies pass/fail counts and picks
# its own exit code at the end. 'set -e' would abort the whole suite at the
# first failing test instead of running the rest and reporting a summary.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# experiment_run_no_compile.sh looks for a MITgcm checkout by walking up from
# its own location for a 'verification/.gitignore' marker (the same shape a
# symlinked-into-a-real-checkout install has). Fake that shape here so the
# script's real root-detection logic runs the same way it would for a user,
# rather than skipping it.
TEST_EXP_DIR="$PROJECT_ROOT/verification"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_count=0
pass_count=0
fail_count=0

# Setup test environment
setup_test_env() {
    echo "Setting up test environment..."

    rm -rf "$TEST_EXP_DIR"
    mkdir -p "$TEST_EXP_DIR"
    touch "$TEST_EXP_DIR/.gitignore"

    mkdir -p "$TEST_EXP_DIR/test_exp1/input"
    mkdir -p "$TEST_EXP_DIR/test_exp1/output_docker"
    mkdir -p "$TEST_EXP_DIR/test_exp1/results"
    mkdir -p "$TEST_EXP_DIR/test_exp2/input_custom"
    mkdir -p "$TEST_EXP_DIR/test_exp2/output_docker"
    mkdir -p "$TEST_EXP_DIR/test_exp3/input"

    # Create dummy input files
    echo "# Test input" > "$TEST_EXP_DIR/test_exp1/input/data"
    echo "# Test input custom" > "$TEST_EXP_DIR/test_exp2/input_custom/data"
    echo "# Test input" > "$TEST_EXP_DIR/test_exp3/input/data"

    # Create a dummy binary
    echo '#!/bin/bash' > "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"
    echo 'echo "%MON 1 2 3 4 5.123456789"' >> "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"
    chmod +x "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"

    # Create reference output for comparison tests (realistic monitor lines:
    # compare_results.sh compares named variables as time series, like testreport)
    write_monitor_output "$TEST_EXP_DIR/test_exp1/results/output.txt"
    write_monitor_output "$TEST_EXP_DIR/test_exp1/output_docker/output.txt"

    # Custom output dir for compare_results.sh
    mkdir -p "$TEST_EXP_DIR/test_exp1/output_custom"
    write_monitor_output "$TEST_EXP_DIR/test_exp1/output_custom/output.txt"
}

# Write a small MITgcm-style log with three monitor records
write_monitor_output() {
    local f="$1"
    : > "$f"
    for step in 1 2 3; do
        for var in cg2d_init_res dynstat_theta_min dynstat_theta_max dynstat_theta_mean dynstat_theta_sd; do
            printf '(PID.TID 0000.0001) %%MON %-28s =   %d.2345678901234E-0%d\n' "$var" "$step" "$step" >> "$f"
        done
    done
    echo "PROGRAM MAIN: Execution ended Normally" >> "$f"
}

# Cleanup
cleanup() {
    rm -rf "$TEST_EXP_DIR"
}

# Test runner
run_test() {
    local test_name="$1"
    local expected_result="$2"
    shift 2
    local cmd="$@"

    test_count=$((test_count + 1))
    echo ""
    echo "Test $test_count: $test_name"
    echo "  Command: $cmd"

    # Run command and capture result
    local result=0
    eval "$cmd" > /tmp/test_output_$$.txt 2>&1 || result=$?

    if [ "$expected_result" = "pass" ] && [ $result -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC}"
        pass_count=$((pass_count + 1))
        return 0
    elif [ "$expected_result" = "fail" ] && [ $result -ne 0 ]; then
        echo -e "  ${GREEN}PASS${NC} (expected failure)"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "  ${RED}FAIL${NC}"
        echo "  Expected: $expected_result, Got: exit code $result"
        echo "  Output:"
        cat /tmp/test_output_$$.txt | sed 's/^/    /'
        fail_count=$((fail_count + 1))
        return 1
    fi
}

# Test that expected error message appears
run_test_with_message() {
    local test_name="$1"
    local expected_message="$2"
    shift 2
    local cmd="$@"

    test_count=$((test_count + 1))
    echo ""
    echo "Test $test_count: $test_name"
    echo "  Command: $cmd"

    # Run command and capture output
    local result=0
    eval "$cmd" > /tmp/test_output_$$.txt 2>&1 || result=$?

    if grep -q "$expected_message" /tmp/test_output_$$.txt; then
        echo -e "  ${GREEN}PASS${NC} (found expected message)"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "  ${RED}FAIL${NC}"
        echo "  Expected message: $expected_message"
        echo "  Output:"
        cat /tmp/test_output_$$.txt | sed 's/^/    /'
        fail_count=$((fail_count + 1))
        return 1
    fi
}

echo "=========================================="
echo "Script Integration Tests"
echo "=========================================="

# Setup
setup_test_env
trap cleanup EXIT

# Test Group 1: experiment_run_no_compile.sh validation
echo ""
echo "=== Testing experiment_run_no_compile.sh ==="

run_test_with_message \
    "No arguments shows usage" \
    "Usage:" \
    "$SCRIPTS_DIR/experiment_run_no_compile.sh"

run_test_with_message \
    "Flag as first argument should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/experiment_run_no_compile.sh -mpi"

run_test_with_message \
    "Missing input directory should fail" \
    "Error: Input directory not found" \
    "$SCRIPTS_DIR/experiment_run_no_compile.sh test_exp1 nonexistent_input"

# Test Group 2: compare_results.sh validation
echo ""
echo "=== Testing compare_results.sh ==="

run_test_with_message \
    "No arguments shows usage" \
    "Usage:" \
    "$SCRIPTS_DIR/compare_results.sh"

run_test_with_message \
    "Flag as first argument should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/compare_results.sh --match 13"

run_test_with_message \
    "Missing reference file should fail" \
    "ERROR: Reference output not found" \
    "cd $TEST_EXP_DIR && $SCRIPTS_DIR/compare_results.sh test_exp2"

run_test_with_message \
    "Missing output file should fail" \
    "ERROR: Output file not found" \
    "cd $TEST_EXP_DIR && $SCRIPTS_DIR/compare_results.sh test_exp1 nonexistent_output"

run_test \
    "Valid comparison should pass" \
    "pass" \
    "cd $TEST_EXP_DIR && $SCRIPTS_DIR/compare_results.sh test_exp1"

# Test Group 3: Argument parsing edge cases
echo ""
echo "=== Testing Argument Parsing ==="

run_test_with_message \
    "Custom input directory with hyphen in name" \
    "Error: Input directory not found" \
    "$SCRIPTS_DIR/experiment_run_no_compile.sh test_exp2 my-input"
# test_exp2 only has input_custom/, not my-input/ -- this should parse the
# hyphenated name correctly as input_dir and fail on the missing directory,
# not on argument parsing.

run_test_with_message \
    "Flag detection: -mpi with count, no input_dir" \
    "Error: Binary not found" \
    "$SCRIPTS_DIR/experiment_run_no_compile.sh test_exp3 -mpi 2"
# test_exp3 has an input/ dir but no compiled binary -- this should use the
# default 'input' directory and fail on the missing binary, not on parsing.

run_test \
    "Custom output directory" \
    "pass" \
    "cd $TEST_EXP_DIR && $SCRIPTS_DIR/compare_results.sh test_exp1 output_custom"

run_test \
    "Flag detection: --match without output_dir" \
    "pass" \
    "cd $TEST_EXP_DIR && $SCRIPTS_DIR/compare_results.sh test_exp1 --match 10"

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "  Total:  $test_count"
echo -e "  ${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "  ${RED}Failed: $fail_count${NC}"
else
    echo "  Failed: 0"
fi
echo "=========================================="

# Cleanup is handled by trap

if [ $fail_count -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

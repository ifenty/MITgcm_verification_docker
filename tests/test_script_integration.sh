#!/bin/bash
#
# Integration test for run_no_compile.sh and compare_results.sh
# Tests actual script execution with various argument combinations
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
TEST_DIR="$PROJECT_ROOT/_temp/test_integration"

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

    # Scripts look for experiments as siblings to scripts dir
    # So we create test experiments in the project root
    TEST_EXP_DIR="$SCRIPTS_DIR"

    # Cleanup any existing test experiments
    rm -rf "$TEST_EXP_DIR/test_exp1" "$TEST_EXP_DIR/test_exp2" "$TEST_EXP_DIR/test_exp3"

    mkdir -p "$TEST_EXP_DIR/test_exp1/input"
    mkdir -p "$TEST_EXP_DIR/test_exp1/output_docker"
    mkdir -p "$TEST_EXP_DIR/test_exp1/results"
    mkdir -p "$TEST_EXP_DIR/test_exp2/input_custom"
    mkdir -p "$TEST_EXP_DIR/test_exp2/output_docker"

    # Create dummy input files
    echo "# Test input" > "$TEST_EXP_DIR/test_exp1/input/data"
    echo "# Test input custom" > "$TEST_EXP_DIR/test_exp2/input_custom/data"

    # Create a dummy binary
    echo '#!/bin/bash' > "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"
    echo 'echo "%MON 1 2 3 4 5.123456789"' >> "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"
    chmod +x "$TEST_EXP_DIR/test_exp1/output_docker/mitgcmuv"

    # Create reference output for comparison tests
    echo "%MON 1 2 3 4 5.123456789" > "$TEST_EXP_DIR/test_exp1/results/output.txt"
    echo "%MON 1 2 3 4 5.123456789" > "$TEST_EXP_DIR/test_exp1/output_docker/output.txt"
}

# Cleanup
cleanup() {
    # Clean up test experiments from scripts dir
    rm -rf "$SCRIPTS_DIR/test_exp1" "$SCRIPTS_DIR/test_exp2" "$SCRIPTS_DIR/test_exp3"
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

# Test Group 1: run_no_compile.sh validation
echo ""
echo "=== Testing run_no_compile.sh ==="

run_test_with_message \
    "Missing experiment name should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/run_no_compile.sh"

run_test_with_message \
    "Flag as first argument should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/run_no_compile.sh -mpi"

run_test_with_message \
    "Missing input directory should fail" \
    "Error: Input directory not found" \
    "$SCRIPTS_DIR/run_no_compile.sh test_exp1 nonexistent_input"

# Test Group 2: compare_results.sh validation
echo ""
echo "=== Testing compare_results.sh ==="

run_test_with_message \
    "Missing experiment name should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/compare_results.sh"

run_test_with_message \
    "Flag as first argument should fail" \
    "Error: experiment name is required" \
    "$SCRIPTS_DIR/compare_results.sh --match 13"

run_test_with_message \
    "Missing reference file should fail" \
    "ERROR: Reference output not found" \
    "cd $SCRIPTS_DIR && ./compare_results.sh test_exp2"

run_test_with_message \
    "Missing output file should fail" \
    "ERROR: Output file not found" \
    "cd $SCRIPTS_DIR && ./compare_results.sh test_exp1 nonexistent_output"

run_test \
    "Valid comparison should pass" \
    "pass" \
    "cd $SCRIPTS_DIR && ./compare_results.sh test_exp1"

# Test Group 3: Argument parsing edge cases
echo ""
echo "=== Testing Argument Parsing ==="

# Create test with custom input dir
mkdir -p "$TEST_DIR/test_exp2/my-input"
echo "# Test" > "$TEST_DIR/test_exp2/my-input/data"

run_test_with_message \
    "Custom input directory with hyphen in name" \
    "Error: Input directory not found" \
    "$SCRIPTS_DIR/run_no_compile.sh test_exp2 my-input"

# This should fail because my-input doesn't have a binary yet
# But it should parse correctly and fail on binary check, not on parsing

# Test with flag detection
# Create test experiment with input dir
mkdir -p "$SCRIPTS_DIR/test_exp3/input"
echo "# Test" > "$SCRIPTS_DIR/test_exp3/input/data"

run_test_with_message \
    "Flag detection: -mpi with count, no input_dir" \
    "ERROR: Binary not found" \
    "$SCRIPTS_DIR/run_no_compile.sh test_exp3 -mpi 2"

# This should use default 'input' directory and fail on missing binary
# If it failed on input directory, the parsing is wrong

# Test compare_results.sh with custom output dir
mkdir -p "$SCRIPTS_DIR/test_exp1/output_custom"
echo "%MON 1 2 3 4 5.123456789" > "$SCRIPTS_DIR/test_exp1/output_custom/output.txt"

run_test \
    "Custom output directory" \
    "pass" \
    "cd $SCRIPTS_DIR && ./compare_results.sh test_exp1 output_custom"

# Test with --match flag (should use default output_docker)
run_test \
    "Flag detection: --match without output_dir" \
    "pass" \
    "cd $SCRIPTS_DIR && ./compare_results.sh test_exp1 --match 10"

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

#!/bin/bash
set -euo pipefail

# Test script for generate.sh

SCRIPT_UNDER_TEST="./generate.sh"
TEST_COUNT=0
FAIL_COUNT=0

# --- Test Helpers ---

# Function to run a test case
# Usage: run_test "Test description" expected_exit_code command [args...]
run_test() {
    local description="$1"
    local expected_exit_code="$2"
    shift 2
    local cmd=("$@")

    ((TEST_COUNT++))
    echo -n "Test $((TEST_COUNT)): $description ... "

    # Execute the command, capturing output and exit code
    # Redirect stderr to a temp file to capture it separately
    local stderr_file
    stderr_file=$(mktemp)
    local stdout
    local actual_exit_code=0
    stdout=$("${cmd[@]}" 2> "$stderr_file") || actual_exit_code=$?
    local stderr_output
    stderr_output=$(<"$stderr_file")
    rm "$stderr_file"


    # Check exit code
    if [[ "$actual_exit_code" -ne "$expected_exit_code" ]]; then
        echo "FAILED (Expected exit code $expected_exit_code, got $actual_exit_code)"
        echo "  Command: ${cmd[*]}"
        echo "  Stdout:"
        echo "$stdout" | sed 's/^/    /'
        echo "  Stderr:"
        echo "$stderr_output" | sed 's/^/    /'
        ((FAIL_COUNT++))
        return 1 # Indicate failure for the purpose of the function
    fi

    # Store outputs for potential further checks
    # Using global variables is simple for this script structure
    LAST_STDOUT="$stdout"
    LAST_STDERR="$stderr_output"

    echo "PASSED"
    return 0 # Indicate success
}

# --- Assertion Helpers ---

assert_output_matches() {
    local pattern="$1"
    local description="${2:-Output matches regex}"
    if [[ ! "$LAST_STDOUT" =~ $pattern ]]; then
        echo "FAILED Assertion: $description ('$pattern')"
        echo "  Actual Output:"
        echo "$LAST_STDOUT" | sed 's/^/    /'
        ((FAIL_COUNT++))
        # Find the test number that failed this assertion (slightly hacky way)
        local current_test_line=$(grep -n "Test ${TEST_COUNT}:" "$0" | cut -d: -f1)
        local previous_failed_line=$(grep -n "FAILED (" "$0" | grep ":${current_test_line}," | tail -n 1)
        # If the main run_test didn't fail, mark the test as failed here
        if [[ -z "$previous_failed_line" ]]; then
             sed -i '' "${current_test_line}s/PASSED/FAILED (Assertion failed)/" "$0" # macOS sed
             # sed -i "${current_test_line}s/PASSED/FAILED (Assertion failed)/" "$0" # Linux sed
        fi
        return 1
    fi
    # echo "  Assertion PASSED: $description"
    return 0
}


assert_stderr_contains() {
    local substring="$1"
    local description="${2:-Stderr contains string}"
     if [[ "$LAST_STDERR" != *"$substring"* ]]; then
        echo "FAILED Assertion: $description ('$substring')"
        echo "  Actual Stderr:"
        echo "$LAST_STDERR" | sed 's/^/    /'
        ((FAIL_COUNT++))
        # Mark test as failed if not already marked
        local current_test_line=$(grep -n "Test ${TEST_COUNT}:" "$0" | cut -d: -f1)
        local previous_failed_line=$(grep -n "FAILED (" "$0" | grep "^${current_test_line}:" | tail -n 1)
        if [[ -z "$previous_failed_line" ]]; then
             sed -i '' "${current_test_line}s/PASSED/FAILED (Assertion failed)/" "$0" # macOS sed
             # sed -i "${current_test_line}s/PASSED/FAILED (Assertion failed)/" "$0" # Linux sed
        fi
        return 1
    fi
    # echo "  Assertion PASSED: $description"
    return 0
}


# --- Setup ---
echo "Running tests for $SCRIPT_UNDER_TEST..."

# Make sure the script exists and is executable
if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
    echo "Error: Script '$SCRIPT_UNDER_TEST' not found or not executable."
    exit 1
fi

# Check for word list (needed for passphrase tests)
word_list="/usr/share/dict/words" # Match the script's default
if [[ ! -r "$word_list" ]]; then
    echo "Warning: Default word list '$word_list' not found or not readable. Passphrase tests might fail."
    # Consider creating a dummy file for basic tests? For now, just warn.
fi


# --- Test Cases ---

# Help and Usage
run_test "Help flag (-h)" 0 "$SCRIPT_UNDER_TEST" -h && assert_output_matches "Usage:.*generate.sh.*{pass\|password\|tkn\|token\|api\|api_token\|secret}"
run_test "Help flag (--help)" 0 "$SCRIPT_UNDER_TEST" --help && assert_output_matches "Usage:.*generate.sh.*{pass\|password\|tkn\|token\|api\|api_token\|secret}"
run_test "No arguments shows help" 1 "$SCRIPT_UNDER_TEST" && assert_output_matches "Usage:.*generate.sh.*{pass\|password\|tkn\|token\|api\|api_token\|secret}" # Should exit 1 and show help
run_test "Invalid command" 1 "$SCRIPT_UNDER_TEST" invalid_command && assert_stderr_contains "Invalid command: invalid_command"
run_test "Unknown option" 1 "$SCRIPT_UNDER_TEST" pass --unknown-option && assert_stderr_contains "Unknown option: --unknown-option"

# Passphrase Generation (pass)
run_test "Default passphrase (pass)" 0 "$SCRIPT_UNDER_TEST" pass && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){3}-[0-9]{2}$" "Passphrase format: word-word-word-word-NN"
run_test "Default passphrase (password)" 0 "$SCRIPT_UNDER_TEST" password && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){3}-[0-9]{2}$" "Passphrase format: word-word-word-word-NN"
run_test "Passphrase custom length (-L 6)" 0 "$SCRIPT_UNDER_TEST" pass -L 6 && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){5}-[0-9]{2}$" "Passphrase format: 6 words"
run_test "Passphrase custom length (--length 3)" 0 "$SCRIPT_UNDER_TEST" pass --length 3 && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){2}-[0-9]{2}$" "Passphrase format: 3 words"
run_test "Passphrase uppercase (-u)" 0 "$SCRIPT_UNDER_TEST" pass -u && assert_output_matches "^[[:upper:]][[:lower:]]*(-[[:upper:]][[:lower:]]*){3}-[0-9]{2}$" "Passphrase format: Word-Word-Word-Word-NN"
run_test "Passphrase lowercase (-l)" 0 "$SCRIPT_UNDER_TEST" pass -l && assert_output_matches "^[[:lower:]]+(-[[:lower:]]+){3}-[0-9]{2}$" "Passphrase format: word-word-word-word-NN (all lower)"
run_test "Passphrase verbose (-v)" 0 "$SCRIPT_UNDER_TEST" pass -v && assert_stderr_contains "[DEBUG] Generating passphrase"
run_test "Passphrase uppercase and lowercase error" 1 "$SCRIPT_UNDER_TEST" pass -u -l && assert_stderr_contains "Error: Cannot use --uppercase and --lowercase flags together"
run_test "Passphrase invalid length (non-numeric)" 1 "$SCRIPT_UNDER_TEST" pass -L abc && assert_stderr_contains "Error: --length requires a numeric value"
run_test "Passphrase invalid length (negative - although caught by regex)" 1 "$SCRIPT_UNDER_TEST" pass -L -5 && assert_stderr_contains "Error: --length requires a numeric value" # Script uses simple regex ^[0-9]+$

# Secret Generation (secret)
# Note: Checking exact Base64 length is tricky due to padding. We check it's non-empty and looks like Base64.
DEFAULT_SECRET_B64_LEN=$(echo $(( (4 * 32 / 3) ))) # Approx length for 32 bytes
CUSTOM_SECRET_B64_LEN=$(echo $(( (4 * 16 / 3) ))) # Approx length for 16 bytes
run_test "Default secret" 0 "$SCRIPT_UNDER_TEST" secret && assert_output_matches "^[A-Za-z0-9+/=]+$" "Secret format: Base64"
run_test "Secret custom length (-L 16)" 0 "$SCRIPT_UNDER_TEST" secret -L 16 && assert_output_matches "^[A-Za-z0-9+/=]+$" "Secret format: Base64 (16 bytes)"
run_test "Secret verbose (-v)" 0 "$SCRIPT_UNDER_TEST" secret -v && assert_stderr_contains "[DEBUG] Generating JWT secret"
run_test "Secret invalid length (non-numeric)" 1 "$SCRIPT_UNDER_TEST" secret -L abc && assert_stderr_contains "Error: --length requires a numeric value"


# API Token Generation (api)
# Note: Checks prefix and URL-safe Base64 characters. Length check is approximate.
DEFAULT_API_B64_LEN=$(echo $(( (4 * 32 / 3) ))) # Approx length for 32 bytes
CUSTOM_API_B64_LEN=$(echo $(( (4 * 16 / 3) ))) # Approx length for 16 bytes
run_test "Default API token (api)" 0 "$SCRIPT_UNDER_TEST" api && assert_output_matches "^sk-[A-Za-z0-9_-]+$" "API token format: sk- followed by Base64URL"
run_test "Default API token (api_token)" 0 "$SCRIPT_UNDER_TEST" api_token && assert_output_matches "^sk-[A-Za-z0-9_-]+$" "API token format: sk- followed by Base64URL"
run_test "API token custom length (-L 16)" 0 "$SCRIPT_UNDER_TEST" api -L 16 && assert_output_matches "^sk-[A-Za-z0-9_-]+$" "API token format: sk- (16 bytes)"
run_test "API token verbose (-v)" 0 "$SCRIPT_UNDER_TEST" api -v && assert_stderr_contains "[DEBUG] Generating API token"
run_test "API token invalid length (non-numeric)" 1 "$SCRIPT_UNDER_TEST" api -L xyz && assert_stderr_contains "Error: --length requires a numeric value"


# Length flag interaction: Ensure -L applies to the correct command
run_test "Length flag applies to pass, not default api" 0 "$SCRIPT_UNDER_TEST" pass -L 5 && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){4}-[0-9]{2}$" "Passphrase format: 5 words"
# Now run api without -L, should use default bytes (32)
# We can't *easily* verify byte length from output, but this checks the code path
run_test "API uses default length after pass used -L" 0 "$SCRIPT_UNDER_TEST" api && assert_output_matches "^sk-[A-Za-z0-9_-]+$"

run_test "Length flag applies to api, not default pass" 0 "$SCRIPT_UNDER_TEST" api -L 16 && assert_output_matches "^sk-[A-Za-z0-9_-]+$"
# Now run pass without -L, should use default words (4)
run_test "Passphrase uses default length after api used -L" 0 "$SCRIPT_UNDER_TEST" pass && assert_output_matches "^[[:alpha:]]+(-[[:alpha:]]+){3}-[0-9]{2}$" "Passphrase format: 4 words"


# --- Test Summary ---
echo "--------------------"
echo "Tests Run: $TEST_COUNT"
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "Result: ALL PASSED"
  exit 0
else
  echo "Result: $FAIL_COUNT FAILED"
  exit 1
fi

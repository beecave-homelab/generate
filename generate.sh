#!/bin/bash
set -euo pipefail

# Script Description: Generates passphrases, JWT tokens, or API keys with selectable formatting.
# Author: elvee
# Version: 0.2.1
# License: MIT
# Creation Date: 09-04-2025
# Last Modified: 12-04-2025
# Usage: ./gen [pass|tkn|api] [OPTIONS]

# Constants
DEFAULT_PASSPHRASE_WORDS=4
DEFAULT_API_TOKEN_BYTES=32
DEFAULT_JWT_SECRET_BYTES=32 # Suitable for HS256
DEFAULT_WORD_LIST="/usr/share/dict/words" # Common path, might need adjustment on some systems
WORD_LIST="${WORD_LIST:-$DEFAULT_WORD_LIST}" # Use environment var if set and non-empty, otherwise use default

# --- Flags ---
VERBOSE=false
INCLUDE_UPPERCASE=false
INCLUDE_LOWERCASE=false
PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
JWT_SECRET_BYTE_LENGTH=$DEFAULT_JWT_SECRET_BYTES
# --- End Flags ---


# ASCII Art
print_ascii_art() {
  cat << EOF >&2
    ▗▄▄▖▗▄▄▄▖▗▖  ▗▖▗▄▄▄▖▗▄▄▖  ▗▄▖▗▄▄▄▖▗▄▄▄▖
   ▐▌   ▐▌   ▐▛▚▖▐▌▐▌   ▐▌ ▐▌▐▌ ▐▌ █  ▐▌   
   ▐▌▝▜▌▐▛▀▀▘▐▌ ▝▜▌▐▛▀▀▘▐▛▀▚▖▐▛▀▜▌ █  ▐▛▀▀▘
   ▝▚▄▞▘▐▙▄▄▖▐▌  ▐▌▐▙▄▄▖▐▌ ▐▌▐▌ ▐▌ █  ▐▙▄▄▖
   
EOF
}

# Verbose Output Function
log_debug() {
  if [[ "$VERBOSE" == true ]]; then
    echo "[DEBUG] $1" >&2
  fi
}

# Clipboard Copy Function
copy_to_clipboard() {
    local input="$1"
    log_debug "--- Entered copy_to_clipboard ---"
    local clipboard_cmd=""

    # Detect clipboard command
    if command -v pbcopy &> /dev/null; then
        clipboard_cmd="pbcopy" # macOS
    elif command -v xclip &> /dev/null; then
        clipboard_cmd="xclip -selection clipboard" # Linux (requires xclip)
    elif command -v xsel &> /dev/null; then
        clipboard_cmd="xsel --clipboard --input" # Linux (requires xsel)
    fi

    if [[ -n "$clipboard_cmd" ]]; then
        log_debug "Detected clipboard command: '$clipboard_cmd'"
        # Attempt to copy, capturing stderr via a temporary file
        local error_output=""
        local exit_status=0
        local error_file
        error_file=$(mktemp) # Create a temporary file

        log_debug "Checking for timeout command..."
        local timeout_cmd=""
        if command -v timeout &> /dev/null; then
            log_debug "timeout command found."
            timeout_cmd="timeout 1s " # Add a space at the end
        else
            log_debug "timeout command not found. Proceeding without timeout."
        fi

        log_debug "Attempting clipboard command (stderr to $error_file)..."
        # Wrap command in timeout if available, use sh -c for pipeline, redirect stdout to null, stderr to temp file
        # Temporarily disable exit on error (-e) for the timeout command
        set +e
        # Use ${timeout_cmd:-} which expands to nothing if timeout_cmd is empty
        ${timeout_cmd:-}sh -c "printf '%s' \"$input\" | $clipboard_cmd > /dev/null" 2> "$error_file"
        exit_status=$? # Capture exit status immediately
        set -e # Re-enable exit on error

        log_debug "Clipboard command finished. Exit status: $exit_status"

        # Read any error output from the temp file
        if [[ -s "$error_file" ]]; then # Check if error file is not empty
           error_output=$(<"$error_file")
           log_debug "Captured error output: $error_output"
        fi

        rm -f "$error_file" # Clean up the temporary file

        # Logic to handle exit status and error
        if [[ $exit_status -eq 0 ]]; then
            # Success
            if [[ "$VERBOSE" == true ]]; then
              log_debug "Result copied to clipboard using '$clipboard_cmd'."
            fi
        else
            # Failure or Timeout
            echo "Warning: Failed to copy to clipboard. Please copy the output manually." >&2
            if [[ "$VERBOSE" == true ]]; then
              if [[ $exit_status -eq 124 ]]; then
                 log_debug "Clipboard command '$clipboard_cmd' timed out (likely hung)."
              else
                 log_debug "Clipboard command '$clipboard_cmd' failed with exit status $exit_status. Error: $error_output"
              fi
            fi
        fi
    else
      log_debug "No clipboard command detected."
      # Only log missing command if verbose mode is on (This check is slightly redundant now but kept for clarity)
       if [[ "$VERBOSE" == true ]]; then
         log_debug "No clipboard command (pbcopy, xclip, xsel) found. Cannot copy to clipboard."
       fi
    fi
}


# Help Function
show_help() {
  cat << EOF
Usage: $0 {pass|password|secret|api|api_token} [OPTIONS]

Generates passphrases, JWT secrets, or API keys.

Commands:
  pass, password        Generate a human-readable passphrase.
  secret                Generate a secure, Base64-encoded secret (e.g., for JWT signing).
  api, api_token        Generate an API token starting with 'sk-'.

Options:
  -u, --uppercase       Capitalize first letter of each word (pass only).
  -l, --lowercase       Force words to lowercase (pass only).
  -L, --length <num>    For 'pass' : number of words (default: $DEFAULT_PASSPHRASE_WORDS).
                        For 'api'  : number of random bytes (default: $DEFAULT_API_TOKEN_BYTES).
                        For 'secret': number of random bytes (default: $DEFAULT_JWT_SECRET_BYTES).
  -v, --verbose         Enable verbose debug output.
  -h, --help            Display this help message.

Clipboard: Attempts to copy the generated value to the clipboard using pbcopy (macOS) or xclip/xsel (Linux).
EOF
}

# Select random word from dictionary (uses shuf if available, falls back to awk)
get_random_word() {
  local word=""
  if command -v shuf &> /dev/null; then
    # Try shuf, capture potential errors
    log_debug "get_random_word: Found shuf, attempting: shuf -n 1 '$WORD_LIST'"
    word=$(shuf -n 1 "$WORD_LIST" 2>/dev/null)
    log_debug "get_random_word: shuf command finished. Result: '$word'"
    if [[ -z "$word" ]]; then
        log_debug "shuf returned empty, potentially an issue with dictionary or shuf itself."
        # Optionally fall back to awk here if shuf consistently fails
    fi
  fi

  # If shuf wasn't found or failed, use awk
  if [[ -z "$word" ]] && ! command -v shuf &> /dev/null; then
     log_debug "shuf not found or failed, using awk fallback (slower)."
     # Ensure awk doesn't hang on empty input/errors
     word=$(awk 'BEGIN {srand();} { lines[NR]=$0 } END { if (NR > 0) print lines[int(rand()*NR)+1]; else print "" }' "$WORD_LIST" 2>/dev/null)
     if [[ -z "$word" ]]; then
         log_debug "awk fallback also returned empty."
     fi
  elif [[ -z "$word" ]]; then
      log_debug "shuf returned empty, not attempting awk fallback as shuf exists."
      # Policy: Return empty string if shuf exists but failed.
      echo "" # Return empty string
      return
  fi
  echo "$word" # Return the potentially multi-word line
}

# Generate random words for passphrase
generate_passphrase() {
  if [[ ! -r "$WORD_LIST" ]]; then
    echo "Error: Word list not found or not readable at $WORD_LIST" >&2
    exit 1
  fi

  if [[ "$INCLUDE_UPPERCASE" == true && "$INCLUDE_LOWERCASE" == true ]]; then
      echo "Error: Cannot use --uppercase and --lowercase flags together." >&2
      exit 1
  fi

  log_debug "Generating passphrase with $PASSPHRASE_WORD_COUNT unique words using batch method."

  # Determine how many words to grab initially (oversample to increase unique chance)
  local words_to_grab=$(( PASSPHRASE_WORD_COUNT * 3 ))
  if (( words_to_grab < 20 )); then # Ensure we grab a reasonable minimum
      words_to_grab=20
  fi
  log_debug "Attempting to grab $words_to_grab raw words initially."

  local raw_words_list
  if command -v shuf &> /dev/null; then
      log_debug "Using shuf to get raw words."
      # Handle potential errors from shuf
      raw_words_list=$(shuf -n "$words_to_grab" "$WORD_LIST" 2>/dev/null)
      if [[ $? -ne 0 || -z "$raw_words_list" ]]; then
          log_debug "shuf failed or returned empty. Attempting awk fallback."
          # Fall through to awk if shuf fails
          raw_words_list=""
      fi
  fi

  # Awk fallback (if shuf not found or failed)
  if [[ -z "$raw_words_list" ]]; then
      log_debug "Using awk fallback to get raw words (slower)."
      # Awk method to get N random lines (less efficient than shuf)
      # This is a common reservoir sampling algorithm for awk
      raw_words_list=$(awk -v n="$words_to_grab" 'BEGIN{srand()} {if(NR<=n) {a[NR]=$0} else {r=int(rand()*NR)+1; if(r<=n) {a[r]=$0}}} END{for(i=1;i<=n;i++) print a[i]}' "$WORD_LIST" 2>/dev/null)
       if [[ $? -ne 0 || -z "$raw_words_list" ]]; then
           echo "Error: Failed to get words using shuf and awk fallback from '$WORD_LIST'." >&2
           exit 1
       fi
  fi

  log_debug "Processing and filtering raw words..."
  local processed_words
  # Process lines: get first word, apply case mods, ensure uniqueness
  processed_words=$(echo "$raw_words_list" | awk \
    -v upper="$INCLUDE_UPPERCASE" -v lower="$INCLUDE_LOWERCASE" '
    {
      # Extract the first word from the line
      word = $1
      if (word == "") next # Skip empty lines/words

      # Filter out words with non-alphabetic characters (e.g., apostrophes)
      if (!match(word, /^[[:alpha:]]+$/)) next

      # Apply case modification (variables passed via -v)
      if (upper == "true") {
        word = toupper(substr(word,1,1)) tolower(substr(word,2))
      } else if (lower == "true") {
        word = tolower(word)
      }

      # Ensure uniqueness (case-sensitive after modification)
      if (!seen[word]++) {
        print word
      }
    }'
  )

  # Take the required number of unique words
  local unique_words
  unique_words=$(echo "$processed_words" | head -n "$PASSPHRASE_WORD_COUNT")

  # Check if we got enough unique words
  local unique_count
  unique_count=$(echo "$unique_words" | wc -w) # Count words

  if (( unique_count < PASSPHRASE_WORD_COUNT )); then
      echo "Error: Could not generate enough unique words ($unique_count found) for the requested count ($PASSPHRASE_WORD_COUNT)." >&2
      echo "       Try reducing the count or checking the dictionary '$WORD_LIST'." >&2
      exit 1
  fi

  log_debug "Successfully obtained $unique_count unique words."

  # Format the result
  local result
  if [[ -z "$unique_words" ]]; then
      echo "Error: Failed to obtain valid unique words after filtering." >&2
      log_debug "Debug: unique_words variable was empty before paste operation."
      exit 1
  fi
  # result=$(echo "$unique_words" | paste -sd '-') # Join words with hyphen
  # Use awk for more robust joining across platforms
  result=$(echo "$unique_words" | awk 'NR > 1 { printf "-" }; { printf "%s", $0 } END { print "" }')

  local number
  number=$(printf "%02d" $((RANDOM % 100)))
  result+="-$number"

  # Call copy BEFORE printing the result
  copy_to_clipboard "$result"
  printf "%s\n" "$result"
}

# Generate API token with sk- prefix and custom byte length
generate_api_token() {
  log_debug "Generating API token with length $API_TOKEN_BYTE_LENGTH containing only [A-Za-z0-9]."
  local random_chars
  # Generate enough Base64 random bytes to likely cover the desired length after filtering, then filter and truncate.
  # We estimate needing roughly N bytes input for N alphanumeric characters output after filtering Base64. Add a buffer.
  random_chars=$(openssl rand -base64 "$(( API_TOKEN_BYTE_LENGTH * 3 / 4 + 5 ))" | tr -dc 'A-Za-z0-9' | head -c "$API_TOKEN_BYTE_LENGTH")

  # Check if we generated enough characters (unlikely to fail with the buffer, but good practice)
  if [[ ${#random_chars} -lt $API_TOKEN_BYTE_LENGTH ]]; then
      echo "Error: Could not generate enough random alphanumeric characters." >&2
      log_debug "Needed $API_TOKEN_BYTE_LENGTH, got ${#random_chars}"
      exit 1
  fi

  local token="sk-${random_chars}"
  # Call copy BEFORE printing the result
  copy_to_clipboard "$token"
  printf "%s\n" "$token"
}

# Generate a secure secret suitable for JWT signing (Base64 encoded)
generate_jwt_secret() {
  log_debug "Generating JWT secret with $JWT_SECRET_BYTE_LENGTH random bytes."
  local secret
  # Generate specified number of bytes and Base64 encode them
  secret=$(openssl rand -base64 "$JWT_SECRET_BYTE_LENGTH")

  # Call copy BEFORE printing the result
  copy_to_clipboard "$secret"
  printf "%s\n" "$secret"
}

# --- Argument Parsing ---

# Check for help flag *before* assuming the first arg is a command
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    show_help
    exit 0
  fi
done

# Now, proceed if no help flag was found
if [[ $# -lt 1 ]]; then
  show_help
  exit 1
fi

COMMAND=$1
shift # Remove command from argument list

# Reset flags/options for parsing
INCLUDE_UPPERCASE=false
INCLUDE_LOWERCASE=false
PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
JWT_SECRET_BYTE_LENGTH=$DEFAULT_JWT_SECRET_BYTES
LENGTH_FLAG_SET_PASS=false
LENGTH_FLAG_SET_API=false
LENGTH_FLAG_SET_SECRET=false


while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--uppercase)
      INCLUDE_UPPERCASE=true
      log_debug "Uppercase flag set."
      shift
      ;;
    -l|--lowercase)
      INCLUDE_LOWERCASE=true
      log_debug "Lowercase flag set."
      shift
      ;;
    -L|--length)
      if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
           echo "Error: --length requires a numeric value." >&2
           exit 1
      fi
      # We don't know the command yet, so set flags to check later
      PASSPHRASE_WORD_COUNT="$2"
      API_TOKEN_BYTE_LENGTH="$2"
      JWT_SECRET_BYTE_LENGTH="$2"
      LENGTH_FLAG_SET_PASS=true
      LENGTH_FLAG_SET_API=true
      LENGTH_FLAG_SET_SECRET=true
      log_debug "Length flag set to $2."
      shift 2 # Consume flag and value
      ;;
    -v|--verbose)
       VERBOSE=true
       shift
       ;;
    -h|--help)
      # This case is technically redundant now but harmless to keep
      # as the loop above handles it. We could remove it for cleanup.
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

# --- Command Execution ---
print_ascii_art

log_debug "Verbose mode enabled."

log_debug "Command: $COMMAND"

# Assign correct length based on command if not set by flag
if [[ "$COMMAND" == "pass" || "$COMMAND" == "password" ]]; then
  if [[ "$LENGTH_FLAG_SET_PASS" = false ]]; then
    PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS # Use default if -L wasn't used
    log_debug "Using default passphrase length: $PASSPHRASE_WORD_COUNT words."
  else
     log_debug "Using specified passphrase length: $PASSPHRASE_WORD_COUNT words."
  fi
  # Reset other lengths if pass command is used and length was potentially set
   if [[ "$LENGTH_FLAG_SET_PASS" = true ]]; then
       API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
       JWT_SECRET_BYTE_LENGTH=$DEFAULT_JWT_SECRET_BYTES
   fi

elif [[ "$COMMAND" == "secret" ]]; then
  if [[ "$LENGTH_FLAG_SET_SECRET" = false ]]; then
      JWT_SECRET_BYTE_LENGTH=$DEFAULT_JWT_SECRET_BYTES # Use default if -L wasn't used
      log_debug "Using default JWT secret length: $JWT_SECRET_BYTE_LENGTH bytes."
  else
      log_debug "Using specified JWT secret length: $JWT_SECRET_BYTE_LENGTH bytes."
  fi
   # Reset other lengths if secret command is used and length was potentially set
   if [[ "$LENGTH_FLAG_SET_SECRET" = true ]]; then
       PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
       API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
   fi

elif [[ "$COMMAND" == "api" || "$COMMAND" == "api_token" ]]; then
  if [[ "$LENGTH_FLAG_SET_API" = false ]]; then
    API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES # Use default if -L wasn't used
    log_debug "Using default API token length: $API_TOKEN_BYTE_LENGTH bytes."
  else
    log_debug "Using specified API token length: $API_TOKEN_BYTE_LENGTH bytes."
  fi
   # Reset other lengths if api command is used and length was potentially set
   if [[ "$LENGTH_FLAG_SET_API" = true ]]; then
       PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
       JWT_SECRET_BYTE_LENGTH=$DEFAULT_JWT_SECRET_BYTES
   fi
fi


# Execute the chosen command function
case "$COMMAND" in
  pass|password)
    generate_passphrase
    ;;
  secret)
    generate_jwt_secret
    ;;
  api|api_token)
    generate_api_token
    ;;
  *)
    echo "Invalid command: $COMMAND" >&2
    show_help
    exit 1
    ;;
esac

exit 0


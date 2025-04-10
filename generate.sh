#!/bin/bash
set -euo pipefail

# Script Description: Generates passphrases, JWT tokens, or API keys with selectable formatting.
# Author: elvee
# Version: 0.2.0
# License: MIT
# Creation Date: 09-04-2025
# Last Modified: 09-04-2025
# Usage: ./gen [pass|tkn|api] [OPTIONS]

# Constants
DEFAULT_PASSPHRASE_WORDS=4
DEFAULT_API_TOKEN_BYTES=32
WORD_LIST="/usr/share/dict/words" # Common path, might need adjustment on some systems

# --- Flags ---
VERBOSE=false
INCLUDE_UPPERCASE=false
INCLUDE_LOWERCASE=false
PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
# --- End Flags ---


# ASCII Art
print_ascii_art() {
  cat << EOF
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
        printf "%s" "$input" | $clipboard_cmd
        log_debug "Result copied to clipboard using $clipboard_cmd."
    else
        log_debug "No clipboard command (pbcopy, xclip, xsel) found. Cannot copy to clipboard."
    fi
}


# Help Function
show_help() {
  cat << EOF
Usage: $0 {pass|password|tkn|token|api|api_token} [OPTIONS]

Generates passphrases, JWT-like tokens, or API keys.

Commands:
  pass, password        Generate a human-readable passphrase.
  tkn, token            Generate a JWT-like token string (fixed format).
  api, api_token        Generate an API token starting with 'sk-'.

Options:
  -u, --uppercase       Capitalize first letter of each word (pass only).
  -l, --lowercase       Force words to lowercase (pass only).
  -L, --length <num>    For 'pass': number of words (default: $DEFAULT_PASSPHRASE_WORDS).
                        For 'api' : number of random bytes (default: $DEFAULT_API_TOKEN_BYTES).
                        For 'tkn' : ignored.
  -v, --verbose         Enable verbose debug output.
  -h, --help            Display this help message.

Clipboard: Attempts to copy the generated value to the clipboard using pbcopy (macOS) or xclip/xsel (Linux).

Tip: Create a symlink like 'ln -s \$(pwd)/generate.sh /usr/local/bin/gen' to use this globally.
EOF
}

# Select random word from dictionary (uses shuf if available, falls back to awk)
get_random_word() {
  if command -v shuf &> /dev/null; then
    shuf -n 1 "$WORD_LIST"
  else
    log_debug "shuf not found, using awk fallback (slower)."
    awk 'BEGIN {srand();} { lines[NR]=$0 } END { print lines[int(rand()*NR)+1] }' "$WORD_LIST"
  fi
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

  local words=()
  log_debug "Generating passphrase with $PASSPHRASE_WORD_COUNT words."
  for ((i = 0; i < PASSPHRASE_WORD_COUNT; i++)); do
    word=$(get_random_word)
    # Handle potential empty lines or multi-word lines from dict
    word=$(echo "$word" | awk '{print $1}')
    if [[ -z "$word" ]]; then
        ((i--)) # Retry if we got an empty word
        continue
    fi

    if [[ $INCLUDE_UPPERCASE == true ]]; then
      word=$(echo "$word" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') # Portable capitalization
    elif [[ $INCLUDE_LOWERCASE == true ]]; then
      word=$(echo "$word" | tr '[:upper:]' '[:lower:]') # Portable lowercase
    fi
    words+=("$word")
    log_debug "Added word: $word"
  done

  local number
  number=$(printf "%02d" $((RANDOM % 100))) # Keep 2-digit number suffix
  local result
  result=$(printf "%s-" "${words[@]}")$number
  printf "%s\n" "$result"
  copy_to_clipboard "$result"
}

# Generate JWT-like token using openssl
generate_token() {
  log_debug "Generating JWT-like token."
  local part1 part2 part3 raw_result temp_result final_result result

  # Generate URL-safe base64 strings directly
  part1=$(openssl rand -base64 12 | tr '+/' '-_')
  part2=$(openssl rand -base64 32 | tr '+/' '-_')
  part3=$(openssl rand -base64 16 | tr '+/' '-_')

  # Concatenate the parts first
  raw_result="${part1}.${part2}.${part3}"

  # Remove potential trailing padding character(s) from the combined string
  # Use two steps with % to remove up to two trailing '=' signs
  temp_result=${raw_result%=}   # Remove one trailing '=' if it exists
  final_result=${temp_result%=} # Remove another trailing '=' if it exists

  # Append exactly one '=' sign
  result="${final_result}="

  printf "%s\n" "$result"
  copy_to_clipboard "$result"
}

# Generate API token with sk- prefix and custom byte length
generate_api_token() {
  log_debug "Generating API token with $API_TOKEN_BYTE_LENGTH random bytes."
  local random_bytes
  # Generate URL-safe base64 string from specified bytes
  random_bytes=$(openssl rand -base64 "$API_TOKEN_BYTE_LENGTH" | tr -d '=' | tr '+/' '-_')

  local token="sk-${random_bytes}"
  printf "%s\n" "$token"
  copy_to_clipboard "$token"
}

# --- Argument Parsing ---
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
LENGTH_FLAG_SET_PASS=false
LENGTH_FLAG_SET_API=false


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
      LENGTH_FLAG_SET_PASS=true
      LENGTH_FLAG_SET_API=true
      log_debug "Length flag set to $2."
      shift 2 # Consume flag and value
      ;;
    -v|--verbose)
       VERBOSE=true
       shift
       ;;
    -h|--help)
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
  # Reset API length if pass command is used and length was potentially set
   if [[ "$LENGTH_FLAG_SET_API" = true && "$LENGTH_FLAG_SET_PASS" = true ]]; then
       API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES
   fi

elif [[ "$COMMAND" == "api" || "$COMMAND" == "api_token" ]]; then
  if [[ "$LENGTH_FLAG_SET_API" = false ]]; then
    API_TOKEN_BYTE_LENGTH=$DEFAULT_API_TOKEN_BYTES # Use default if -L wasn't used
    log_debug "Using default API token length: $API_TOKEN_BYTE_LENGTH bytes."
  else
    log_debug "Using specified API token length: $API_TOKEN_BYTE_LENGTH bytes."
  fi
   # Reset Pass length if api command is used and length was potentially set
   if [[ "$LENGTH_FLAG_SET_API" = true && "$LENGTH_FLAG_SET_PASS" = true ]]; then
       PASSPHRASE_WORD_COUNT=$DEFAULT_PASSPHRASE_WORDS
   fi
elif [[ "$COMMAND" == "tkn" || "$COMMAND" == "token" ]]; then
   if [[ "$LENGTH_FLAG_SET_PASS" = true || "$LENGTH_FLAG_SET_API" = true ]]; then
       log_debug "Ignoring --length flag for token command."
   fi
fi


# Execute the chosen command function
case "$COMMAND" in
  pass|password)
    generate_passphrase
    ;;
  tkn|token)
    generate_token
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

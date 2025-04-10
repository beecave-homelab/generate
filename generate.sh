#!/bin/bash
set -euo pipefail

# Script Description: Generates passphrases, JWT tokens, or API keys with selectable formatting.
# Author: elvee
# Version: 0.2.0
# License: MIT
# Creation Date: 09-04-2025
# Last Modified: 10-04-2025
# Usage: ./gen [pass|tkn|api] [OPTIONS]

# Constants
DEFAULT_PASSPHRASE_WORDS=4
DEFAULT_API_TOKEN_BYTES=32
DEFAULT_JWT_SECRET_BYTES=32 # Suitable for HS256
WORD_LIST="/usr/share/dict/words" # Common path, might need adjustment on some systems

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

  log_debug "Generating passphrase with $PASSPHRASE_WORD_COUNT unique words."
  
  # Check if word list has enough unique potential words (considering case modification)
  # This check is complex to do perfectly portably without knowing the final case.
  # We'll rely on the retry mechanism, but add a safeguard.
  local unique_word_count
  unique_word_count=$(awk '{print $1}' "$WORD_LIST" | sort -u | wc -l) # Raw unique words
  if (( unique_word_count < PASSPHRASE_WORD_COUNT )); then
      echo "Warning: Dictionary might not contain enough unique words ($unique_word_count) for the requested count ($PASSPHRASE_WORD_COUNT), especially with case flags. Generation might be slow or fail." >&2
      # Don't exit, let it try, but warn the user.
  fi

  local attempts=0
  local max_attempts=$(( PASSPHRASE_WORD_COUNT * 100 )) # Safeguard against infinite loops

  words=() # Initialize the array
  local word_count=0 # Initialize word counter
  local chosen_words_marker=$'\n' # Use newline delimiters for unique matching

  # Loop using the counter instead of array size check
  while [[ $word_count -lt $PASSPHRASE_WORD_COUNT ]]; do
    ((attempts++))
    if (( attempts > max_attempts )); then
        echo "Error: Exceeded maximum attempts ($max_attempts) to find unique words. Check dictionary or requested length." >&2
        exit 1
    fi

    local word
    word=$(get_random_word)
    # Handle potential empty lines or multi-word lines from dict
    word=$(echo "$word" | awk '{print $1}')
    if [[ -z "$word" ]]; then
        log_debug "Got empty word, retrying..."
        continue # Retry if we got an empty word
    fi

    # Apply case modification *first*
    local modified_word="$word"
    if [[ $INCLUDE_UPPERCASE == true ]]; then
      modified_word=$(echo "$word" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') # Portable capitalization
    elif [[ $INCLUDE_LOWERCASE == true ]]; then
      modified_word=$(echo "$word" | tr '[:upper:]' '[:lower:]') # Portable lowercase
    fi

    # Check if the *modified* word already exists using string matching
    if [[ "$chosen_words_marker" == *$'
'"$modified_word"$'
'* ]]; then
        log_debug "Modified word '$modified_word' (from raw '$word') already selected, retrying..."
        continue # Retry if the modified form exists
    fi

    # If unique, add the modified word to the list and the marker string
    words+=("$modified_word")
    chosen_words_marker+="$modified_word"$'
'
    ((word_count++)) # Increment the counter
    log_debug "Added unique modified word to list: $modified_word (Count: $word_count)"
  done

  local number
  number=$(printf "%02d" $((RANDOM % 100))) # Keep 2-digit number suffix
  local result="" # Initialize result string

  # Build the result string by iterating with the counter to avoid "${words[@]}"
  local i
  for (( i=0; i < word_count; i++ )); do
      result+="${words[$i]}-"
  done

  # Append the final number (handles case where word_count is 0)
  result+="$number"

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

# Generate a secure secret suitable for JWT signing (Base64 encoded)
generate_jwt_secret() {
  log_debug "Generating JWT secret with $JWT_SECRET_BYTE_LENGTH random bytes."
  local secret
  # Generate specified number of bytes and Base64 encode them
  secret=$(openssl rand -base64 "$JWT_SECRET_BYTE_LENGTH")

  printf "%s\n" "$secret"
  copy_to_clipboard "$secret"
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

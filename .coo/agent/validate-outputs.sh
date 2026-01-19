#!/bin/bash
#
# COO Agent Validation Functions
#
# Provides validation functions for all COO agent output types:
# - Email CSVs
# - Leads CSVs
# - Twitter posts
# - Instagram prospect lists
#
# Usage:
#   source "$SCRIPT_DIR/validate-outputs.sh"
#   validate_all "$STAGING_DIR/2025-01-15"
#
# Returns 0 if all validations pass, 1 if any fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source config if not already loaded
if [ -z "$COO_DIR" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# =============================================================================
# VALIDATION STATE
# =============================================================================

VALIDATION_ERRORS=()
VALIDATION_WARNINGS=()

clear_validation_state() {
  VALIDATION_ERRORS=()
  VALIDATION_WARNINGS=()
}

add_error() {
  VALIDATION_ERRORS+=("$1")
  log_error "$1"
}

add_warning() {
  VALIDATION_WARNINGS+=("$1")
  log_warning "$1"
}

get_error_count() {
  echo "${#VALIDATION_ERRORS[@]}"
}

get_warning_count() {
  echo "${#VALIDATION_WARNINGS[@]}"
}

# =============================================================================
# EMAIL CSV VALIDATION
# =============================================================================

validate_email_csv() {
  local file="$1"
  local errors=0

  if [ ! -f "$file" ]; then
    log_qa "No email CSV to validate"
    return 0
  fi

  log_qa "Validating email CSV: $file"

  # Check file is not empty
  local line_count=$(wc -l < "$file" | tr -d ' ')
  if [ "$line_count" -lt 2 ]; then
    add_error "Email CSV is empty or has only header"
    return 1
  fi

  # Check required headers
  local header=$(head -1 "$file")
  for field in $(echo "$EMAIL_CSV_REQUIRED_FIELDS" | tr ',' ' '); do
    if ! echo "$header" | grep -qi "$field"; then
      add_error "Email CSV missing required field: $field"
      errors=$((errors + 1))
    fi
  done

  # Use Claude to validate CSV (handles quoted fields with commas correctly)
  local validation_result=$(claude --print --dangerously-skip-permissions "
Read the CSV file at '$file' and validate each row.

For each row, extract the 'email' column (handle any column name case) and validate:
1. Email matches regex: $EMAIL_REGEX

Output format - one line per issue found:
ERROR:Row N:Invalid email format:value

If no errors, output:
VALID

At the end, always output:
EMAIL_COUNT:N
where N is the number of data rows (excluding header).
")

  # Parse Claude's validation output
  while IFS= read -r line; do
    if [[ "$line" == ERROR:* ]]; then
      add_error "${line#ERROR:}"
      errors=$((errors + 1))
    fi
  done <<< "$validation_result"

  # Extract email count
  local email_count=$(echo "$validation_result" | grep -oP 'EMAIL_COUNT:\K\d+' || echo "0")

  # Check warm-up limits
  local email_limit=$(get_email_limit)

  if [ "$email_count" -gt "$email_limit" ]; then
    add_error "Email count ($email_count) exceeds warm-up limit ($email_limit for day $(get_warmup_day))"
    errors=$((errors + 1))
  else
    log_qa "Email count ($email_count) within warm-up limit ($email_limit)"
  fi

  # Check for A/B variant column
  if ! echo "$header" | grep -qi "variant"; then
    add_warning "Email CSV has no A/B variant column - all emails will use same template"
  fi

  if [ $errors -gt 0 ]; then
    add_error "Email CSV validation failed with $errors error(s)"
    return 1
  fi

  log_success "Email CSV validation passed ($email_count emails)"
  return 0
}

# =============================================================================
# LEADS CSV VALIDATION
# =============================================================================

validate_leads_csv() {
  local file="$1"
  local errors=0

  if [ ! -f "$file" ]; then
    log_qa "No leads CSV to validate"
    return 0
  fi

  log_qa "Validating leads CSV: $file"

  # Check file is not empty
  local line_count=$(wc -l < "$file" | tr -d ' ')
  if [ "$line_count" -lt 2 ]; then
    add_error "Leads CSV is empty or has only header"
    return 1
  fi

  # Check required headers
  local header=$(head -1 "$file")
  for field in $(echo "$LEADS_CSV_REQUIRED_FIELDS" | tr ',' ' '); do
    if ! echo "$header" | grep -qi "$field"; then
      add_error "Leads CSV missing required field: $field"
      errors=$((errors + 1))
    fi
  done

  # Use Claude to validate CSV (handles quoted fields with commas correctly)
  local validation_result=$(claude --print --dangerously-skip-permissions "
Read the CSV file at '$file' and validate each row.

For each row:
1. If 'phone' column exists, validate it matches E.164 format: $PHONE_REGEX
2. Check for duplicate values in the phone column (or first column if no phone)

Output format - one line per issue:
ERROR:Row N:Invalid phone format (expected E.164):value
WARNING:Duplicate entries found:value1,value2,...

If no errors, output:
VALID

At the end, always output:
LEAD_COUNT:N
where N is the number of data rows (excluding header).
")

  # Parse Claude's validation output
  while IFS= read -r line; do
    if [[ "$line" == ERROR:* ]]; then
      add_error "${line#ERROR:}"
      errors=$((errors + 1))
    elif [[ "$line" == WARNING:* ]]; then
      add_warning "${line#WARNING:}"
    fi
  done <<< "$validation_result"

  # Extract lead count
  local lead_count=$(echo "$validation_result" | grep -oP 'LEAD_COUNT:\K\d+' || echo "0")

  if [ $errors -gt 0 ]; then
    add_error "Leads CSV validation failed with $errors error(s)"
    return 1
  fi

  log_success "Leads CSV validation passed ($lead_count leads)"
  return 0
}

# =============================================================================
# TWITTER POST VALIDATION
# =============================================================================

validate_twitter_post() {
  local file="$1"
  local errors=0

  if [ ! -f "$file" ]; then
    log_qa "No Twitter posts to validate"
    return 0
  fi

  log_qa "Validating Twitter posts: $file"

  # Check if JSON file
  if [[ "$file" == *.json ]]; then
    # Validate JSON structure
    if ! jq -e '.' "$file" > /dev/null 2>&1; then
      add_error "Twitter posts file is not valid JSON"
      return 1
    fi

    # Validate each post
    local post_count=$(jq 'if type == "array" then length else 1 end' "$file")
    local i=0

    while [ $i -lt "$post_count" ]; do
      local post
      if [ "$post_count" -eq 1 ] && ! jq -e '.[0]' "$file" > /dev/null 2>&1; then
        post=$(jq -r '.content // .text // .tweet // .' "$file")
      else
        post=$(jq -r ".[$i].content // .[$i].text // .[$i].tweet // .[$i]" "$file")
      fi

      # Check character limit
      local char_count=${#post}
      if [ "$char_count" -gt "$TWITTER_MAX_CHARS" ]; then
        add_error "Post $((i+1)): Exceeds $TWITTER_MAX_CHARS chars (has $char_count)"
        errors=$((errors + 1))
      fi

      # Check for at least one hashtag
      local hashtag_count=$(echo "$post" | grep -o '#[a-zA-Z0-9_]*' | wc -l | tr -d ' ')
      if [ "$hashtag_count" -lt "$TWITTER_MIN_HASHTAGS" ]; then
        add_warning "Post $((i+1)): Has no hashtags (recommended: at least $TWITTER_MIN_HASHTAGS)"
      fi

      # Check for sensitive content patterns (basic filter)
      if echo "$post" | grep -qiE "(kill|hate|racist|sexist|nsfw)"; then
        add_error "Post $((i+1)): May contain inappropriate content - manual review required"
        errors=$((errors + 1))
      fi

      # Check for empty post
      if [ -z "$post" ] || [ "$post" = "null" ]; then
        add_error "Post $((i+1)): Empty or null content"
        errors=$((errors + 1))
      fi

      i=$((i + 1))
    done
  else
    # Plain text file - one post per line
    while IFS= read -r post; do
      [ -z "$post" ] && continue

      local char_count=${#post}
      if [ "$char_count" -gt "$TWITTER_MAX_CHARS" ]; then
        add_error "Post exceeds $TWITTER_MAX_CHARS chars (has $char_count)"
        errors=$((errors + 1))
      fi

      local hashtag_count=$(echo "$post" | grep -o '#[a-zA-Z0-9_]*' | wc -l | tr -d ' ')
      if [ "$hashtag_count" -lt "$TWITTER_MIN_HASHTAGS" ]; then
        add_warning "Post has no hashtags"
      fi
    done < "$file"
  fi

  if [ $errors -gt 0 ]; then
    add_error "Twitter validation failed with $errors error(s)"
    return 1
  fi

  log_success "Twitter posts validation passed"
  return 0
}

# =============================================================================
# INSTAGRAM PROSPECT LIST VALIDATION
# =============================================================================

validate_instagram_list() {
  local file="$1"
  local errors=0

  if [ ! -f "$file" ]; then
    log_qa "No Instagram list to validate"
    return 0
  fi

  log_qa "Validating Instagram list: $file"

  # Check file format (CSV or JSON)
  if [[ "$file" == *.json ]]; then
    if ! jq -e '.' "$file" > /dev/null 2>&1; then
      add_error "Instagram list is not valid JSON"
      return 1
    fi

    # Validate each entry has handle and context
    local entry_count=$(jq 'length' "$file")
    local i=0

    while [ $i -lt "$entry_count" ]; do
      local handle=$(jq -r ".[$i].handle // .[$i].username // .[$i].instagram" "$file" | tr -d '@')
      local company=$(jq -r ".[$i].company // .[$i].context // empty" "$file")

      # Validate handle format
      if [ -z "$handle" ] || [ "$handle" = "null" ]; then
        add_error "Entry $((i+1)): Missing Instagram handle"
        errors=$((errors + 1))
      elif ! echo "$handle" | grep -qE "$INSTAGRAM_REGEX"; then
        add_error "Entry $((i+1)): Invalid Instagram handle format: $handle"
        errors=$((errors + 1))
      fi

      # Check for company/context
      if [ -z "$company" ] || [ "$company" = "null" ]; then
        add_warning "Entry $((i+1)): No company context for DM personalization"
      fi

      i=$((i + 1))
    done
  else
    # CSV format - use Claude to parse (handles quoted fields with commas correctly)
    local validation_result=$(claude --print --dangerously-skip-permissions "
Read the CSV file at '$file' and validate Instagram handles.

For each row:
1. Find the handle/username/instagram column (case insensitive)
2. Strip @ symbol and whitespace from handles
3. Validate handle matches regex: $INSTAGRAM_REGEX
4. Check for company/context column for personalization

Output format - one line per issue:
ERROR:Row N:Invalid Instagram handle:value
ERROR:Missing handle/username column
WARNING:Entry N:No company context for DM personalization

If no errors, output:
VALID

At the end, always output:
ENTRY_COUNT:N
where N is the number of data rows (excluding header).
")

    # Parse Claude's validation output
    while IFS= read -r line; do
      if [[ "$line" == ERROR:* ]]; then
        add_error "${line#ERROR:}"
        errors=$((errors + 1))
      elif [[ "$line" == WARNING:* ]]; then
        add_warning "${line#WARNING:}"
      fi
    done <<< "$validation_result"
  fi

  if [ $errors -gt 0 ]; then
    add_error "Instagram list validation failed with $errors error(s)"
    return 1
  fi

  local entry_count=$(wc -l < "$file" | tr -d ' ')
  log_success "Instagram list validation passed ($((entry_count - 1)) prospects)"
  return 0
}

# =============================================================================
# MAIN VALIDATION FUNCTION
# =============================================================================

validate_all() {
  local staging_dir="$1"
  local validation_failed=0

  clear_validation_state

  log_qa "=========================================="
  log_qa "Starting QA validation for: $staging_dir"
  log_qa "=========================================="

  if [ ! -d "$staging_dir" ]; then
    add_error "Staging directory does not exist: $staging_dir"
    return 1
  fi

  # Find and validate each output type
  local found_files=0

  # Email CSVs
  for file in "$staging_dir"/*email*.csv "$staging_dir"/emails.csv "$staging_dir"/outreach.csv; do
    if [ -f "$file" ]; then
      found_files=$((found_files + 1))
      if ! validate_email_csv "$file"; then
        validation_failed=1
      fi
    fi
  done

  # Leads CSVs
  for file in "$staging_dir"/*leads*.csv "$staging_dir"/*dialer*.csv "$staging_dir"/prospects.csv; do
    if [ -f "$file" ]; then
      found_files=$((found_files + 1))
      if ! validate_leads_csv "$file"; then
        validation_failed=1
      fi
    fi
  done

  # Twitter posts
  for file in "$staging_dir"/*twitter*.json "$staging_dir"/tweets.json "$staging_dir"/tweet.txt; do
    if [ -f "$file" ]; then
      found_files=$((found_files + 1))
      if ! validate_twitter_post "$file"; then
        validation_failed=1
      fi
    fi
  done

  # Instagram lists
  for file in "$staging_dir"/*instagram*.json "$staging_dir"/*instagram*.csv "$staging_dir"/instagram.json; do
    if [ -f "$file" ]; then
      found_files=$((found_files + 1))
      if ! validate_instagram_list "$file"; then
        validation_failed=1
      fi
    fi
  done

  if [ $found_files -eq 0 ]; then
    add_warning "No output files found in staging directory"
    # Not an error - worker may have generated research notes only
  fi

  log_qa "=========================================="
  log_qa "Validation Summary"
  log_qa "=========================================="
  log_qa "Files validated: $found_files"
  log_qa "Errors: $(get_error_count)"
  log_qa "Warnings: $(get_warning_count)"

  if [ $validation_failed -eq 0 ] && [ "$(get_error_count)" -eq 0 ]; then
    log_success "All validations PASSED"
    return 0
  else
    log_error "Validation FAILED"
    return 1
  fi
}

# =============================================================================
# DIRECT INVOCATION
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -lt 1 ]; then
    echo "Usage: $0 <staging_directory>"
    echo "       $0 /path/to/staging/2025-01-15"
    exit 1
  fi

  validate_all "$1"
  exit $?
fi

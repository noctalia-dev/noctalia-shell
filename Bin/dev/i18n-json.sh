#!/usr/bin/env -S bash

# JSON Language File Comparison Script
# Compares language files against en.json reference and generates a report

set -euo pipefail

# Configuration
FOLDER_PATH="Assets/Translations"
REFERENCE_FILE="en.json"
TRANSLATE_MODE=false

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_color $RED "Error: 'jq' is required but not installed. Please install jq first." >&2
        print_color $YELLOW "On Ubuntu/Debian: sudo apt-get install jq" >&2
        print_color $YELLOW "On CentOS/RHEL: sudo yum install jq" >&2
        print_color $YELLOW "On macOS: brew install jq" >&2
        exit 1
    fi
    
    if $TRANSLATE_MODE && ! command -v curl &> /dev/null; then
        print_color $RED "Error: 'curl' is required for translation mode but not installed." >&2
        exit 1
    fi
}

# Function to get Gemini API key
get_gemini_api_key() {
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        print_color $RED "Error: GEMINI_API_KEY environment variable is not set" >&2
        print_color $YELLOW "Please set it with: export GEMINI_API_KEY='your-api-key'" >&2
        exit 1
    fi
    echo "$GEMINI_API_KEY"
}

# Function to get value from JSON using key path
get_json_value() {
    local json_file=$1
    local key_path=$2
    
    # Convert dot-separated path to jq path
    local jq_path=$(echo "$key_path" | sed 's/\./\.\["/g' | sed 's/$/"]/' | sed 's/^\.//')
    local jq_query=".${jq_path}"
    
    # Use a more robust approach: split by dots and build path
    local -a path_parts
    IFS='.' read -ra path_parts <<< "$key_path"
    
    local jq_filter="."
    for part in "${path_parts[@]}"; do
        jq_filter="${jq_filter}[\"${part}\"]"
    done
    
    jq -r "$jq_filter // empty" "$json_file" 2>/dev/null || echo ""
}

# Function to list available Gemini models
list_gemini_models() {
    local api_key=$(get_gemini_api_key)
    
    print_color $BLUE "Fetching available Gemini models..." >&2
    echo "" >&2
    
    local response=$(curl -s -X GET \
        "https://generativelanguage.googleapis.com/v1/models?key=${api_key}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    # Parse and display models
    echo "$response" | jq -r '.models[] | "- \(.name) (\(.displayName))"' 2>/dev/null || {
        print_color $RED "Failed to parse models list" >&2
        echo "$response" >&2
        exit 1
    }
    
    exit 0
}

# Function to translate text using Gemini API
translate_text() {
    local text=$1
    local target_language=$2
    local api_key=$3
    
    # Escape text for JSON
    local escaped_text=$(echo "$text" | jq -Rs .)
    
    # Prepare the API request
    local prompt="Translate the following English text to ${target_language}. Return ONLY the translation, no explanations or additional text:\n\n${text}"
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)
    
    local request_body=$(cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": ${escaped_prompt}
    }]
  }],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 1000
  }
}
EOF
)
    
    # Make API call to Gemini
    local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${api_key}"
    
    # print_color $BLUE "    API URL: $api_url" >&2
    
    local response=$(curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>/dev/null)
    
    # print_color $BLUE "    API Response: $response" >&2
    
    # Extract the translation from response - try multiple parsing approaches
    local translation=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // .text // empty' 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [[ -z "$translation" ]]; then
        print_color $RED "    Failed to parse translation. Full response:" >&2
        echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
        echo ""
        return 1
    fi
    
    print_color $GREEN "    Parsed translation: $translation" >&2
    
    echo "$translation"
}

# Function to inject translation into JSON file using jq
inject_translation() {
    local json_file=$1
    local key_path=$2
    local value=$3
    
    # Split key path into array
    local -a path_parts
    IFS='.' read -ra path_parts <<< "$key_path"
    
    # Build jq path array
    local jq_path="["
    for i in "${!path_parts[@]}"; do
        if [[ $i -gt 0 ]]; then
            jq_path+=","
        fi
        jq_path+="\"${path_parts[$i]}\""
    done
    jq_path+="]"
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Use jq to set the value at the path
    jq --argjson path "$jq_path" --arg value "$value" 'setpath($path; $value)' "$json_file" > "$temp_file"
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$json_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to remove a key from JSON file using jq
remove_json_key() {
    local json_file=$1
    local key_path=$2
    
    # Split key path into array
    local -a path_parts
    IFS='.' read -ra path_parts <<< "$key_path"
    
    # Build jq path array
    local jq_path="["
    for i in "${!path_parts[@]}"; do
        if [[ $i -gt 0 ]]; then
            jq_path+=","
        fi
        jq_path+="\"${path_parts[$i]}\""
    done
    jq_path+="]"
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Use jq to delete the path
    jq --argjson path "$jq_path" 'delpaths([$path])' "$json_file" > "$temp_file"
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$json_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to extract all keys from a JSON file recursively
extract_keys() {
    local json_file=$1
    
    if [[ ! -f "$json_file" ]]; then
        echo "Error: File $json_file not found" >&2
        return 1
    fi
    
    # Extract all keys recursively using jq
    jq -r '
        def keys_recursive:
            if type == "object" then
                keys[] as $k |
                if (.[$k] | type) == "object" then
                    ($k + "." + (.[$k] | keys_recursive))
                else
                    $k
                end
            else
                empty
            end;
        keys_recursive
    ' "$json_file" 2>/dev/null | sort
}

# Function to extract empty keys from a JSON file recursively
extract_empty_keys() {
    local json_file=$1
    
    if [[ ! -f "$json_file" ]]; then
        echo "Error: File $json_file not found" >&2
        return 1
    fi
    
    # Extract all keys with empty string or null values recursively using jq
    jq -r '
        def empty_keys_recursive:
            if type == "object" then
                keys[] as $k |
                if (.[$k] | type) == "object" then
                    ($k + "." + (.[$k] | empty_keys_recursive))
                elif (.[$k] == "" or .[$k] == null) then
                    $k
                else
                    empty
                end
            else
                empty
            end;
        empty_keys_recursive
    ' "$json_file" 2>/dev/null | sort
}

# Function to remove empty objects recursively from JSON file
remove_empty_objects() {
    local json_file=$1

    # Create a temporary file
    local temp_file=$(mktemp)

    # Use jq to recursively remove empty objects
    # This function walks the entire JSON tree and removes any object that contains no leaf values
    jq '
        def remove_empty:
            if type == "object" then
                to_entries |
                map(
                    .value |= remove_empty
                ) |
                map(
                    select(
                        .value != {} and
                        .value != [] and
                        .value != null and
                        .value != ""
                    )
                ) |
                from_entries |
                if length == 0 then empty else . end
            elif type == "array" then
                map(remove_empty) |
                map(select(. != null and . != {} and . != [] and . != ""))
            else
                .
            end;
        remove_empty
    ' "$json_file" > "$temp_file" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$json_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to sort JSON keys alphabetically (recursively)
sort_json_keys() {
    local json_file=$1

    # Create a temporary file
    local temp_file=$(mktemp)

    # Use jq to recursively sort all object keys
    jq --sort-keys '.' "$json_file" > "$temp_file" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$json_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Function to get language files
get_language_files() {
    find "$FOLDER_PATH" -maxdepth 1 -name "*.json" -type f | sort
}

# Function to generate report header
generate_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "================================================================================"
    echo "                     LANGUAGE FILE COMPARISON REPORT"
    echo "================================================================================"
    echo "Generated: $timestamp"
    echo "Reference file: $REFERENCE_FILE"
    echo "Folder: $(realpath "$FOLDER_PATH")"
    if $TRANSLATE_MODE; then
        echo "Mode: TRANSLATION ENABLED (translates missing keys, removes extra/empty keys and empty objects, sorts all keys alphabetically)"
    fi
    echo ""
    echo "Notes:"
    echo "- Keys are compared recursively through all nested JSON objects"
    echo "- Missing keys indicate incomplete translations"
    echo "- Extra keys might indicate deprecated keys or translation-specific additions"
    echo "- Empty keys are keys with empty string (\"\") or null values"
    echo "- Empty objects are nested objects containing no actual values (only other empty objects)"
    echo "- Translation completion percentage is calculated based on English reference"
    echo "- Results are sorted by descending line numbers for easier editing"
    if $TRANSLATE_MODE; then
        echo "- In translation mode, extra keys, empty keys, and empty objects are automatically removed"
        echo "- In translation mode, all keys are sorted alphabetically to ensure consistency across languages"
    fi
    echo ""
    echo "This report compares all language JSON files against the English reference file"
    echo "and identifies missing keys and extra keys in each language."
    echo ""
}

# Function to find line number of a key in JSON file
find_key_line_number() {
    local json_file=$1
    local key_path=$2
    
    # Extract the final key name (after last dot)
    local key_name="${key_path##*.}"
    
    # Search for the key in the file with line numbers
    # Look for the pattern "key": (with quotes and colon)
    local line_num=$(grep -n "\"$key_name\":" "$json_file" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
    
    if [[ -n "$line_num" ]]; then
        echo "$line_num"
    else
        # If not found with quotes, try without (though less reliable)
        line_num=$(grep -n "$key_name:" "$json_file" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
        if [[ -n "$line_num" ]]; then
            echo "$line_num"
        else
            echo "?"
        fi
    fi
}

# Function to safely count lines
count_non_empty_lines() {
    local content="$1"
    if [[ -z "$content" ]]; then
        echo "0"
    else
        echo "$content" | grep -c -v '^$' || echo "0"
    fi
}

# Function to compare keys and generate report section
compare_language() {
    local lang_file="$1"
    local lang_name="$2"
    local ref_keys_file="$3"
    local ref_file_path="$FOLDER_PATH/$REFERENCE_FILE"
    
    # Create temporary file for language keys
    local lang_keys_file=$(mktemp)
    extract_keys "$lang_file" > "$lang_keys_file" || {
        echo "Error: Failed to extract keys from $lang_file" >&2
        rm -f "$lang_keys_file"
        return 1
    }
    
    # Get missing and extra keys safely
    local missing_keys=""
    local extra_keys=""
    
    missing_keys=$(comm -23 "$ref_keys_file" "$lang_keys_file" 2>/dev/null || echo "")
    extra_keys=$(comm -13 "$ref_keys_file" "$lang_keys_file" 2>/dev/null || echo "")
    
    # Count lines safely
    local missing_count=$(count_non_empty_lines "$missing_keys")
    local extra_count=$(count_non_empty_lines "$extra_keys")
    local total_ref_keys=$(wc -l < "$ref_keys_file" 2>/dev/null || echo "0")
    local total_lang_keys=$(wc -l < "$lang_keys_file" 2>/dev/null || echo "0")
    
    # Calculate completion percentage safely
    local completion_percentage=0
    if [[ $total_ref_keys -gt 0 ]]; then
        completion_percentage=$(( (total_ref_keys - missing_count) * 100 / total_ref_keys ))
    fi
    
    print_color $YELLOW "================================================================================"
    print_color $YELLOW "LANGUAGE: $lang_name"
    print_color $YELLOW "================================================================================"
    echo "File: $lang_file"
    echo "Total keys in reference (en): $total_ref_keys"
    echo "Total keys in $lang_name: $total_lang_keys"
    
    # Color code the completion percentage
    if [[ $completion_percentage -eq 100 ]]; then
        echo -e "Translation completion: ${GREEN}${completion_percentage}%${NC}"
    else
        echo -e "Translation completion: ${RED}${completion_percentage}%${NC}"
    fi
    
    echo ""
    echo "SUMMARY:"
    echo "- Missing keys (exist in English but not in $lang_name): $missing_count"
    echo "- Extra keys (exist in $lang_name but not in English): $extra_count"
    echo ""

    # Handle missing keys
    if [[ $missing_count -gt 0 && -n "$missing_keys" ]]; then
        echo "MISSING KEYS IN $lang_name:"
        
        # Collect keys with line numbers and sort by line number (descending)
        local temp_missing=$(mktemp)
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                local ref_line=$(find_key_line_number "$ref_file_path" "$key")
                # Use numeric sort padding for proper sorting
                if [[ "$ref_line" =~ ^[0-9]+$ ]]; then
                    printf "%06d|%s|en.json:%s\n" "$ref_line" "$key" "$ref_line" >> "$temp_missing"
                else
                    printf "999999|%s|en.json:%s\n" "$key" "$ref_line" >> "$temp_missing"
                fi
            fi
        done <<< "$missing_keys"
        
        # Sort by line number (descending) and display
        local counter=1
        sort -t'|' -k1,1nr "$temp_missing" | while IFS='|' read -r sort_key key location; do
            printf "  %3d. %s (%s)\n" "$counter" "$key" "$location"
            counter=$((counter + 1))
        done
        rm -f "$temp_missing"
        echo ""
        
        # Translate missing keys if in translate mode
        if $TRANSLATE_MODE; then
            print_color $BLUE "Translating missing keys for $lang_name..." >&2
            local api_key=$(get_gemini_api_key)
            local translated_count=0
            local failed_count=0
            
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    # Get English value
                    local en_value=$(get_json_value "$ref_file_path" "$key")
                    
                    if [[ -n "$en_value" ]]; then
                        print_color $YELLOW "  Translating: $key" >&2
                        
                        # Translate the value
                        local translated_value=$(translate_text "$en_value" "$lang_name" "$api_key")
                        
                        if [[ -n "$translated_value" ]]; then
                            # Inject translation into the file
                            if inject_translation "$lang_file" "$key" "$translated_value"; then
                                print_color $GREEN "    ✓ Translated: $key" >&2
                                translated_count=$((translated_count + 1))
                            else
                                print_color $RED "    ✗ Failed to inject: $key" >&2
                                failed_count=$((failed_count + 1))
                            fi
                        else
                            print_color $RED "    ✗ Translation failed: $key" >&2
                            failed_count=$((failed_count + 1))
                        fi
                        
                        # Small delay to avoid rate limiting
                        sleep 0.5
                    fi
                fi
            done <<< "$missing_keys"
            
            echo ""
            print_color $GREEN "Translation complete: $translated_count succeeded, $failed_count failed" >&2
            echo ""
        fi
    else
        echo "✅ No missing keys in $lang_name"
        echo ""
    fi
    
    # Handle extra keys
    if [[ $extra_count -gt 0 && -n "$extra_keys" ]]; then
        echo "EXTRA KEYS IN $lang_name (not in English):"
        
        # Collect keys with line numbers and sort by line number (descending)
        local temp_extra=$(mktemp)
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                local lang_line=$(find_key_line_number "$lang_file" "$key")
                # Use numeric sort padding for proper sorting
                if [[ "$lang_line" =~ ^[0-9]+$ ]]; then
                    printf "%06d|%s|%s:%s\n" "$lang_line" "$key" "$(basename "$lang_file")" "$lang_line" >> "$temp_extra"
                else
                    printf "999999|%s|%s:%s\n" "$key" "$(basename "$lang_file")" "$lang_line" >> "$temp_extra"
                fi
            fi
        done <<< "$extra_keys"
        
        # Sort by line number (descending) and display
        local counter=1
        sort -t'|' -k1,1nr "$temp_extra" | while IFS='|' read -r sort_key key location; do
            printf "  %3d. %s (%s)\n" "$counter" "$key" "$location"
            counter=$((counter + 1))
        done
        rm -f "$temp_extra"
        echo ""
        
        # Remove extra keys if in translate mode
        if $TRANSLATE_MODE; then
            print_color $BLUE "Removing extra keys from $lang_name..." >&2
            local removed_count=0
            local failed_removal_count=0
            
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    print_color $YELLOW "  Removing: $key" >&2
                    
                    if remove_json_key "$lang_file" "$key"; then
                        print_color $GREEN "    ✓ Removed: $key" >&2
                        removed_count=$((removed_count + 1))
                    else
                        print_color $RED "    ✗ Failed to remove: $key" >&2
                        failed_removal_count=$((failed_removal_count + 1))
                    fi
                fi
            done <<< "$extra_keys"
            
            echo ""
            print_color $GREEN "Removal complete: $removed_count removed, $failed_removal_count failed" >&2
            echo ""
        fi
    else
        echo "✅ No extra keys in $lang_name"
        echo ""
    fi
    
    # Handle empty keys in translate mode
    if $TRANSLATE_MODE; then
        local empty_keys=$(extract_empty_keys "$lang_file")
        local empty_count=$(count_non_empty_lines "$empty_keys")
        
        if [[ $empty_count -gt 0 && -n "$empty_keys" ]]; then
            echo "EMPTY KEYS IN $lang_name:"
            
            # Display empty keys
            local counter=1
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    local lang_line=$(find_key_line_number "$lang_file" "$key")
                    printf "  %3d. %s (%s:%s)\n" "$counter" "$key" "$(basename "$lang_file")" "$lang_line"
                    counter=$((counter + 1))
                fi
            done <<< "$empty_keys"
            echo ""
            
            print_color $BLUE "Removing empty keys from $lang_name..." >&2
            local removed_empty_count=0
            local failed_empty_removal_count=0
            
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    print_color $YELLOW "  Removing empty key: $key" >&2
                    
                    if remove_json_key "$lang_file" "$key"; then
                        print_color $GREEN "    ✓ Removed: $key" >&2
                        removed_empty_count=$((removed_empty_count + 1))
                    else
                        print_color $RED "    ✗ Failed to remove: $key" >&2
                        failed_empty_removal_count=$((failed_empty_removal_count + 1))
                    fi
                fi
            done <<< "$empty_keys"
            
            echo ""
            print_color $GREEN "Empty key removal complete: $removed_empty_count removed, $failed_empty_removal_count failed" >&2
            echo ""
        else
            echo "✅ No empty keys in $lang_name"
            echo ""
        fi
        
        # Remove empty objects (nested objects with no actual values)
        print_color $BLUE "Cleaning up empty objects in $lang_name..." >&2
        if remove_empty_objects "$lang_file"; then
            print_color $GREEN "✓ Successfully removed all empty objects" >&2
            echo ""
        else
            print_color $RED "✗ Failed to clean up empty objects" >&2
            echo ""
        fi

        # Sort all keys alphabetically to maintain consistency across language files
        print_color $BLUE "Sorting keys alphabetically in $lang_name..." >&2
        if sort_json_keys "$lang_file"; then
            print_color $GREEN "✓ Keys sorted alphabetically" >&2
            echo ""
        else
            print_color $RED "✗ Failed to sort keys" >&2
            echo ""
        fi
    fi

    # Clean up
    rm -f "$lang_keys_file"
}

# Main function
main() {
    local target_language="$1"
    
    print_color $BLUE "Starting language file comparison..." >&2
    
    # Check dependencies
    check_dependencies
    
    # Validate folder path
    if [[ ! -d "$FOLDER_PATH" ]]; then
        print_color $RED "Error: Folder '$FOLDER_PATH' does not exist" >&2
        exit 1
    fi
    
    # Check if reference file exists
    local ref_file_path="$FOLDER_PATH/$REFERENCE_FILE"
    if [[ ! -f "$ref_file_path" ]]; then
        print_color $RED "Error: Reference file '$ref_file_path' does not exist" >&2
        exit 1
    fi
    
    print_color $GREEN "Reference file found: $ref_file_path" >&2
    
    # Extract keys from reference file
    local ref_keys_file=$(mktemp)
    if ! extract_keys "$ref_file_path" > "$ref_keys_file"; then
        print_color $RED "Error: Failed to extract keys from reference file" >&2
        rm -f "$ref_keys_file"
        exit 1
    fi
    
    local total_ref_keys=$(wc -l < "$ref_keys_file" 2>/dev/null || echo "0")
    
    print_color $BLUE "Extracted $total_ref_keys keys from reference file" >&2
    
    # Get all language files or just the target language
    local -a language_files
    if [[ -n "$target_language" ]]; then
        # Single language mode
        local target_file="$FOLDER_PATH/${target_language}.json"
        if [[ ! -f "$target_file" ]]; then
            print_color $RED "Error: Language file '$target_file' does not exist" >&2
            rm -f "$ref_keys_file"
            exit 1
        fi
        if [[ "$target_language" == "${REFERENCE_FILE%.json}" ]]; then
            print_color $RED "Error: Cannot compare reference file against itself" >&2
            rm -f "$ref_keys_file"
            exit 1
        fi
        language_files=("$target_file")
        print_color $BLUE "Checking single language: $target_language" >&2
    else
        # All languages mode
        while IFS= read -r -d '' file; do
            language_files+=("$file")
        done < <(find "$FOLDER_PATH" -maxdepth 1 -name "*.json" -type f -print0 | sort -z)
        
        if [[ ${#language_files[@]} -eq 0 ]]; then
            print_color $RED "Error: No JSON files found in $FOLDER_PATH" >&2
            rm -f "$ref_keys_file"
            exit 1
        fi
        print_color $BLUE "Found ${#language_files[@]} JSON files to process" >&2
    fi
    
    echo "" >&2
    
    # Generate report header
    generate_header

    # Sort the English reference file if in translate mode
    if $TRANSLATE_MODE; then
        print_color $BLUE "Sorting keys alphabetically in English reference file..." >&2
        if sort_json_keys "$ref_file_path"; then
            print_color $GREEN "✓ English reference file keys sorted alphabetically" >&2
            echo "" >&2
        else
            print_color $RED "✗ Failed to sort English reference file keys" >&2
            echo "" >&2
        fi
    fi

    local processed=0
    for lang_file in "${language_files[@]}"; do
        local filename=$(basename "$lang_file")
        local lang_name="${filename%.json}"

        # Skip the reference file in all-languages mode
        if [[ -z "$target_language" && "$filename" == "$REFERENCE_FILE" ]]; then
            continue
        fi
        
        print_color $YELLOW "Processing: $filename" >&2
        
        # Validate JSON syntax
        if ! jq empty "$lang_file" 2>/dev/null; then
            print_color $RED "Warning: $lang_file contains invalid JSON syntax. Skipping..." >&2
            echo "ERROR: $lang_file contains invalid JSON syntax and was skipped."
            echo ""
            continue
        fi
        
        if compare_language "$lang_file" "$lang_name" "$ref_keys_file"; then
            processed=$((processed + 1))
        else
            print_color $RED "Error processing $lang_file" >&2
        fi
    done
    
    # Add summary at the end
    echo "================================================================================"
    echo "SUMMARY"
    echo "================================================================================"
    echo "Total files processed: $processed"
    echo "Reference file: $REFERENCE_FILE (English)"
    if [[ -n "$target_language" ]]; then
        echo "Target language: $target_language"
    fi
    if $TRANSLATE_MODE; then
        echo "Translation mode: ENABLED (translated missing keys, removed extra keys, removed empty keys and objects, sorted keys alphabetically)"
    fi
    echo "Report generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "================================================================================"
    
    # Clean up
    rm -f "$ref_keys_file"
    
    if [[ -n "$target_language" ]]; then
        print_color $GREEN "Comparison completed for language: $target_language" >&2
    else
        print_color $GREEN "Comparison completed: Processed $processed language files against English reference" >&2
    fi
}

# Usage information
show_usage() {
    echo "Usage: $0 [--translate] [language_code]" >&2
    echo "" >&2
    echo "This script compares JSON language files in '$FOLDER_PATH' against the English reference." >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  --translate    Enable automatic translation of missing keys, removal of extra keys," >&2
    echo "                 removal of empty keys (empty strings or null values), removal of" >&2
    echo "                 empty objects (nested objects containing no actual values), and" >&2
    echo "                 alphabetical sorting of all keys for consistency" >&2
    echo "  --list-models  List all available Gemini models and exit" >&2
    echo "  language_code  Optional. Compare only the specified language (e.g., 'fr', 'es', 'de')" >&2
    echo "                 If not provided, all language files will be compared" >&2
    echo "" >&2
    echo "Configuration:" >&2
    echo "  - Folder path: $FOLDER_PATH (hardcoded)" >&2
    echo "  - Reference file: $REFERENCE_FILE" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0                    # Compare all languages" >&2
    echo "  $0 fr                 # Compare only French (fr.json)" >&2
    echo "  $0 --list-models      # List available Gemini models" >&2
    echo "  $0 --translate        # Compare all, translate missing, remove extra/empty keys and objects, sort keys" >&2
    echo "  $0 --translate fr     # Translate, clean, and sort French only" >&2
    echo "" >&2
    echo "Requirements:" >&2
    echo "  - jq must be installed" >&2
    echo "  - curl must be installed (for --translate mode)" >&2
    echo "  - $REFERENCE_FILE must exist in $FOLDER_PATH" >&2
    echo "  - Target language file must exist if specified" >&2
    echo "  - GEMINI_API_KEY environment variable must be set (for --translate mode)" >&2
    echo "" >&2
    echo "Output:" >&2
    echo "  - Comparison report is printed to stdout" >&2
    echo "  - Progress messages are printed to stderr" >&2
    echo "  - Results are sorted by descending line numbers for easier editing" >&2
    echo "  - In translate mode, extra keys, empty keys, and empty objects are removed" >&2
    echo "  - In translate mode, all keys are sorted alphabetically for consistency" >&2
}

# Handle command line arguments
target_lang=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --list-models)
            list_gemini_models
            ;;
        --translate)
            TRANSLATE_MODE=true
            shift
            ;;
        *)
            if [[ -n "$target_lang" ]]; then
                echo "Error: Too many arguments. Only one language code is allowed." >&2
                echo "" >&2
                show_usage
                exit 1
            fi
            # Validate language code format (basic check for reasonable filename)
            if [[ ! "$1" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
                echo "Error: Invalid language code format '$1'. Use alphanumeric characters, hyphens, and underscores only." >&2
                echo "" >&2
                show_usage
                exit 1
            fi
            target_lang="$1"
            shift
            ;;
    esac
done

# Run main function
main "$target_lang"
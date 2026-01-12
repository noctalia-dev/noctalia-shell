#!/bin/bash

# Push translations to Noctalia Translate API
# Usage: TRANSLATION_PUSH_SECRET=your_secret ./push-translations.sh [--overwrite] [/path/to/Assets/Translations]
# Or set the secret in environment and pass the path as argument

set -e

# Parse arguments
OVERWRITE=false
TRANSLATIONS_DIR="Assets/Translations"

for arg in "$@"; do
    case $arg in
        --overwrite)
            OVERWRITE=true
            ;;
        *)
            TRANSLATIONS_DIR="$arg"
            ;;
    esac
done

# Configuration
API_URL="${TRANSLATION_API_URL:-https://i18n.noctalia.dev}"
PROJECT_SLUG="${TRANSLATION_PROJECT:-noctalia-shell}"

# Check for secret
if [ -z "$NOCTALIA_SHELL_TRANSLATION_PUSH_SECRET" ]; then
    echo "Error: NOCTALIA_SHELL_TRANSLATION_PUSH_SECRET environment variable is required"
    exit 1
fi

# Check if directory exists
if [ ! -d "$TRANSLATIONS_DIR" ]; then
    echo "Error: Directory not found: $TRANSLATIONS_DIR"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Install with: apt install jq"
    exit 1
fi

echo "Pushing translations from: $TRANSLATIONS_DIR"
echo "Target: $API_URL/api/projects/$PROJECT_SLUG/push"

# Build combined JSON object
COMBINED_JSON="{}"

for file in "$TRANSLATIONS_DIR"/*.json; do
    if [ -f "$file" ]; then
        # Extract locale from filename (e.g., en.json -> en)
        filename=$(basename "$file")
        locale="${filename%.json}"

        echo "  Loading: $locale ($filename)"

        # Add this locale's translations to the combined object
        COMBINED_JSON=$(echo "$COMBINED_JSON" | jq --arg locale "$locale" --slurpfile content "$file" '. + {($locale): $content[0]}')
    fi
done

# Count locales
LOCALE_COUNT=$(echo "$COMBINED_JSON" | jq 'keys | length')
echo "Found $LOCALE_COUNT locale(s)"

if [ "$LOCALE_COUNT" -eq 0 ]; then
    echo "Error: No JSON files found in $TRANSLATIONS_DIR"
    exit 1
fi

# Check if English exists
if ! echo "$COMBINED_JSON" | jq -e '.en' > /dev/null 2>&1; then
    echo "Error: English (en.json) is required"
    exit 1
fi

# Confirmation
echo ""
read -p "Push $LOCALE_COUNT locale(s) to $API_URL? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Build URL with optional overwrite parameter
PUSH_URL="$API_URL/api/projects/$PROJECT_SLUG/push"
if [ "$OVERWRITE" = true ]; then
    PUSH_URL="$PUSH_URL?overwrite=true"
    echo "Overwrite mode enabled"
fi

# Push to API
echo "Pushing to API..."
RESPONSE=$(echo "$COMBINED_JSON" | curl -s -w "\n%{http_code}" -X POST \
    "$PUSH_URL" \
    -H "Authorization: Bearer $NOCTALIA_SHELL_TRANSLATION_PUSH_SECRET" \
    -H "Content-Type: application/json" \
    -d @-)

# Extract HTTP status code (last line) and body (everything else)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "Success!"
    echo "$BODY" | jq .
else
    echo "Error: HTTP $HTTP_CODE"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi

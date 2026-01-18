#!/usr/bin/env bash
# Generate a registry.json from all color schemes in Assets/ColorScheme
# Output format matches ~/Development/misc/noctalia/noctalia-colorschemes/registry.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COLORSCHEME_DIR="$PROJECT_ROOT/Assets/ColorScheme"

# Start JSON output
echo '{'
echo '  "version": 1,'
echo '  "themes": ['

first=true
for dir in "$COLORSCHEME_DIR"/*/; do
  [ -d "$dir" ] || continue

  name=$(basename "$dir")
  json_file="$dir/$name.json"

  [ -f "$json_file" ] || continue

  # Read the JSON file content
  content=$(cat "$json_file")

  # Extract dark and light objects using jq
  dark=$(echo "$content" | jq -c '.dark')
  light=$(echo "$content" | jq -c '.light')

  # Skip if missing dark or light
  [ "$dark" = "null" ] || [ "$light" = "null" ] && continue

  # Add comma before all but first entry
  if [ "$first" = true ]; then
    first=false
  else
    echo ','
  fi

  # Output theme entry
  printf '    {\n'
  printf '      "name": "%s",\n' "$name"
  printf '      "path": "%s",\n' "$name"
  printf '      "dark": %s,\n' "$dark"
  printf '      "light": %s\n' "$light"
  printf '    }'
done

echo ''
echo '  ]'
echo '}'

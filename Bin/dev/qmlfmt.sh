#!/usr/bin/env -S bash
set -euo pipefail

# QML Formatter Script
# Uses: https://github.com/jesperhh/qmlfmt
# Install: AUR package "qmlfmt-git" (requires qt6-5compat)

# Find the available QML formatter command and define format_file accordingly
if command -v qmlfmt &>/dev/null; then
    echo "Using 'qmlfmt' for formatting."
    format_file() { qmlfmt -e -b 360 -t 2 -i 2 -w "$1" || { echo "Failed: $1" >&2; return 1; }; }
elif command -v qmlformat &>/dev/null; then
    echo "Using 'qmlformat' for formatting."
    format_file() { qmlformat -i -t --indent-width 2 -W 360 "$1" && sed -i 's/;[[:space:]]*$//' "$1" || { echo "Failed: $1" >&2; return 1; }; }
else
    echo "Neither 'qmlfmt' nor 'qmlformat' found in PATH." >&2
    exit 1
fi

export -f format_file

# Find all .qml files
mapfile -t all_files < <(find "${1:-.}" -name "*.qml" -type f)
[ ${#all_files[@]} -eq 0 ] && { echo "No QML files found"; exit 0; }

echo "Scanning ${#all_files[@]} files for array destructuring..."
safe_files=()
for file in "${all_files[@]}"; do
    # Checks for a comma inside brackets followed by an equals sign aka "array destructuring"
    # as this ES6 syntax is not supported by qmlfmt and will result in breakage.
    if grep -qE '\[.*,.*\]\s*=' "$file"; then
        echo "-> Skipping (Array destructuring detected): $file" >&2
    else
        safe_files+=("$file")
    fi
done

[ ${#safe_files[@]} -eq 0 ] && { echo "No safe files to format after filtering."; exit 0; }

echo "Formatting ${#safe_files[@]} files..."
printf '%s\0' "${safe_files[@]}" | \
    xargs -0 -P "${QMLFMT_JOBS:-$(nproc)}" -I {} bash -c 'format_file "$@"' _ {} \
    && echo "Done" || { echo "Errors occurred" >&2; exit 1; }
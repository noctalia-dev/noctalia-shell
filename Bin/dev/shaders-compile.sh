#!/bin/bash

# Find qsb binary in common locations.
QSB_PATHS=(
    "/usr/lib/qt6/bin/qsb"
    "/usr/lib64/qt6/bin/qsb"
)

QSB_BIN=""
for path in "${QSB_PATHS[@]}"; do
    if [ -x "$path" ]; then
        QSB_BIN="$path"
        break
    fi
done

if [ -z "$QSB_BIN" ]; then
    echo "Error: qsb binary not found in any of: ${QSB_PATHS[*]}"
    exit 1
fi

# Directory containing the source shaders.
SOURCE_DIR="Shaders/frag/"

# Directory where the compiled shaders will be saved.
DEST_DIR="Shaders/qsb/"

# Check if the source directory exists.
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source directory $SOURCE_DIR not found!"
    exit 1
fi

# Create the destination directory if it doesn't exist.
mkdir -p "$DEST_DIR"

# Array to hold the list of full paths to the shaders.
SHADERS_TO_COMPILE=()

# Specific files mode.
if [ "$#" -gt 0 ]; then

    # Loop through all command-line arguments ($@ holds all arguments).
    for SINGLE_FILE in "$@"; do

        # Construct the full path to the source file.
        FULL_PATH="$SOURCE_DIR$SINGLE_FILE"

        # Check if the specified file exists in the SOURCE_DIR.
        if [ ! -f "$FULL_PATH" ]; then
            echo "Error: Specified file '$SINGLE_FILE' not found in $SOURCE_DIR! Skipping."
            continue
        fi

        # Add the valid file to the compilation list.
        SHADERS_TO_COMPILE+=("$FULL_PATH")
    done

    # Check if any valid files were found to compile.
    if [ ${#SHADERS_TO_COMPILE[@]} -eq 0 ]; then
        echo "No valid shaders found to compile."
        exit 1
    fi

# Whole directory mode (no argument provided).
else
    # Use find to generate the list of files and assign it to the array.
    while IFS= read -r shader_path; do
        if [ -n "$shader_path" ]; then
            SHADERS_TO_COMPILE+=("$shader_path")
        fi
    done < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.frag")

fi

# Loop through the list of shaders to compile.
for shader in "${SHADERS_TO_COMPILE[@]}"; do

    # Get the base name of the file (e.g., wp_fade).
    shader_name=$(basename "$shader" .frag)

    # Construct the output path for the compiled shader.
    output_path="$DEST_DIR$shader_name.frag.qsb"

    # Construct and run the qsb command.
    "$QSB_BIN" --qt6 -o "$output_path" "$shader"

    # Print a message to confirm compilation.
    echo "Compiled $(basename "$shader") to $output_path"
done

echo "Shader compilation complete."

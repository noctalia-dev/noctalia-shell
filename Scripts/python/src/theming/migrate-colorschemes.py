#!/usr/bin/env python3
import os
import json
import sys
import urllib.request
import urllib.parse
from pathlib import Path

# Registry URL for color schemes
REGISTRY_URL = "https://raw.githubusercontent.com/noctalia-dev/noctalia-colorschemes/main/registry.json"
RAW_BASE_URL = "https://raw.githubusercontent.com/noctalia-dev/noctalia-colorschemes/main/"

def is_valid_format(data):
    """Check if the scheme data has the new terminal format."""
    for variant in ['dark', 'light']:
        if variant in data:
            v_data = data[variant]
            if isinstance(v_data, dict) and 'terminal' in v_data:
                term = v_data['terminal']
                if isinstance(term, dict) and 'normal' in term:
                    if isinstance(term['normal'], dict) and 'black' in term['normal']:
                        return True
    return False

def get_registry():
    """Fetch the remote registry to get correct paths for schemes."""
    try:
        with urllib.request.urlopen(REGISTRY_URL) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        print(f"Error fetching registry: {e}")
        return None

def migrate(config_dir):
    colorschemes_dir = Path(config_dir) / "colorschemes"
    if not colorschemes_dir.exists():
        return

    registry = get_registry()
    if not registry:
        return

    # Map name to path from registry
    theme_map = {t['name']: t['path'] for t in registry.get('themes', [])}

    for scheme_dir in colorschemes_dir.iterdir():
        if not scheme_dir.is_dir():
            continue

        scheme_name = scheme_dir.name
        json_file = scheme_dir / f"{scheme_name}.json"

        if not json_file.exists():
            continue

        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
        except Exception:
            continue

        if not is_valid_format(data):
            print(f"Scheme '{scheme_name}' has old format. Attempting to redownload...")
            
            # Use registry path if available, otherwise fallback to name
            remote_path = theme_map.get(scheme_name, scheme_name)
            
            # Encode URL parts to handle spaces and special characters
            encoded_path = urllib.parse.quote(remote_path)
            encoded_name = urllib.parse.quote(scheme_name)
            remote_url = f"{RAW_BASE_URL}{encoded_path}/{encoded_name}.json"
            
            try:
                with urllib.request.urlopen(remote_url) as response:
                    new_data = json.loads(response.read().decode())
                    with open(json_file, 'w') as f:
                        json.dump(new_data, f, indent=2)
                
                print(f"Successfully migrated '{scheme_name}'")
            except Exception as e:
                print(f"Failed to migrate '{scheme_name}': {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: migrate-colorschemes.py <config_dir>")
        sys.exit(1)
    
    migrate(sys.argv[1])

#!/usr/bin/env python3
"""
Build settings search index from QML source files.

Parses settings tab QML files to extract searchable metadata
(i18n keys, widget types, tab/sub-tab locations).

Output: Assets/settings-search-index.json

Usage:
  python Scripts/dev/build-settings-search-index.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SETTINGS_DIR = ROOT / "Modules" / "Panels" / "Settings"
TABS_DIR = SETTINGS_DIR / "Tabs"
OUTPUT = ROOT / "Assets" / "settings-search-index.json"

# Widget types that have searchable label/description
WIDGET_TYPES = (
    "NToggle",
    "NComboBox",
    "NValueSlider",
    "NSpinBox",
    "NSearchableComboBox",
    "NTextInputButton",
    "NTextInput",
    "NCheckbox",
    "NLabel",
    "HookRow",
)

# Regex patterns
RE_WIDGET_OPEN = re.compile(
    r"^\s*(" + "|".join(WIDGET_TYPES) + r")\s*\{", re.MULTILINE
)
RE_LABEL = re.compile(r'label:\s*I18n\.tr\("([^"]+)"')
RE_DESCRIPTION = re.compile(r'description:\s*I18n\.tr\("([^"]+)"')


def parse_component_declarations(content: str) -> dict[str, str]:
    """
    Parse Component declarations from SettingsContent.qml.

    Returns: component_id -> QML type name (e.g. "generalTab" -> "GeneralTab")
    """
    components = {}
    # Match patterns like:
    #   Component {
    #     id: generalTab
    #     GeneralTab {}
    #   }
    pattern = re.compile(
        r"Component\s*\{\s*\n\s*id:\s*(\w+)\s*\n\s*(\w+)\s*\{",
        re.MULTILINE,
    )
    for m in pattern.finditer(content):
        comp_id = m.group(1)
        type_name = m.group(2)
        components[comp_id] = type_name

    return components


def parse_tabs_model_order(content: str) -> list[tuple[str, str]]:
    """
    Parse updateTabsModel() to get the ordered list of (source_id, label_key) pairs.

    Returns: list of (component_id, i18n_label_key) in display order.
    """
    # Find the updateTabsModel function body
    match = re.search(r"function updateTabsModel\(\)\s*\{", content)
    if not match:
        return []

    func_body = content[match.end():]

    # Extract tab entries: each has "label" and "source" fields
    entries = []
    for m in re.finditer(
        r'"label":\s*"([^"]+)"[^}]*?"source":\s*(\w+)',
        func_body,
        re.DOTALL,
    ):
        entries.append((m.group(2), m.group(1)))

    return entries


def build_tab_mappings(content: str) -> tuple[dict[str, int], dict[str, str]]:
    """
    Build mappings from QML type name to tabsModel index and label key.

    Parses Component declarations and updateTabsModel() order.
    Returns: (type_to_index, type_to_label)
      - type_to_index: e.g. {"GeneralTab": 0, ...}
      - type_to_label: e.g. {"GeneralTab": "common.general", ...}
    """
    components = parse_component_declarations(content)
    entries = parse_tabs_model_order(content)

    type_to_index = {}
    type_to_label = {}
    for idx, (source_id, label_key) in enumerate(entries):
        type_name = components.get(source_id)
        if type_name:
            type_to_index[type_name] = idx
            type_to_label[type_name] = label_key

    return type_to_index, type_to_label


def get_subtab_info(parent_tab_file: Path) -> tuple[list[str], list[str | None]]:
    """
    Parse a parent tab file to get subtab order and labels.

    Returns: (subtab_type_names, subtab_label_keys)
      - subtab_type_names: list of component names like ["VolumesSubTab", ...]
      - subtab_label_keys: list of i18n keys like ["common.volumes", ...] (same order)
    """
    content = parent_tab_file.read_text()

    # Extract NTabButton labels in order from NTabBar
    labels = []
    in_tabbar = False
    tabbar_depth = 0

    for line in content.splitlines():
        stripped = line.strip()

        if not in_tabbar:
            if re.match(r"NTabBar\s*\{", stripped):
                in_tabbar = True
                tabbar_depth = 1
                continue
            continue

        tabbar_depth += stripped.count("{") - stripped.count("}")

        if tabbar_depth <= 0:
            break

        # Match text: I18n.tr("...") inside NTabButton
        m = re.search(r'text:\s*I18n\.tr\("([^"]+)"', stripped)
        if m:
            labels.append(m.group(1))

    # Extract subtab component names from NTabView
    subtabs = []
    in_tabview = False
    tabview_depth = 0

    for line in content.splitlines():
        stripped = line.strip()

        if not in_tabview:
            if re.match(r"NTabView\s*\{", stripped):
                in_tabview = True
                tabview_depth = 1
                continue
            continue

        tabview_depth += stripped.count("{") - stripped.count("}")

        if tabview_depth <= 0:
            break

        # Match component instantiations like "VolumesSubTab {}" or "VolumesSubTab {"
        m = re.match(r"(\w+SubTab)\s*\{", stripped)
        if m:
            subtabs.append(m.group(1))

    # Pad labels list if shorter than subtabs (shouldn't happen, but safety)
    while len(labels) < len(subtabs):
        labels.append(None)

    return subtabs, labels[:len(subtabs)]


def resolve_tab_info(
    qml_file: Path,
    type_to_index: dict[str, int],
    type_to_label: dict[str, str],
) -> tuple[int | None, str | None, int | None, str | None]:
    """
    Determine the tab index, tab label, sub-tab index, and sub-tab label for a QML file.

    Returns (tab_index, tab_label_key, sub_tab_index, sub_tab_label_key)
    """
    parent = qml_file.parent
    stem = qml_file.stem

    # Top-level tab files (directly in Tabs/)
    if parent == TABS_DIR:
        tab_index = type_to_index.get(stem)
        tab_label = type_to_label.get(stem)
        return tab_index, tab_label, None, None

    # Sub-directory files
    dir_name = parent.name  # e.g. "Audio", "Bar"
    parent_type = f"{dir_name}Tab"  # e.g. "AudioTab"
    tab_index = type_to_index.get(parent_type)
    tab_label = type_to_label.get(parent_type)

    if tab_index is None:
        return None, None, None, None

    # Skip the parent tab file itself (e.g. AudioTab.qml) — still scan for widgets
    if stem.endswith("Tab") and not stem.endswith("SubTab"):
        return tab_index, tab_label, None, None

    # Determine sub-tab index and label from parent tab's NTabBar/NTabView
    parent_tab_file = parent / f"{dir_name}Tab.qml"
    if not parent_tab_file.exists():
        return tab_index, tab_label, None, None

    subtab_names, subtab_labels = get_subtab_info(parent_tab_file)
    try:
        idx = subtab_names.index(stem)
        sub_label = subtab_labels[idx] if idx < len(subtab_labels) else None
        return tab_index, tab_label, idx, sub_label
    except ValueError:
        # File doesn't map to any subtab (e.g. a dialog). If the parent tab
        # has subtabs, the focus ring can't reach widgets inside dialogs, so
        # exclude them from the index.
        if subtab_names:
            return None, None, None, None
        return tab_index, tab_label, None, None


def extract_widget_blocks(content: str) -> list[tuple[str, str]]:
    """
    Extract (widget_type, block_text) pairs from QML content.

    Uses brace-depth tracking to capture the full widget block.
    """
    results = []
    lines = content.splitlines()
    i = 0

    while i < len(lines):
        m = RE_WIDGET_OPEN.match(lines[i])
        if m:
            widget_type = m.group(1)
            depth = 0
            block_lines = []
            j = i

            while j < len(lines):
                line = lines[j]
                block_lines.append(line)
                depth += line.count("{") - line.count("}")
                if depth <= 0:
                    break
                j += 1

            block_text = "\n".join(block_lines)
            results.append((widget_type, block_text))
            i = j + 1
        else:
            i += 1

    return results


def extract_entries(
    qml_file: Path,
    type_to_index: dict[str, int],
    type_to_label: dict[str, str],
) -> list[dict]:
    """Extract all searchable settings entries from a QML file."""
    tab_index, tab_label, sub_tab, sub_tab_label = resolve_tab_info(
        qml_file, type_to_index, type_to_label
    )
    if tab_index is None:
        return []

    content = qml_file.read_text()
    entries = []

    for widget_type, block in extract_widget_blocks(content):
        label_match = RE_LABEL.search(block)
        if not label_match:
            continue

        label_key = label_match.group(1)
        desc_match = RE_DESCRIPTION.search(block)
        desc_key = desc_match.group(1) if desc_match else None

        entry = {
            "labelKey": label_key,
            "descriptionKey": desc_key,
            "widget": widget_type,
            "tab": tab_index,
            "tabLabel": tab_label,
            "subTab": sub_tab,
        }
        if sub_tab_label is not None:
            entry["subTabLabel"] = sub_tab_label

        entries.append(entry)

    return entries


def main():
    if not TABS_DIR.exists():
        print(f"Error: Tabs directory not found: {TABS_DIR}", file=sys.stderr)
        sys.exit(1)

    settings_content = SETTINGS_DIR / "SettingsContent.qml"
    if not settings_content.exists():
        print(f"Error: SettingsContent.qml not found: {settings_content}", file=sys.stderr)
        sys.exit(1)

    # Build type -> tabsModel index/label mappings from SettingsContent.qml
    content = settings_content.read_text()
    type_to_index, type_to_label = build_tab_mappings(content)

    if not type_to_index:
        print("Error: Could not parse tab model from SettingsContent.qml", file=sys.stderr)
        sys.exit(1)

    print(f"Parsed {len(type_to_index)} tab types from SettingsContent.qml")

    all_entries = []
    seen_labels = set()

    # Scan all QML files in Tabs/ (recursive)
    for qml_file in sorted(TABS_DIR.rglob("*.qml")):
        entries = extract_entries(qml_file, type_to_index, type_to_label)
        for entry in entries:
            if entry["labelKey"] not in seen_labels:
                seen_labels.add(entry["labelKey"])
                all_entries.append(entry)

    # Write output
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(all_entries, f, indent=2)

    print(f"Generated {len(all_entries)} entries -> {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

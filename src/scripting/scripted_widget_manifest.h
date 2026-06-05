#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace scripting {

  enum class ManifestFieldType : std::uint8_t {
    Bool,
    Int,
    Double,
    String,
    File,
    Folder,
    Glyph,
    Select,
    Color,
  };

  struct ManifestSelectOption {
    std::string value;
    std::string label;
  };

  struct ManifestVisibility {
    std::string key;
    std::vector<std::string> values;
  };

  struct ManifestField {
    std::string key;
    std::string label;
    std::string description;
    ManifestFieldType type = ManifestFieldType::String;

    // Typed default; the active member is selected by `type`.
    bool boolDefault = false;
    double numberDefault = 0.0;
    std::string stringDefault;

    std::optional<double> minValue;
    std::optional<double> maxValue;
    double step = 1.0;
    std::vector<ManifestSelectOption> options;
    std::vector<std::string> extensions;
    bool advanced = false;
    std::optional<ManifestVisibility> visibleWhen;
  };

  struct ScriptWidgetManifest {
    std::string label;
    std::string version;
    std::string icon;
    std::string description;
    bool pickable = true;
    std::vector<ManifestField> settings;
  };

  // A scripted widget discovered in the bundled scripts directory that declared
  // a manifest via `barWidget.define`.
  struct DiscoveredScript {
    std::string id;          // derived from the script filename, e.g. "screen_recorder"
    std::string assetScript; // asset-relative script path, e.g. "scripts/screen_recorder.lua"
    ScriptWidgetManifest manifest;
  };

  // Expand a leading `~` / `~/` to $HOME. Other paths are returned unchanged.
  [[nodiscard]] std::string expandUserPath(std::string_view path);

  // Resolve a `script` config value the same way ScriptedWidget does:
  // `~` -> $HOME, absolute paths verbatim, otherwise relative to the asset root.
  [[nodiscard]] std::filesystem::path resolveScriptPath(const std::string& path);

  // Run `resolvedScript` in manifest-extraction mode (side-effecting `noctalia.*`
  // top-level code is short-circuited by aborting at the `barWidget.define` call)
  // and return the declared manifest, or nullopt if the script declares none.
  // Results are cached by (path, mtime, size).
  [[nodiscard]] std::optional<ScriptWidgetManifest> extractScriptManifest(const std::filesystem::path& resolvedScript);

  // Same as extractScriptManifest but accepts a raw `script` config value.
  [[nodiscard]] std::optional<ScriptWidgetManifest> manifestForScriptConfig(const std::string& scriptConfigValue);

  // Enumerate the bundled scripts directory and return every script that declares
  // a pickable manifest.
  [[nodiscard]] std::vector<DiscoveredScript> discoverBundledScriptedWidgets();

} // namespace scripting

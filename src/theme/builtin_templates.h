#pragma once

#include <string>
#include <vector>

namespace noctalia::theme {

  struct BuiltinTemplateInfo {
    std::string id;
    std::string name;
    std::string category;
  };

  struct AvailableTemplate {
    std::string id;          // canonical TOML value (what gets written to config)
    std::string displayName; // friendly label for the GUI; falls back to id when not provided
  };

  // Loads the built-in template catalog from the shipped assets/templates/builtin.toml.
  // On parse failure, sets `err` (when non-null) and returns an empty list.
  // Entries are sorted by category, then id.
  [[nodiscard]] std::vector<BuiltinTemplateInfo> loadBuiltinTemplateInfo(std::string* err = nullptr);

  // Every template the user can opt into. Currently the built-in catalog only;
  // when downloaded/external template sources land, this is the place to merge them
  // so callers (e.g. the settings GUI) keep working without changes.
  [[nodiscard]] std::vector<AvailableTemplate> availableTemplates();

} // namespace noctalia::theme

#pragma once

#include "config/schema/diagnostics.h"

#include <string_view>

namespace noctalia::config {

  // Loads and merges the config sources the same way ConfigService::loadAll does
  // (sorted *.toml in configDir, then the state-dir settings.toml overrides) and
  // validates the result against the declarative schema + the widget setting
  // schema. Returns every issue found: syntax errors, unknown sections/keys, and
  // type/enum/range/color problems. Errors mean the config is invalid; warnings
  // are advisory (e.g. clamped ranges). Does not construct a ConfigService and has
  // no side effects.
  [[nodiscard]] schema::Diagnostics
  validateConfigSources(std::string_view configDir, std::string_view settingsTomlPath);

} // namespace noctalia::config

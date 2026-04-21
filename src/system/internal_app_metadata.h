#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace internal_apps {

  struct AppMetadata {
    std::string displayName;
    std::string iconPath;
  };

  struct InternalAppDefinition {
    std::string_view appId;
    std::string_view windowTitle;
    std::string_view displayName;
    std::string_view iconAssetPath;
  };

  [[nodiscard]] const InternalAppDefinition* appDefinitionForAppId(std::string_view appId);
  [[nodiscard]] const InternalAppDefinition* appDefinitionForWindowTitle(std::string_view windowTitle);
  [[nodiscard]] std::optional<AppMetadata> metadataForAppId(std::string_view appId);

} // namespace internal_apps

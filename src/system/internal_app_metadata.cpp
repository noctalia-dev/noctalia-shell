#include "system/internal_app_metadata.h"

#include "core/resource_paths.h"
#include "i18n/i18n.h"

namespace internal_apps {

  namespace {

    constexpr InternalAppDefinition kInternalApps[] = {
        {
            .appId = "dev.noctalia.Noctalia.Settings",
            .windowTitle = "Noctalia Settings",
            .displayName = "Settings",
            .iconAssetPath = "noctalia.svg",
        },
    };

  } // namespace

  const InternalAppDefinition* appDefinitionForAppId(std::string_view appId) {
    for (const auto& app : kInternalApps) {
      if (app.appId == appId) {
        return &app;
      }
    }
    return nullptr;
  }

  const InternalAppDefinition* appDefinitionForWindowTitle(std::string_view windowTitle) {
    for (const auto& app : kInternalApps) {
      if (!app.windowTitle.empty() && app.windowTitle == windowTitle) {
        return &app;
      }
    }
    return nullptr;
  }

  std::optional<AppMetadata> metadataForAppId(std::string_view appId) {
    const auto* app = appDefinitionForAppId(appId);
    if (app == nullptr) {
      return std::nullopt;
    }
    return AppMetadata{
        .displayName = app->appId == std::string_view("dev.noctalia.Noctalia.Settings")
                           ? i18n::tr("internal-apps.settings.display-name")
                           : std::string(app->displayName),
        .iconPath = paths::assetPath(app->iconAssetPath).string(),
    };
  }

} // namespace internal_apps

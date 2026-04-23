#include "theme/template_apply_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/resource_paths.h"
#include "theme/template_engine.h"
#include "util/path_utils.h"

#include <fstream>
#include <string>

namespace noctalia::theme {

  namespace {

    constexpr Logger kLog("theme_templates");

    std::filesystem::path builtinTemplateConfigPath() { return paths::assetPath("templates/builtin.toml"); }

    std::string schemeTypeFromConfig(const ThemeConfig& theme) {
      if (theme.wallpaperScheme.rfind("m3-", 0) == 0)
        return theme.wallpaperScheme.substr(3);
      return theme.wallpaperScheme;
    }

  } // namespace

  TemplateApplyService::TemplateApplyService(const ConfigService& config) : m_config(config) {}

  void TemplateApplyService::apply(const GeneratedPalette& palette, std::string_view defaultMode) const {
    const auto& templateCfg = m_config.config().theme.templates;

    TemplateEngine::Options options;
    options.defaultMode = std::string(defaultMode);
    options.imagePath = m_config.getDefaultWallpaperPath();
    options.schemeType = schemeTypeFromConfig(m_config.config().theme);
    options.verbose = true;

    TemplateEngine engine(TemplateEngine::makeThemeData(palette), options);

    if (templateCfg.enableBuiltins && !templateCfg.builtinIds.empty()) {
      TemplateEngine::Options builtinOptions = options;
      builtinOptions.enabledTemplates.insert(templateCfg.builtinIds.begin(), templateCfg.builtinIds.end());
      TemplateEngine builtinEngine(TemplateEngine::makeThemeData(palette), std::move(builtinOptions));
      const std::filesystem::path builtinConfig = builtinTemplateConfigPath();
      if (!builtinEngine.processConfigFile(builtinConfig)) {
        kLog.warn("failed to apply built-in templates from {}", builtinConfig.string());
      }
    }

    if (!templateCfg.enableUserTemplates)
      return;

    const std::filesystem::path userConfigPath = PathUtils::expandUserPath(templateCfg.userConfig);
    ensureUserConfigStub(userConfigPath);
    if (!std::filesystem::exists(userConfigPath))
      return;
    if (!engine.processConfigFile(userConfigPath)) {
      kLog.warn("failed to apply user templates from {}", userConfigPath.string());
    }
  }

  void TemplateApplyService::ensureUserConfigStub(const std::filesystem::path& path) const {
    std::error_code ec;
    if (std::filesystem::exists(path, ec))
      return;

    if (path.has_parent_path())
      std::filesystem::create_directories(path.parent_path(), ec);
    std::ofstream out(path);
    if (!out)
      return;

    out << "[config]\n\n";
    out << "[templates]\n\n";
    out << "# User-defined templates live here.\n";
    out << "# Example:\n";
    out << "# [templates.my_app]\n";
    out << "# input_path = \"~/.config/noctalia/templates/my-app.css\"\n";
    out << "# output_path = \"~/.config/my-app/theme.css\"\n";
    out << "# post_hook = \"my-app --reload-theme\"\n";
  }

} // namespace noctalia::theme

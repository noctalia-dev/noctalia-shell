#include "theme/template_apply_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/resource_paths.h"
#include "theme/community_templates.h"
#include "theme/template_engine.h"
#include "util/file_utils.h"

#include <fstream>
#include <string>
#include <utility>

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

  TemplateApplyService::TemplateApplyService(const ConfigService& config) : m_config(config) {
    m_worker = std::thread([this]() { workerLoop(); });
  }

  TemplateApplyService::~TemplateApplyService() {
    {
      std::lock_guard lock(m_mutex);
      m_shutdown = true;
      m_pendingRequest.reset();
    }
    m_cv.notify_one();
    if (m_worker.joinable()) {
      m_worker.join();
    }
  }

  void TemplateApplyService::apply(const GeneratedPalette& palette, std::string_view defaultMode) const {
    ApplyRequest request = makeRequest(palette, defaultMode);
    {
      std::lock_guard lock(m_mutex);
      request.generation = ++m_nextGeneration;
      m_pendingRequest = std::move(request);
    }
    m_cv.notify_one();
  }

  TemplateApplyService::ApplyRequest TemplateApplyService::makeRequest(const GeneratedPalette& palette,
                                                                       std::string_view defaultMode) const {
    const ThemeConfig& theme = m_config.config().theme;
    return ApplyRequest{
        .palette = palette,
        .templates = theme.templates,
        .defaultMode = std::string(defaultMode),
        .imagePath = m_config.getDefaultWallpaperPath(),
        .schemeType = schemeTypeFromConfig(theme),
    };
  }

  void TemplateApplyService::applyRequest(const ApplyRequest& request) const {
    TemplateEngine::Options options;
    options.defaultMode = request.defaultMode;
    options.imagePath = request.imagePath;
    options.schemeType = request.schemeType;
    options.verbose = true;
    options.cancelRequested = [this, generation = request.generation]() { return requestSuperseded(generation); };

    TemplateEngine engine(TemplateEngine::makeThemeData(request.palette), options);

    if (request.templates.enableBuiltinTemplates && !request.templates.builtinIds.empty() &&
        !requestSuperseded(request.generation)) {
      TemplateEngine::Options builtinOptions = options;
      builtinOptions.enabledTemplates.insert(request.templates.builtinIds.begin(), request.templates.builtinIds.end());
      TemplateEngine builtinEngine(TemplateEngine::makeThemeData(request.palette), std::move(builtinOptions));
      const std::filesystem::path builtinConfig = builtinTemplateConfigPath();
      if (!builtinEngine.processConfigFile(builtinConfig)) {
        kLog.warn("failed to apply built-in templates from {}", builtinConfig.string());
      }
    }

    if (request.templates.enableCommunityTemplates && !request.templates.communityIds.empty() &&
        !requestSuperseded(request.generation)) {
      for (const auto& id : request.templates.communityIds) {
        if (requestSuperseded(request.generation))
          return;
        if (!isSafeCommunityTemplateId(id)) {
          kLog.warn("skipping unsafe community template id '{}'", id);
          continue;
        }

        const std::filesystem::path communityConfig = communityTemplateConfigPath(id);
        if (!std::filesystem::exists(communityConfig)) {
          kLog.warn("community template '{}' is not cached yet", id);
          continue;
        }
        TemplateEngine communityEngine(TemplateEngine::makeThemeData(request.palette), options);
        if (!communityEngine.processConfigFile(communityConfig)) {
          kLog.warn("failed to apply community template '{}' from {}", id, communityConfig.string());
        }
      }
    }

    if (!request.templates.enableUserTemplates || requestSuperseded(request.generation))
      return;

    const std::filesystem::path userConfigPath = FileUtils::expandUserPath(request.templates.userConfig);
    ensureUserConfigStub(userConfigPath);
    if (!std::filesystem::exists(userConfigPath))
      return;
    if (!engine.processConfigFile(userConfigPath)) {
      kLog.warn("failed to apply user templates from {}", userConfigPath.string());
    }
  }

  void TemplateApplyService::workerLoop() {
    while (true) {
      ApplyRequest request;
      {
        std::unique_lock lock(m_mutex);
        m_cv.wait(lock, [this]() { return m_shutdown || m_pendingRequest.has_value(); });
        if (m_shutdown) {
          return;
        }
        request = std::move(*m_pendingRequest);
        m_pendingRequest.reset();
      }

      applyRequest(request);
    }
  }

  bool TemplateApplyService::requestSuperseded(std::uint64_t generation) const {
    std::lock_guard lock(m_mutex);
    return m_shutdown || generation != m_nextGeneration;
  }

  void TemplateApplyService::ensureUserConfigStub(const std::filesystem::path& path) {
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

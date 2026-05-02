#pragma once

#include "config/config_types.h"
#include "theme/palette.h"

#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>

class ConfigService;

namespace noctalia::theme {

  class TemplateApplyService {
  public:
    explicit TemplateApplyService(const ConfigService& config);
    ~TemplateApplyService();

    TemplateApplyService(const TemplateApplyService&) = delete;
    TemplateApplyService& operator=(const TemplateApplyService&) = delete;

    void apply(const GeneratedPalette& palette, std::string_view defaultMode) const;

  private:
    struct ApplyRequest {
      GeneratedPalette palette;
      ThemeConfig::TemplatesConfig templates;
      std::string defaultMode;
      std::string imagePath;
      std::string schemeType;
      std::uint64_t generation = 0;
    };

    [[nodiscard]] ApplyRequest makeRequest(const GeneratedPalette& palette, std::string_view defaultMode) const;
    void applyRequest(const ApplyRequest& request) const;
    void workerLoop();
    [[nodiscard]] bool requestSuperseded(std::uint64_t generation) const;
    static void ensureUserConfigStub(const std::filesystem::path& path);

    const ConfigService& m_config;
    mutable std::mutex m_mutex;
    mutable std::condition_variable m_cv;
    mutable std::optional<ApplyRequest> m_pendingRequest;
    mutable std::thread m_worker;
    mutable std::uint64_t m_nextGeneration = 0;
    mutable bool m_shutdown = false;
  };

} // namespace noctalia::theme

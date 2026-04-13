#pragma once

#include "theme/palette.h"

#include <filesystem>
#include <string_view>

class ConfigService;

namespace noctalia::theme {

  class TemplateApplyService {
  public:
    explicit TemplateApplyService(const ConfigService& config);

    void apply(const GeneratedPalette& palette, std::string_view defaultMode) const;

  private:
    void ensureUserConfigStub(const std::filesystem::path& path) const;

    const ConfigService& m_config;
  };

} // namespace noctalia::theme

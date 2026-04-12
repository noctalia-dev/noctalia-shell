#pragma once

#include "theme/palette.h"

#include <filesystem>
#include <string_view>

class ConfigService;
class StateService;

namespace noctalia::theme {

  class TemplateApplyService {
  public:
    TemplateApplyService(const ConfigService& config, const StateService& state);

    void apply(const GeneratedPalette& palette, std::string_view defaultMode) const;

  private:
    void ensureUserConfigStub(const std::filesystem::path& path) const;

    const ConfigService& m_config;
    const StateService& m_state;
  };

} // namespace noctalia::theme

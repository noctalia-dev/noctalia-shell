#pragma once

#include "config/config_types.h"
#include "render/core/render_styles.h"

namespace shell::panel_effects {

  void apply(RoundedRectStyle& style, const ShellConfig::PanelConfig::EffectsConfig& effects);

} // namespace shell::panel_effects

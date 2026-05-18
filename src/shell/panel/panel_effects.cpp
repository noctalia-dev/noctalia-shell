#include "shell/panel/panel_effects.h"

#include <algorithm>

namespace shell::panel_effects {

  void apply(RoundedRectStyle& style, const ShellConfig::PanelConfig::EffectsConfig& effects) {
    style.materialTextureStyle = static_cast<int>(effects.texture);
    style.materialTextureOpacity =
        effects.texture == PanelTextureStyle::Disabled ? 0.0f : std::clamp(effects.textureOpacity, 0.0f, 1.0f);
    style.materialHighlightStyle = static_cast<int>(effects.highlight);
    style.materialHighlightOpacity = effects.highlight == PanelHighlightStyle::Disabled
                                         ? 0.0f
                                         : std::clamp(effects.highlightOpacity, 0.0f, 1.0f) * 0.5f;
  }

} // namespace shell::panel_effects

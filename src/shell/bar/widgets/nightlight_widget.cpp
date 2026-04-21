#include "shell/bar/widgets/nightlight_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "system/night_light_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

namespace {

  const char* glyphForState(bool enabled, bool forced) {
    if (forced) {
      return "nightlight-forced";
    }
    return enabled ? "nightlight-on" : "nightlight-off";
  }

} // namespace

NightLightWidget::NightLightWidget(NightLightManager* nightLight) : m_nightLight(nightLight) {}

void NightLightWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    if (m_nightLight == nullptr) {
      return;
    }
    if (m_nightLight->forceEnabled()) {
      // forced → off
      m_nightLight->setEnabled(false);
      m_nightLight->clearForceOverride();
    } else if (m_nightLight->enabled()) {
      // on → forced
      m_nightLight->setForceEnabled(true);
    } else {
      // off → on
      m_nightLight->setEnabled(true);
    }
  });
  m_area = area.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("nightlight-off");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void NightLightWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_glyph == nullptr) {
    return;
  }

  syncState(renderer);
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->measure(renderer);

  if (auto* node = root(); node != nullptr) {
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

void NightLightWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void NightLightWidget::syncState(Renderer& renderer) {
  if (m_glyph == nullptr || m_area == nullptr) {
    return;
  }

  const bool enabled = m_nightLight != nullptr && m_nightLight->enabled();
  const bool active = m_nightLight != nullptr && m_nightLight->active();
  const bool forced = m_nightLight != nullptr && m_nightLight->forceEnabled();

  if (enabled == m_lastEnabled && active == m_lastActive && forced == m_lastForced) {
    return;
  }

  m_lastEnabled = enabled;
  m_lastActive = active;
  m_lastForced = forced;

  m_glyph->setGlyph(glyphForState(enabled, forced));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);

  if (forced || (enabled && active)) {
    m_glyph->setColor(roleColor(ColorRole::Primary));
  } else if (enabled) {
    m_glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  } else {
    m_glyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
  }

  m_glyph->measure(renderer);
  if (auto* node = root(); node != nullptr) {
    node->setOpacity(enabled || forced ? 1.0f : 0.55f);
  }
  requestRedraw();
}

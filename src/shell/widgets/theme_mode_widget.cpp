#include "shell/widgets/theme_mode_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "theme/theme_service.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

namespace {

const char* glyphForMode(bool isLight) { return isLight ? "weather-sun" : "weather-moon"; }

} // namespace

ThemeModeWidget::ThemeModeWidget(noctalia::theme::ThemeService* themeService) : m_themeService(themeService) {}

void ThemeModeWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    if (m_themeService == nullptr) {
      return;
    }
    m_themeService->toggleLightDark();
    m_lastIsLight = !m_lastIsLight;
    if (m_glyph != nullptr) {
      m_glyph->setGlyph(glyphForMode(m_lastIsLight));
      m_glyph->setColor(roleColor(m_lastIsLight ? ColorRole::Primary : ColorRole::OnSurface));
    }
    requestRedraw();
  });
  m_area = area.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("weather-moon");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(roleColor(ColorRole::OnSurface));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void ThemeModeWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
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

void ThemeModeWidget::doUpdate(Renderer& renderer) {
  syncState(renderer);
}

void ThemeModeWidget::syncState(Renderer& renderer) {
  if (m_themeService == nullptr || m_glyph == nullptr || m_area == nullptr) {
    return;
  }

  const bool isLight = m_themeService->isLightMode();
  if (isLight == m_lastIsLight) {
    return;
  }

  m_lastIsLight = isLight;
  m_glyph->setGlyph(glyphForMode(isLight));
  m_glyph->setColor(roleColor(isLight ? ColorRole::Primary : ColorRole::OnSurface));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->measure(renderer);

  if (auto* node = root(); node != nullptr) {
    node->setOpacity(isLight ? 1.0f : 0.85f);
  }
  requestRedraw();
}

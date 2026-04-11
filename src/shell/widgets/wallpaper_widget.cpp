#include "shell/widgets/wallpaper_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

WallpaperWidget::WallpaperWidget(wl_output* output) : m_output(output) {}

void WallpaperWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("wallpaper", m_output, 0.0f, 0.0f);
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("wallpaper-selector");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.onSurface);
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void WallpaperWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_glyph == nullptr) {
    return;
  }
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->measure(renderer);
  if (auto* node = root(); node != nullptr) {
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

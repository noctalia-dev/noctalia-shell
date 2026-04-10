#include "shell/widgets/launcher_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

LauncherWidget::LauncherWidget(wl_output* output, std::int32_t scale) : m_output(output), m_scale(scale) {}

void LauncherWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    PanelManager::instance().togglePanel("launcher", m_output, m_scale, absX, absY);
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("search");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.onSurface);
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void LauncherWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_glyph == nullptr) {
    return;
  }
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->measure(renderer);
  auto* node = root();
  if (node != nullptr) {
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

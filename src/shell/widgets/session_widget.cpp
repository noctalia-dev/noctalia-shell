#include "shell/widgets/session_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

SessionWidget::SessionWidget(wl_output* output, std::int32_t scale) : m_output(output), m_scale(scale) {}

void SessionWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    PanelManager::instance().togglePanel("session-menu", m_output, m_scale, absX, absY);
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("shutdown");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.onSurface);
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  m_root = std::move(area);
}

void SessionWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
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

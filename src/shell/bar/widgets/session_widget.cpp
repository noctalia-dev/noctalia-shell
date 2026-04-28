#include "shell/bar/widgets/session_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

SessionWidget::SessionWidget(wl_output* output, std::string barGlyphId)
    : m_output(output), m_barGlyphId(std::move(barGlyphId)) {}

void SessionWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("session", m_output, 0.0f, 0.0f);
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph(m_barGlyphId.empty() ? "shutdown" : m_barGlyphId);
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void SessionWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_glyph == nullptr) {
    return;
  }
  m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  m_glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph->measure(renderer);
  auto* node = root();
  if (node != nullptr) {
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

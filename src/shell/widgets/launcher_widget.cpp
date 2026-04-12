#include "shell/widgets/launcher_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

LauncherWidget::LauncherWidget(wl_output* output) : m_output(output) {}

void LauncherWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("launcher", m_output, 0.0f, 0.0f);
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("search");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(roleColor(ColorRole::OnSurface));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void LauncherWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
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

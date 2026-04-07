#include "shell/widgets/launcher_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/icon.h"
#include "ui/palette.h"

#include <memory>

LauncherWidget::LauncherWidget(wl_output* output, std::int32_t scale) : m_output(output), m_scale(scale) {}

void LauncherWidget::create(Renderer& renderer) {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("launcher");
  });

  auto icon = std::make_unique<Icon>();
  icon->setIcon("search");
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  area->addChild(std::move(icon));

  m_icon->measure(renderer);
  area->setSize(m_icon->width(), m_icon->height());

  m_root = std::move(area);
}

void LauncherWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_icon == nullptr) {
    return;
  }
  m_icon->measure(renderer);
  auto* node = root();
  if (node != nullptr) {
    node->setSize(m_icon->width(), m_icon->height());
  }
}

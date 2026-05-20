#ifndef NDEBUG

#include "shell/bar/widgets/debug_indicator_widget.h"

#include "ui/controls/chip.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

DebugIndicatorWidget::DebugIndicatorWidget() = default;

void DebugIndicatorWidget::create() {
  auto chip = std::make_unique<Chip>();

  chip->setFill(colorSpecFromRole(ColorRole::Error));
  chip->label()->setColor(colorSpecFromRole(ColorRole::OnError));
  chip->label()->setBold(true);
  chip->setText("DEBUG");
  chip->clearBorder();
  chip->setPadding(2.0f, Style::spaceSm);

  m_chip = chip.get();
  setRoot(std::move(chip));
}

void DebugIndicatorWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  const LayoutConstraints unconstrained{};
  const auto size = m_chip->measure(renderer, unconstrained);
  m_chip->setRadius(std::min(size.width, size.height) * 0.5f);
  root()->setSize(size.width, size.height);
}

#endif

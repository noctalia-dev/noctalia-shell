#include "debug_indicator_widget.h"
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

  // Override Chip's default active/inactive styling with a red pill
  chip->setFill(colorSpecFromRole(ColorRole::Error));
  chip->label()->setColor(colorSpecFromRole(ColorRole::OnError));
  chip->label()->setBold(true);
  chip->setText("DEBUG");
  chip->clearBorder();
  chip->setRadius(999.0f);
  chip->setPadding(2.0f, Style::spaceSm);

  m_chip = chip.get();
  setRoot(std::move(chip));
}

void DebugIndicatorWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_chip == nullptr) {
    return;
  }
  const LayoutConstraints unconstrained{};
  auto* node = root();
  if (node != nullptr) {
    const auto size = m_chip->measure(renderer, unconstrained);
    node->setSize(size.width, size.height);
  }
}

#endif

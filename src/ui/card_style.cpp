#include "ui/card_style.h"

#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"

namespace ui {

  void applyCardStyle(Box& box, float scale) {
    box.setFill(roleColor(ColorRole::SurfaceVariant));
    box.setBorder(roleColor(ColorRole::Outline, 0.5f), Style::borderWidth);
    box.setRadius(Style::radiusXl * scale);
    box.setSoftness(1.0f);
  }

  void applyCardStyle(Flex& flex, float scale) {
    flex.setFill(roleColor(ColorRole::SurfaceVariant));
    flex.setBorder(roleColor(ColorRole::Outline, 0.5f), Style::borderWidth);
    flex.setRadius(Style::radiusXl * scale);
    flex.setSoftness(1.0f);
    flex.setPadding(Style::spaceMd * scale);
  }

  void applyCardStyle(ScrollView& scrollView, float scale) {
    scrollView.setFill(roleColor(ColorRole::SurfaceVariant));
    scrollView.setBorder(roleColor(ColorRole::Outline, 0.5f), Style::borderWidth);
    scrollView.setRadius(Style::radiusXl * scale);
    scrollView.setSoftness(1.0f);
    scrollView.setViewportPaddingH(Style::spaceMd * scale);
    scrollView.setViewportPaddingV(Style::spaceMd * scale);
  }

} // namespace ui

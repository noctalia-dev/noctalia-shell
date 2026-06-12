#include "shell/bar/widgets/launcher_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/builders.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

LauncherWidget::LauncherWidget(
    wl_output* /*output*/, std::string barGlyphId, std::string logoPath, bool customImageColorize
)
    : m_barGlyphId(std::move(barGlyphId)), m_logoPath(std::move(logoPath)), m_customImageColorize(customImageColorize) {
}

void LauncherWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) { requestPanelToggle("launcher"); });

  if (!m_logoPath.empty()) {
    area->addChild(
        ui::image({
            .out = &m_image,
            .fit = ImageFit::Contain,
        })
    );
  } else {
    area->addChild(
        ui::glyph({
            .out = &m_glyph,
            .glyph = m_barGlyphId.empty() ? "video" : m_barGlyphId,
            .glyphSize = Style::baseGlyphSize * m_contentScale,
            .color = widgetIconColorOr(colorSpecFromRole(ColorRole::OnSurface)),
        })
    );
  }

  setRoot(std::move(area));
}

void LauncherWidget::refreshCustomImageTint() {
  if (m_image == nullptr) {
    return;
  }
  if (m_customImageColorize) {
    m_image->setForegroundTint(widgetIconColorOr(colorSpecFromRole(ColorRole::OnSurface)));
  } else {
    m_image->setForegroundTint(std::nullopt);
  }
}

void LauncherWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* node = root();
  if (node == nullptr) {
    return;
  }

  if (m_image != nullptr) {
    refreshCustomImageTint();
    m_image->setSize(Style::baseGlyphSize * m_contentScale, Style::baseGlyphSize * m_contentScale);
    const int logoTargetSize = std::max(1, static_cast<int>(48.0f * m_contentScale));
    m_image->setSourceFile(renderer, m_logoPath, logoTargetSize, true);
    node->setSize(m_image->width(), m_image->height());
  } else if (m_glyph != nullptr) {
    m_glyph->setGlyphSize(Style::baseGlyphSize * m_contentScale);
    m_glyph->setColor(widgetIconColorOr(colorSpecFromRole(ColorRole::OnSurface)));
    m_glyph->measure(renderer);
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

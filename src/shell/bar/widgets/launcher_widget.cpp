#include "shell/bar/widgets/launcher_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

LauncherWidget::LauncherWidget(wl_output* output, std::string barGlyphId, std::string logoPath)
    : m_output(output), m_barGlyphId(std::move(barGlyphId)), m_logoPath(std::move(logoPath)) {}

void LauncherWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) { requestPanelToggle("launcher"); });

  if (!m_logoPath.empty()) {
    auto image = std::make_unique<Image>();
    image->setFit(ImageFit::Contain);
    m_image = image.get();
    area->addChild(std::move(image));
  } else {
    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph(m_barGlyphId.empty() ? "video" : m_barGlyphId);
    glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
    glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
    m_glyph = glyph.get();
    area->addChild(std::move(glyph));
  }

  setRoot(std::move(area));
}

void LauncherWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* node = root();
  if (node == nullptr) {
    return;
  }

  if (m_image != nullptr) {
    m_image->setSize(Style::barIconSize * m_contentScale, Style::barIconSize * m_contentScale);
    const int logoTargetSize = std::max(1, static_cast<int>(48.0f * m_contentScale));
    m_image->setSourceFile(renderer, m_logoPath, logoTargetSize, true);
    node->setSize(m_image->width(), m_image->height());
  } else if (m_glyph != nullptr) {
    m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
    m_glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
    m_glyph->measure(renderer);
    node->setSize(m_glyph->width(), m_glyph->height());
  }
}

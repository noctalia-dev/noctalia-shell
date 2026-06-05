#include "shell/desktop/widgets/desktop_login_box_widget.h"

#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "shell/lockscreen/lockscreen_login_box.h"
#include "ui/builders.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

namespace {

  constexpr float kLoginGlyphSize = 16.0f;

} // namespace

void DesktopLoginBoxWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto panel = ui::box({});
  m_panel = panel.get();
  rootNode->addChild(std::move(panel));

  auto passwordGhost = ui::box({
      .fill = colorSpecFromRole(ColorRole::Surface, 0.65f),
  });
  m_passwordGhost = passwordGhost.get();
  rootNode->addChild(std::move(passwordGhost));

  auto loginButtonGhost = ui::box({
      .fill = colorSpecFromRole(ColorRole::Primary, 0.9f),
  });
  m_loginButtonGhost = loginButtonGhost.get();
  rootNode->addChild(std::move(loginButtonGhost));

  auto loginGlyph = ui::glyph({
      .out = &m_loginGlyph,
      .glyph = "check",
      .glyphSize = kLoginGlyphSize,
      .color = colorSpecFromRole(ColorRole::OnPrimary),
  });
  rootNode->addChild(std::move(loginGlyph));

  setRoot(std::move(rootNode));
}

void DesktopLoginBoxWidget::doLayout(Renderer& renderer) {
  const float screenWidth = m_screenWidth > 0.0f ? m_screenWidth : 1920.0f;
  const float panelWidth = lockscreen_login_box::panelWidth(screenWidth);
  const float panelHeight = lockscreen_login_box::panelHeight();
  const float contentLeft = Style::spaceLg;
  const float contentTop = 22.0f;
  const float rightInset = Style::spaceLg + Style::spaceSm;
  const float contentWidth = panelWidth - Style::spaceLg - rightInset;
  const float buttonWidth = Style::controlHeight;
  const float gap = Style::spaceSm;
  const float inputWidth = std::max(120.0f, contentWidth - buttonWidth - gap);
  const float buttonX = contentLeft + inputWidth + gap;

  if (m_panel != nullptr) {
    m_panel->setPosition(0.0f, 0.0f);
    m_panel->setSize(panelWidth, panelHeight);
    m_panel->setStyle(
        RoundedRectStyle{
            .fill = colorForRole(ColorRole::SurfaceVariant, 0.88f),
            .border = colorForRole(ColorRole::Outline, 0.95f),
            .fillMode = FillMode::Solid,
            .radius = Style::scaledRadiusXl(),
            .softness = 1.0f,
            .borderWidth = Style::borderWidth,
        }
    );
  }

  if (m_passwordGhost != nullptr) {
    m_passwordGhost->setPosition(contentLeft, contentTop);
    m_passwordGhost->setSize(inputWidth, Style::controlHeight);
    m_passwordGhost->setStyle(
        RoundedRectStyle{
            .fill = colorForRole(ColorRole::Surface, 0.65f),
            .border = colorForRole(ColorRole::Outline, 0.85f),
            .fillMode = FillMode::Solid,
            .radius = Style::scaledRadiusMd(),
            .borderWidth = Style::borderWidth,
        }
    );
  }

  if (m_loginButtonGhost != nullptr) {
    m_loginButtonGhost->setPosition(buttonX, contentTop);
    m_loginButtonGhost->setSize(buttonWidth, Style::controlHeight);
    m_loginButtonGhost->setStyle(
        RoundedRectStyle{
            .fill = colorForRole(ColorRole::Primary, 0.9f),
            .fillMode = FillMode::Solid,
            .radius = Style::scaledRadiusMd(),
        }
    );
  }

  if (m_loginGlyph != nullptr) {
    m_loginGlyph->setPosition(
        buttonX + (buttonWidth - kLoginGlyphSize) * 0.5f, contentTop + (Style::controlHeight - kLoginGlyphSize) * 0.5f
    );
    m_loginGlyph->measure(renderer);
  }

  if (Node* rootNode = root()) {
    rootNode->setSize(panelWidth, panelHeight);
  }
}

#include "shell/widgets/network_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

namespace {

  const char* glyphForState(const NetworkState& s) {
    if (s.kind == NetworkConnectivity::Wired) {
      return s.connected ? "ethernet" : "ethernet-off";
    }
    if (s.kind != NetworkConnectivity::Wireless || !s.connected) {
      return "wifi-off";
    }
    if (s.signalStrength >= 67) {
      return "wifi-2";
    }
    if (s.signalStrength >= 34) {
      return "wifi-1";
    }
    return "wifi-0";
  }

  std::string labelForState(const NetworkState& s) {
    if (s.kind == NetworkConnectivity::Wireless && s.connected && !s.ssid.empty()) {
      return s.ssid;
    }
    if (s.kind == NetworkConnectivity::Wired && s.connected) {
      return s.interfaceName.empty() ? std::string("Wired") : s.interfaceName;
    }
    return {};
  }

} // namespace

NetworkWidget::NetworkWidget(NetworkService* network, wl_output* output, bool showLabel)
    : m_network(network), m_output(output), m_showLabel(showLabel) {}

void NetworkWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("control-center", m_output, 0.0f, 0.0f, "network");
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("wifi-off");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  // Always create the label node: horizontal bars honor m_showLabel, but
  // vertical bars always display a 3-char truncation under the glyph to match
  // volume/brightness.
  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setBold(true);
  label->setStableBaseline(true);
  m_label = label.get();
  area->addChild(std::move(label));

  setRoot(std::move(area));
}

void NetworkWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (m_glyph == nullptr || rootNode == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;
  syncState(renderer);

  m_glyph->measure(renderer);
  if (m_label != nullptr) {
    m_label->measure(renderer);
  }

  const bool labelVisible = m_label != nullptr && m_label->width() > 0.0f && m_label->visible();
  if (m_isVertical && labelVisible) {
    const float w = std::max(m_glyph->width(), m_label->width());
    m_glyph->setPosition(std::round((w - m_glyph->width()) * 0.5f), 0.0f);
    m_label->setPosition(std::round((w - m_label->width()) * 0.5f), m_glyph->height());
    rootNode->setSize(w, m_glyph->height() + m_label->height());
  } else {
    m_glyph->setPosition(0.0f, 0.0f);
    float totalWidth = m_glyph->width();
    if (labelVisible) {
      m_label->setPosition(m_glyph->width() + Style::spaceXs, 0.0f);
      totalWidth = m_label->x() + m_label->width();
    }
    rootNode->setSize(totalWidth, m_glyph->height());
  }
}

void NetworkWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void NetworkWidget::syncState(Renderer& renderer) {
  if (m_glyph == nullptr || m_network == nullptr) {
    return;
  }

  const NetworkState& s = m_network->state();
  if (m_haveLastState && s == m_lastState && m_isVertical == m_lastVertical) {
    return;
  }
  m_lastState = s;
  m_haveLastState = true;
  m_lastVertical = m_isVertical;

  m_glyph->setGlyph(glyphForState(s));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->setColor(s.connected ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                                : roleColor(ColorRole::OnSurfaceVariant));
  m_glyph->measure(renderer);

  if (m_label != nullptr) {
    const bool showLabel = m_showLabel;
    m_label->setVisible(showLabel);
    if (showLabel) {
      std::string text = labelForState(s);
      if (m_isVertical && text.size() > 3) {
        text = text.substr(0, 3);
      }
      m_label->setFontSize((m_isVertical ? Style::fontSizeCaption : Style::fontSizeBody) * m_contentScale);
      m_label->setText(text);
      m_label->setColor(s.connected ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                                    : roleColor(ColorRole::OnSurfaceVariant));
      m_label->measure(renderer);
    }
  }

  if (auto* rootNode = root(); rootNode != nullptr) {
    rootNode->setOpacity(s.connected ? 1.0f : 0.55f);
  }

  requestRedraw();
}

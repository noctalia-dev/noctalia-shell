#include "shell/bar/widgets/bluetooth_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

  const char* glyphForState(const BluetoothState& s, int connectedCount) {
    if (!s.adapterPresent || !s.powered) {
      return "bluetooth-off";
    }
    if (connectedCount > 0) {
      return "bluetooth-connected";
    }
    return "bluetooth";
  }

  std::string firstConnectedAlias(const std::vector<BluetoothDeviceInfo>& devices) {
    for (const auto& d : devices) {
      if (d.connected) {
        return d.alias;
      }
    }
    return {};
  }

  int connectedCount(const std::vector<BluetoothDeviceInfo>& devices) {
    int count = 0;
    for (const auto& d : devices) {
      if (d.connected) {
        ++count;
      }
    }
    return count;
  }

} // namespace

BluetoothWidget::BluetoothWidget(BluetoothService* bluetooth, wl_output* output, bool showLabel)
    : m_bluetooth(bluetooth), m_output(output), m_showLabel(showLabel) {}

void BluetoothWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick(
      [this](const InputArea::PointerData& /*data*/) { requestPanelToggle("control-center", "bluetooth"); });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("bluetooth");
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  if (m_showLabel) {
    auto label = std::make_unique<Label>();
    label->setFontSize(Style::fontSizeBody * m_contentScale);
    label->setStableBaseline(true);
    m_label = label.get();
    area->addChild(std::move(label));
  }

  setRoot(std::move(area));
}

void BluetoothWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || rootNode == nullptr) {
    return;
  }
  syncState(renderer);

  m_glyph->measure(renderer);

  float totalWidth = m_glyph->width();
  float contentHeight = m_glyph->height();
  if (m_label != nullptr) {
    m_label->measure(renderer);
    if (m_label->width() > 0.0f) {
      contentHeight = std::max(contentHeight, m_label->height());
      m_label->setPosition(m_glyph->width() + Style::spaceXs, std::round((contentHeight - m_label->height()) * 0.5f));
      totalWidth = m_label->x() + m_label->width();
    }
  }
  m_glyph->setPosition(0.0f, std::round((contentHeight - m_glyph->height()) * 0.5f));
  rootNode->setSize(totalWidth, contentHeight);
}

void BluetoothWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void BluetoothWidget::syncState(Renderer& renderer) {
  if (m_glyph == nullptr || m_bluetooth == nullptr) {
    return;
  }

  const auto& s = m_bluetooth->state();
  const auto& devices = m_bluetooth->devices();
  const int numConnected = connectedCount(devices);
  const std::string alias = m_showLabel ? firstConnectedAlias(devices) : std::string{};

  if (m_haveLastState && s == m_lastState && numConnected == m_lastConnectedCount && alias == m_lastConnectedAlias) {
    return;
  }
  m_lastState = s;
  m_haveLastState = true;
  m_lastConnectedCount = numConnected;
  m_lastConnectedAlias = alias;

  auto* rootNode = root();

  if (!s.adapterPresent) {
    if (rootNode != nullptr) {
      rootNode->setVisible(false);
      rootNode->setSize(0.0f, 0.0f);
    }
    return;
  }

  if (rootNode != nullptr) {
    rootNode->setVisible(true);
    rootNode->setOpacity(s.powered ? 1.0f : 0.55f);
  }

  m_glyph->setGlyph(glyphForState(s, numConnected));
  m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  m_glyph->setColor(s.powered ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                              : roleColor(ColorRole::OnSurfaceVariant));
  m_glyph->measure(renderer);

  if (m_label != nullptr) {
    m_label->setText(alias);
    m_label->setColor(s.powered ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                                : roleColor(ColorRole::OnSurfaceVariant));
    m_label->measure(renderer);
  }

  requestRedraw();
}

#include "shell/tray/tray_drawer_panel.h"

#include "shell/bar/widgets/tray_widget.h"
#include "shell/panel/panel_manager.h"

#include <algorithm>
#include <cctype>

TrayDrawerPanel::TrayDrawerPanel(TrayService* tray, std::vector<std::string> hiddenItems, std::size_t drawerColumns)
    : m_tray(tray), m_hiddenItems(std::move(hiddenItems)),
      m_drawerColumns(std::clamp<std::size_t>(drawerColumns, 1U, 5U)) {}

TrayDrawerPanel::~TrayDrawerPanel() = default;

float TrayDrawerPanel::preferredWidth() const {
  const float itemSize = scaled(Style::barGlyphSize);
  const float gap = scaled(Style::spaceXs);
  const std::size_t cols = std::min<std::size_t>(m_drawerColumns, std::max<std::size_t>(1, visibleItemCount()));
  const float contentWidth = static_cast<float>(cols) * itemSize + static_cast<float>(cols > 1 ? cols - 1 : 0) * gap;
  const float panelPadding = scaled(Style::panelPadding) * 2.0f;
  return contentWidth + panelPadding;
}

float TrayDrawerPanel::preferredHeight() const {
  const float itemSize = scaled(Style::barGlyphSize);
  const float gap = scaled(Style::spaceXs);
  const std::size_t count = std::max<std::size_t>(1, visibleItemCount());
  const std::size_t rows = (count + m_drawerColumns - 1U) / m_drawerColumns;
  const float contentHeight = static_cast<float>(rows) * itemSize + static_cast<float>(rows > 1 ? rows - 1 : 0) * gap;
  const float panelPadding = scaled(Style::panelPadding) * 2.0f;
  return contentHeight + panelPadding;
}

void TrayDrawerPanel::create() {
  m_drawerWidget = std::make_unique<TrayWidget>(
      m_tray, m_hiddenItems, false, []() { PanelManager::instance().close(); }, "top", true, m_drawerColumns);
  m_drawerWidget->setContentScale(contentScale());
  m_drawerWidget->create();
  setRoot(m_drawerWidget->releaseRoot());
}

void TrayDrawerPanel::onClose() {
  m_drawerWidget.reset();
  clearReleasedRoot();
}

void TrayDrawerPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_drawerWidget == nullptr || m_drawerWidget->root() == nullptr) {
    return;
  }
  m_drawerWidget->layout(renderer, width, height);
}

void TrayDrawerPanel::doUpdate(Renderer& renderer) {
  if (m_drawerWidget == nullptr || m_drawerWidget->root() == nullptr) {
    return;
  }
  m_drawerWidget->update(renderer);
}

std::size_t TrayDrawerPanel::visibleItemCount() const {
  if (m_tray == nullptr) {
    return 0;
  }
  auto toLower = [](std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
  };
  std::vector<std::string> hiddenLower;
  hiddenLower.reserve(m_hiddenItems.size());
  for (const auto& v : m_hiddenItems) {
    hiddenLower.push_back(toLower(v));
  }
  std::size_t visible = 0;
  for (const auto& item : m_tray->items()) {
    const std::string id = toLower(item.id);
    const std::string bus = toLower(item.busName);
    const bool hidden = std::ranges::find(hiddenLower, id) != hiddenLower.end() ||
                        std::ranges::find(hiddenLower, bus) != hiddenLower.end();
    if (!hidden) {
      ++visible;
    }
  }
  return visible;
}

#include "shell/widgets/active_window_widget.h"

#include "system/desktop_entry.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <string_view>

namespace {

std::string toLower(std::string_view value) {
  std::string out(value);
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return out;
}

std::string fitTextToWidth(Renderer& renderer, const std::string& text, float fontSize, bool bold, float maxWidth) {
  if (text.empty() || maxWidth <= 0.0f) {
    return {};
  }

  if (renderer.measureText(text, fontSize, bold).width <= maxWidth) {
    return text;
  }

  static constexpr const char* kEllipsis = "...";
  const float ellipsisWidth = renderer.measureText(kEllipsis, fontSize, bold).width;
  if (ellipsisWidth >= maxWidth) {
    return {};
  }

  std::size_t lo = 0;
  std::size_t hi = text.size();
  std::size_t best = 0;
  while (lo <= hi) {
    const std::size_t mid = lo + ((hi - lo) / 2);
    std::string candidate = text.substr(0, mid) + kEllipsis;
    if (renderer.measureText(candidate, fontSize, bold).width <= maxWidth) {
      best = mid;
      lo = mid + 1;
    } else {
      if (mid == 0) {
        break;
      }
      hi = mid - 1;
    }
  }

  return text.substr(0, best) + kEllipsis;
}

} // namespace

ActiveWindowWidget::ActiveWindowWidget(WaylandConnection& connection, float maxTitleWidth, float iconSize)
    : m_connection(connection), m_maxTitleWidth(maxTitleWidth), m_iconSize(iconSize) {
  buildDesktopIconIndex();
}

void ActiveWindowWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto icon = std::make_unique<Image>();
  icon->setCornerRadius(Style::radiusSm);
  icon->setBackground(Color{palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.75f});
  icon->setFit(ImageFit::Contain);
  icon->setSize(m_iconSize * m_contentScale, m_iconSize * m_contentScale);
  m_icon = static_cast<Image*>(rootNode->addChild(std::move(icon)));

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody * m_contentScale);
  title->setColor(palette.onSurface);
  title->setMaxWidth(m_maxTitleWidth * m_contentScale);
  m_title = static_cast<Label*>(rootNode->addChild(std::move(title)));

  m_root = std::move(rootNode);
}

void ActiveWindowWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (rootNode == nullptr || m_icon == nullptr || m_title == nullptr) {
    return;
  }
  syncState(renderer);

  const float iconSize = m_iconSize * m_contentScale;
  m_icon->setSize(iconSize, iconSize);
  m_title->setMaxWidth(m_maxTitleWidth * m_contentScale);
  m_title->measure(renderer);

  const float contentHeight = std::max(iconSize, m_title->height());
  const float iconY = std::round((contentHeight - iconSize) * 0.5f);
  const float labelY = std::round((contentHeight - m_title->height()) * 0.5f);

  m_icon->setPosition(0.0f, iconY);
  m_title->setPosition(iconSize + Style::spaceXs, labelY);

  rootNode->setSize(m_title->x() + m_title->width(), contentHeight);
}

void ActiveWindowWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void ActiveWindowWidget::syncState(Renderer& renderer) {
  if (m_icon == nullptr || m_title == nullptr) {
    return;
  }

  const auto desktopVersion = desktopEntriesVersion();
  const bool desktopEntriesChanged = desktopVersion != m_desktopEntriesVersion;
  if (desktopEntriesChanged) {
    buildDesktopIconIndex();
  }

  const auto current = m_connection.activeToplevel();

  std::string identifier;
  std::string title;
  std::string appId;

  if (current.has_value()) {
    identifier = current->identifier;
    title = current->title;
    appId = current->appId;
  }

  if (title.empty()) {
    title = !appId.empty() ? appId : "Desktop";
  }

  if (!desktopEntriesChanged && identifier == m_lastIdentifier && title == m_lastTitle && appId == m_lastAppId) {
    return;
  }

  m_lastIdentifier = std::move(identifier);
  m_lastTitle = title;
  m_lastAppId = appId;

  std::string iconPath = resolveIconPath(appId);
  if (iconPath.empty()) {
    iconPath = m_iconResolver.resolve("application-x-executable");
  }

  const float titleMaxWidth = m_maxTitleWidth * m_contentScale;
  m_title->setText(fitTextToWidth(renderer, m_lastTitle, Style::fontSizeBody * m_contentScale, true, titleMaxWidth));
  m_title->measure(renderer);

  if (iconPath != m_lastIconPath) {
    m_lastIconPath = iconPath;
    if (!m_lastIconPath.empty()) {
      m_icon->setSourceFile(renderer, m_lastIconPath, static_cast<int>(std::round(48.0f * m_contentScale)));
    } else {
      m_icon->clear(renderer);
    }
  }

  requestRedraw();
}

std::string ActiveWindowWidget::resolveIconPath(const std::string& appId) {
  if (appId.empty()) {
    return {};
  }

  auto resolveByName = [this](const std::string& name) -> std::string {
    if (name.empty()) {
      return {};
    }
    return m_iconResolver.resolve(name);
  };

  if (auto it = m_appIcons.find(appId); it != m_appIcons.end()) {
    const auto path = resolveByName(it->second);
    if (!path.empty()) {
      return path;
    }
  }

  const std::string appIdLower = toLower(appId);
  if (auto it = m_appIcons.find(appIdLower); it != m_appIcons.end()) {
    const auto path = resolveByName(it->second);
    if (!path.empty()) {
      return path;
    }
  }

  if (const auto slash = appId.find_last_of('/'); slash != std::string::npos && slash + 1 < appId.size()) {
    const std::string tail = appId.substr(slash + 1);
    if (auto it = m_appIcons.find(tail); it != m_appIcons.end()) {
      const auto path = resolveByName(it->second);
      if (!path.empty()) {
        return path;
      }
    }
  }

  return resolveByName(appId);
}

void ActiveWindowWidget::buildDesktopIconIndex() {
  m_appIcons.clear();
  const auto& entries = desktopEntries();
  for (const auto& entry : entries) {
    if (entry.id.empty() || entry.icon.empty()) {
      continue;
    }
    m_appIcons.try_emplace(entry.id, entry.icon);
    m_appIcons.try_emplace(toLower(entry.id), entry.icon);
    if (const auto dot = entry.id.rfind('.'); dot != std::string::npos && dot + 1 < entry.id.size()) {
      m_appIcons.try_emplace(entry.id.substr(dot + 1), entry.icon);
      m_appIcons.try_emplace(toLower(entry.id.substr(dot + 1)), entry.icon);
    }
  }
  m_desktopEntriesVersion = desktopEntriesVersion();
}

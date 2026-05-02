#include "shell/bar/widgets/active_window_widget.h"

#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "system/desktop_entry.h"
#include "system/internal_app_metadata.h"
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

} // namespace

ActiveWindowWidget::ActiveWindowWidget(WaylandConnection& connection, float maxTitleWidth, float iconSize)
    : m_connection(connection), m_maxTitleWidth(maxTitleWidth), m_iconSize(iconSize) {
  buildDesktopIconIndex();
}

void ActiveWindowWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto icon = std::make_unique<Image>();
  icon->setRadius(Style::radiusSm);
  icon->setFit(ImageFit::Contain);
  icon->setSize(m_iconSize * m_contentScale, m_iconSize * m_contentScale);
  m_icon = static_cast<Image*>(rootNode->addChild(std::move(icon)));

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody * m_contentScale);
  title->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  title->setMaxWidth(m_maxTitleWidth * m_contentScale);
  title->setMaxLines(1);
  title->setStableBaseline(true);
  m_title = static_cast<Label*>(rootNode->addChild(std::move(title)));

  setRoot(std::move(rootNode));
}

void ActiveWindowWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (rootNode == nullptr || m_icon == nullptr || m_title == nullptr) {
    return;
  }
  syncState(renderer);

  rootNode->setVisible(!m_lastEmptyState);
  if (m_lastEmptyState) {
    rootNode->setSize(0.0f, 0.0f);
    return;
  }

  const bool isVertical = containerHeight > containerWidth;
  const float iconSize = m_iconSize * m_contentScale;
  m_icon->setSize(iconSize, iconSize);
  m_icon->setVisible(true);

  m_title->setMaxWidth(m_maxTitleWidth * m_contentScale);
  m_title->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));

  if (isVertical) {
    m_title->setVisible(false);
    m_icon->setPosition(0.0f, 0.0f);
    rootNode->setSize(m_icon->width(), m_icon->height());
  } else {
    m_title->setVisible(true);
    m_title->measure(renderer);

    const float contentHeight = std::max(m_icon->height(), m_title->height());
    const float iconY = std::round((contentHeight - m_icon->height()) * 0.5f);
    const float labelY = std::round((contentHeight - m_title->height()) * 0.5f);

    m_icon->setPosition(0.0f, iconY);
    m_title->setPosition(m_icon->width() + Style::spaceXs, labelY);

    rootNode->setSize(m_title->x() + m_title->width(), contentHeight);
  }
}

void ActiveWindowWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

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
  bool emptyState = false;

  if (!current.has_value()) {
    identifier = {};
    title = {};
    appId = {};
    emptyState = true;
  } else {
    identifier = current->identifier;
    title = current->title;
    appId = current->appId;
    if (title.empty()) {
      title = appId;
    }
  }

  if (!desktopEntriesChanged && identifier == m_lastIdentifier && title == m_lastTitle && appId == m_lastAppId &&
      emptyState == m_lastEmptyState) {
    return;
  }

  m_lastIdentifier = std::move(identifier);
  m_lastTitle = title;
  m_lastAppId = appId;
  m_lastEmptyState = emptyState;

  std::string iconPath = emptyState ? std::string{} : resolveIconPath(appId);

  m_title->setMaxWidth(m_maxTitleWidth * m_contentScale);
  m_title->setText(m_lastTitle);
  m_title->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_title->setVisible(true);
  m_title->measure(renderer);

  if (iconPath != m_lastIconPath) {
    m_lastIconPath = iconPath;
    if (!m_lastIconPath.empty()) {
      m_icon->setSourceFile(renderer, m_lastIconPath, static_cast<int>(std::round(48.0f * m_contentScale)), true);
    } else {
      m_icon->clear(renderer);
    }
  }

  requestUpdate();
}

std::string ActiveWindowWidget::resolveIconPath(const std::string& appId) {
  if (appId.empty()) {
    return {};
  }

  if (const auto internal = internal_apps::metadataForAppId(appId); internal.has_value()) {
    return internal->iconPath;
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
  auto addIndexKey = [this](std::string_view key, const std::string& icon) {
    if (key.empty() || icon.empty()) {
      return;
    }
    m_appIcons.try_emplace(std::string{key}, icon);
    m_appIcons.try_emplace(toLower(key), icon);
  };

  const auto& entries = desktopEntries();
  for (const auto& entry : entries) {
    if (entry.id.empty() || entry.icon.empty()) {
      continue;
    }

    addIndexKey(entry.id, entry.icon);
    if (const auto dot = entry.id.rfind('.'); dot != std::string::npos && dot + 1 < entry.id.size()) {
      addIndexKey(entry.id.substr(dot + 1), entry.icon);
    }
    // Common packaging suffixes in desktop IDs (e.g. vesktop-bin.desktop).
    if (const auto dash = entry.id.rfind('-'); dash != std::string::npos && dash + 1 < entry.id.size()) {
      const std::string suffix = entry.id.substr(dash + 1);
      if (suffix == "bin" || suffix == "desktop") {
        addIndexKey(entry.id.substr(0, dash), entry.icon);
      }
    }
    if (!entry.startupWmClass.empty()) {
      addIndexKey(entry.startupWmClass, entry.icon);
    }
  }
  m_desktopEntriesVersion = desktopEntriesVersion();
}

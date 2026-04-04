#include "shell/widgets/TrayWidget.h"

#include "dbus/tray/TrayService.h"
#include "core/Log.h"
#include "render/core/Renderer.h"
#include "render/scene/ImageNode.h"
#include "render/scene/Node.h"
#include "ui/controls/Box.h"
#include "ui/controls/Icon.h"
#include "ui/icons/IconRegistry.h"
#include "ui/style/Palette.h"

#include "cursor-shape-v1-client-protocol.h"

#include <linux/input-event-codes.h>
#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <string>

namespace {

namespace fs = std::filesystem;

bool hasImageExt(const std::string& value) {
  return value.ends_with(".png") || value.ends_with(".svg") || value.ends_with(".PNG") || value.ends_with(".SVG");
}

std::string resolveThemeIconPath(const std::string& iconName, const std::string& iconThemePath) {
  if (iconName.empty()) {
    return {};
  }

  if (iconName.find('/') != std::string::npos) {
    return fs::exists(iconName) ? iconName : std::string{};
  }

  const std::string stem = hasImageExt(iconName) ? iconName.substr(0, iconName.find_last_of('.')) : iconName;
  const std::array<std::string, 2> exts = {".png", ".svg"};
  const std::array<std::string, 6> themes = {"hicolor", "Adwaita", "Papirus", "Papirus-Dark", "breeze",
                                             "Yaru"};
  const std::array<std::string, 7> sizes = {"16x16", "18x18", "20x20", "22x22", "24x24", "32x32",
                                             "scalable"};
  const std::array<std::string, 5> categories = {"status", "apps", "devices", "actions", "places"};

  std::vector<fs::path> themedRoots;
  if (!iconThemePath.empty()) {
    themedRoots.emplace_back(iconThemePath);
  }
  const char* xdgDataHome = std::getenv("XDG_DATA_HOME");
  if (xdgDataHome != nullptr && xdgDataHome[0] != '\0') {
    themedRoots.emplace_back(fs::path(xdgDataHome) / "icons");
  }
  const char* home = std::getenv("HOME");
  if (home != nullptr && home[0] != '\0') {
    themedRoots.emplace_back(fs::path(home) / ".icons");
    themedRoots.emplace_back(fs::path(home) / ".local/share/icons");
  }
  themedRoots.emplace_back("/usr/share/icons");
  themedRoots.emplace_back("/usr/local/share/icons");

  for (const auto& root : themedRoots) {
    for (const auto& theme : themes) {
      for (const auto& size : sizes) {
        for (const auto& category : categories) {
          for (const auto& ext : exts) {
            const fs::path candidate = root / theme / size / category / (stem + ext);
            if (fs::exists(candidate)) {
              return candidate.string();
            }
          }
        }
      }
    }
  }

  const std::array<fs::path, 2> pixmaps = {fs::path("/usr/share/pixmaps"), fs::path("/usr/local/share/pixmaps")};
  for (const auto& root : pixmaps) {
    for (const auto& ext : exts) {
      const fs::path candidate = root / (stem + ext);
      if (fs::exists(candidate)) {
        return candidate.string();
      }
    }
  }

  return {};
}

} // namespace

TrayWidget::TrayWidget(TrayService* tray) : m_tray(tray) {}

void TrayWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Box>();
  container->setRowLayout();
  container->setGap(4.0f);
  m_container = container.get();

  m_root = std::move(container);
  syncState(renderer);
  layout(renderer, 0.0f, 0.0f);
}

void TrayWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_container == nullptr) {
    return;
  }

  for (const auto& child : m_container->children()) {
    if (auto* icon = dynamic_cast<Icon*>(child.get())) {
      icon->measure(renderer);
    }
  }

  m_container->layout(renderer);
}

void TrayWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void TrayWidget::onPointerEnter(float localX, float localY) { m_hovered_index = iconIndexAt(localX, localY); }

void TrayWidget::onPointerLeave() { m_hovered_index = -1; }

void TrayWidget::onPointerMotion(float localX, float localY) { m_hovered_index = iconIndexAt(localX, localY); }

bool TrayWidget::onPointerButton(std::uint32_t button, bool pressed) {
  if (!pressed || m_hovered_index < 0) {
    return false;
  }

  const std::size_t idx = static_cast<std::size_t>(m_hovered_index);
  if (idx >= m_item_ids.size() || m_tray == nullptr) {
    return false;
  }

  const std::string& item_id = m_item_ids[idx];
  if (button == BTN_LEFT) {
    return m_tray->activateItem(item_id);
  }
  if (button == BTN_RIGHT) {
    return m_tray->openContextMenu(item_id);
  }
  return false;
}

std::uint32_t TrayWidget::cursorShape() const { return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER; }

void TrayWidget::syncState(Renderer& renderer) {
  const auto next_items = (m_tray != nullptr) ? m_tray->items() : std::vector<TrayItemInfo>{};
  if (next_items == m_items) {
    return;
  }

  m_items = next_items;
  rebuild(renderer);
}

void TrayWidget::rebuild(Renderer& renderer) {
  if (m_container == nullptr) {
    return;
  }

  for (auto& texture : m_loadedTextures) {
    renderer.textureManager().unload(texture);
  }
  m_loadedTextures.clear();

  while (!m_container->children().empty()) {
    m_container->removeChild(m_container->children().back().get());
  }

  m_item_ids.clear();
  m_item_ids.reserve(m_items.size());

  for (const auto& item : m_items) {
    const std::string preferred =
        item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName : item.iconName;
    const std::string iconPath = resolveThemeIconPath(preferred, item.iconThemePath);

    if (!iconPath.empty()) {
      auto texture = renderer.textureManager().loadFromFile(iconPath, 16);
      if (texture.id != 0) {
        auto image = std::make_unique<ImageNode>();
        image->setTextureId(texture.id);

        const float maxDim = static_cast<float>(std::max(texture.width, texture.height));
        const float width = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.width) / maxDim) : 16.0f;
        const float height = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.height) / maxDim) : 16.0f;
        image->setSize(width, height);

        m_container->addChild(std::move(image));
        m_loadedTextures.push_back(texture);
        m_item_ids.push_back(item.id);
        logDebug("tray widget icon id={} source=file path={} size={}x{}", item.id, iconPath, texture.width,
                texture.height);
        continue;
      }
      logDebug("tray widget icon id={} source=file path={} failed-to-load", item.id, iconPath);
    }

    const auto& pixmap = item.needsAttention && !item.attentionArgb32.empty() ? item.attentionArgb32 : item.iconArgb32;
    const std::int32_t pixmapW =
        item.needsAttention && !item.attentionArgb32.empty() ? item.attentionWidth : item.iconWidth;
    const std::int32_t pixmapH =
        item.needsAttention && !item.attentionArgb32.empty() ? item.attentionHeight : item.iconHeight;

    if (!pixmap.empty() && pixmapW > 0 && pixmapH > 0) {
      auto texture = renderer.textureManager().loadFromArgbPixmap(pixmap.data(), pixmapW, pixmapH);
      if (texture.id != 0) {
        auto image = std::make_unique<ImageNode>();
        image->setTextureId(texture.id);

        const float maxDim = static_cast<float>(std::max(texture.width, texture.height));
        const float width = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.width) / maxDim) : 16.0f;
        const float height = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.height) / maxDim) : 16.0f;
        image->setSize(width, height);

        m_container->addChild(std::move(image));
        m_loadedTextures.push_back(texture);
        m_item_ids.push_back(item.id);
        logDebug("tray widget icon id={} source=pixmap size={}x{} (bytes={})", item.id, pixmapW, pixmapH,
                pixmap.size());
        continue;
      }
      logDebug("tray widget icon id={} source=pixmap size={}x{} failed-to-load", item.id, pixmapW, pixmapH);
    }

    auto icon = std::make_unique<Icon>();
    const std::string fallback = iconForItem(item);
    icon->setIcon(fallback);
    icon->setColor(item.needsAttention ? palette.error : palette.onSurface);
    icon->measure(renderer);
    m_container->addChild(std::move(icon));
    m_item_ids.push_back(item.id);
    logDebug("tray widget icon id={} source=glyph name={}", item.id, fallback);
  }

  m_hovered_index = -1;
}

int TrayWidget::iconIndexAt(float localX, float localY) const {
  if (m_container == nullptr) {
    return -1;
  }

  for (std::size_t i = 0; i < m_container->children().size(); ++i) {
    const auto* child = m_container->children()[i].get();

    float absX = 0.0f, absY = 0.0f;
    Node::absolutePosition(child, absX, absY);

    float containerAbsX = 0.0f, containerAbsY = 0.0f;
    Node::absolutePosition(m_container, containerAbsX, containerAbsY);
    const float childLocalX = absX - containerAbsX;
    const float childLocalY = absY - containerAbsY;

    if (localX >= childLocalX && localX < childLocalX + child->width() && localY >= childLocalY &&
        localY < childLocalY + child->height()) {
      return static_cast<int>(i);
    }
  }

  return -1;
}

std::string TrayWidget::iconForItem(const TrayItemInfo& item) const {
  const std::string preferred = item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName
                                                                                         : item.iconName;
  if (!preferred.empty() && IconRegistry::lookup(preferred) != 0) {
    return preferred;
  }
  if (item.needsAttention) {
    return "warning";
  }
  return "menu";
}

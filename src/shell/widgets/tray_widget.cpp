#include "shell/widgets/tray_widget.h"

#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "render/core/renderer.h"
#include "render/scene/image_node.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/glyph_registry.h"
#include "ui/palette.h"

#include <linux/input-event-codes.h>
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
  auto container = std::make_unique<Flex>();
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
    if (auto* glyph = dynamic_cast<Glyph*>(child.get())) {
      glyph->measure(renderer);
    }
  }

  m_container->layout(renderer);
}

void TrayWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

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

  for (const auto& item : m_items) {
    const std::string preferred =
        item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName : item.iconName;
    const std::string iconPath = resolveThemeIconPath(preferred, item.iconThemePath);

    std::unique_ptr<Node> iconNode;
    float iconW = 16.0f;
    float iconH = 16.0f;

    if (!iconPath.empty()) {
      auto texture = renderer.textureManager().loadFromFile(iconPath, 16);
      if (texture.id != 0) {
        auto image = std::make_unique<ImageNode>();
        image->setTextureId(texture.id);

        const float maxDim = static_cast<float>(std::max(texture.width, texture.height));
        iconW = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.width) / maxDim) : 16.0f;
        iconH = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.height) / maxDim) : 16.0f;
        image->setSize(iconW, iconH);

        iconNode = std::move(image);
        m_loadedTextures.push_back(texture);
        logDebug("tray widget icon id={} source=file path={} size={}x{}", item.id, iconPath, texture.width,
                texture.height);
      } else {
        logDebug("tray widget icon id={} source=file path={} failed-to-load", item.id, iconPath);
      }
    }

    if (iconNode == nullptr) {
      const auto& pixmap =
          item.needsAttention && !item.attentionArgb32.empty() ? item.attentionArgb32 : item.iconArgb32;
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
          iconW = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.width) / maxDim) : 16.0f;
          iconH = maxDim > 0.0f ? 16.0f * (static_cast<float>(texture.height) / maxDim) : 16.0f;
          image->setSize(iconW, iconH);

          iconNode = std::move(image);
          m_loadedTextures.push_back(texture);
          logDebug("tray widget icon id={} source=pixmap size={}x{} (bytes={})", item.id, pixmapW, pixmapH,
                  pixmap.size());
        } else {
          logDebug("tray widget icon id={} source=pixmap size={}x{} failed-to-load", item.id, pixmapW, pixmapH);
        }
      }
    }

    if (iconNode == nullptr) {
      auto glyph = std::make_unique<Glyph>();
      const std::string fallback = iconForItem(item);
      glyph->setGlyph(fallback);
      glyph->setColor(item.needsAttention ? palette.error : palette.onSurface);
      glyph->measure(renderer);
      iconW = glyph->width();
      iconH = glyph->height();
      iconNode = std::move(glyph);
      logDebug("tray widget icon id={} source=glyph name={}", item.id, fallback);
    }

    // Wrap icon in InputArea for click handling
    auto area = std::make_unique<InputArea>();
    area->setSize(iconW, iconH);
    auto itemId = item.id;
    area->setOnClick([this, itemId](const InputArea::PointerData& data) {
      if (m_tray == nullptr) {
        return;
      }
      if (data.button == BTN_LEFT) {
        (void)m_tray->activateItem(itemId);
      } else if (data.button == BTN_RIGHT) {
        m_tray->requestMenuToggle(itemId);
      } else if (data.button == BTN_MIDDLE) {
        (void)m_tray->openContextMenu(itemId);
      }
    });
    area->addChild(std::move(iconNode));
    m_container->addChild(std::move(area));
  }
}

std::string TrayWidget::iconForItem(const TrayItemInfo& item) const {
  const std::string preferred = item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName
                                                                                         : item.iconName;
  if (!preferred.empty() && GlyphRegistry::lookup(preferred) != 0) {
    return preferred;
  }
  if (item.needsAttention) {
    return "warning";
  }
  return "menu";
}

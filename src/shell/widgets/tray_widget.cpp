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
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <linux/input-event-codes.h>
#include <memory>
#include <string>

namespace {

constexpr float kTrayIconScale = 0.96f;

std::string toLower(std::string_view value) {
  std::string out(value);
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return out;
}

std::vector<std::string> identifierVariants(std::string_view value) {
  std::vector<std::string> out;
  if (value.empty()) {
    return out;
  }

  auto pushUnique = [&out](std::string candidate) {
    if (candidate.empty()) {
      return;
    }
    if (std::ranges::find(out, candidate) == out.end()) {
      out.push_back(std::move(candidate));
    }
  };

  std::string base(value);
  pushUnique(base);
  pushUnique(toLower(base));

  if (const auto slash = base.find_last_of('/'); slash != std::string::npos && slash + 1 < base.size()) {
    base = base.substr(slash + 1);
    pushUnique(base);
    pushUnique(toLower(base));
  }

  std::string dashed = base;
  std::replace(dashed.begin(), dashed.end(), '_', '-');
  pushUnique(dashed);
  pushUnique(toLower(dashed));

  std::string underscored = base;
  std::replace(underscored.begin(), underscored.end(), '-', '_');
  pushUnique(underscored);
  pushUnique(toLower(underscored));

  for (const auto& candidate : std::vector<std::string>{base, dashed, underscored}) {
    for (const auto& suffix : {"_client", "-client", ".desktop"}) {
      if (candidate.size() > std::char_traits<char>::length(suffix) &&
          candidate.ends_with(suffix)) {
        const auto trimmed = candidate.substr(0, candidate.size() - std::char_traits<char>::length(suffix));
        pushUnique(trimmed);
        pushUnique(toLower(trimmed));
      }
    }
  }

  return out;
}

void addIconAlias(std::unordered_map<std::string, std::string>& index, std::string_view key, std::string_view icon) {
  if (key.empty() || icon.empty()) {
    return;
  }

  for (const auto& variant : identifierVariants(key)) {
    index.try_emplace(variant, std::string(icon));
  }
}

std::string execBasename(std::string_view exec) {
  if (exec.empty()) {
    return {};
  }

  std::string token;
  bool inSingle = false;
  bool inDouble = false;
  for (char c : exec) {
    if (c == '\'' && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (c == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (c == ' ' && !inSingle && !inDouble) {
      break;
    }
    token.push_back(c);
  }

  if (token.empty()) {
    return {};
  }
  if (const auto slash = token.find_last_of('/'); slash != std::string::npos && slash + 1 < token.size()) {
    token = token.substr(slash + 1);
  }
  return token;
}

bool isSymbolicIconName(std::string_view name) {
  return name.find("symbolic") != std::string_view::npos || name.ends_with("-panel") || name.ends_with("_panel");
}

bool isSymbolicIconPath(std::string_view path) {
  return path.find("symbolic") != std::string_view::npos || path.find("/status/") != std::string_view::npos;
}

} // namespace

TrayWidget::TrayWidget(TrayService* tray) : m_tray(tray) { buildDesktopIconIndex(); }

void TrayWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Flex>();
  container->setRowLayout();
  container->setAlign(FlexAlign::Center);
  container->setGap(Style::spaceXs * m_contentScale);
  m_container = container.get();

  m_root = std::move(container);
  syncState(renderer);
}

void TrayWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_container == nullptr) {
    return;
  }

  m_container->setGap(Style::spaceXs * m_contentScale);

  for (const auto& child : m_container->children()) {
    if (auto* glyph = dynamic_cast<Glyph*>(child.get())) {
      glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
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
  const auto desktopVersion = desktopEntriesVersion();
  const bool desktopEntriesChanged = desktopVersion != m_desktopEntriesVersion;
  if (desktopEntriesChanged) {
    buildDesktopIconIndex();
    m_preferredIconPaths.clear();
  }

  const auto next_items = (m_tray != nullptr) ? m_tray->items() : std::vector<TrayItemInfo>{};
  if (!desktopEntriesChanged && next_items == m_items) {
    return;
  }

  std::unordered_map<std::string, bool> stillPresent;
  stillPresent.reserve(next_items.size());
  for (const auto& item : next_items) {
    stillPresent[item.id] = true;
  }
  for (auto it = m_preferredIconPaths.begin(); it != m_preferredIconPaths.end();) {
    if (!stillPresent.contains(it->first)) {
      it = m_preferredIconPaths.erase(it);
    } else {
      ++it;
    }
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
    const std::string iconPath = resolveIconPath(item);
    const float slotSize = Style::fontSizeBody * m_contentScale;
    const float iconSize = slotSize * kTrayIconScale;
    const int iconRequestSize = static_cast<int>(std::round(iconSize));

    std::unique_ptr<Node> iconNode;
    float iconW = iconSize;
    float iconH = iconSize;

    if (!iconPath.empty()) {
      auto texture = renderer.textureManager().loadFromFile(iconPath, iconRequestSize);
      if (texture.id != 0) {
        auto image = std::make_unique<ImageNode>();
        image->setTextureId(texture.id);

        const float maxDim = static_cast<float>(std::max(texture.width, texture.height));
        iconW = maxDim > 0.0f ? iconSize * (static_cast<float>(texture.width) / maxDim) : iconSize;
        iconH = maxDim > 0.0f ? iconSize * (static_cast<float>(texture.height) / maxDim) : iconSize;
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
          iconW = maxDim > 0.0f ? iconSize * (static_cast<float>(texture.width) / maxDim) : iconSize;
          iconH = maxDim > 0.0f ? iconSize * (static_cast<float>(texture.height) / maxDim) : iconSize;
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
      glyph->setGlyphSize(iconSize);
      glyph->setColor(item.needsAttention ? palette.error : palette.onSurface);
      glyph->measure(renderer);
      iconW = glyph->width();
      iconH = glyph->height();
      iconNode = std::move(glyph);
      logDebug("tray widget icon id={} source=glyph name={}", item.id, fallback);
    }

    // Wrap icon in InputArea for click handling
    auto area = std::make_unique<InputArea>();
    area->setSize(slotSize, slotSize);
    iconNode->setPosition(std::round((slotSize - iconW) * 0.5f),
                          std::round((slotSize - iconH) * 0.5f + Style::borderWidth * m_contentScale));
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

void TrayWidget::buildDesktopIconIndex() {
  m_appIcons.clear();
  const auto& entries = desktopEntries();
  for (const auto& entry : entries) {
    if (entry.id.empty() || entry.icon.empty()) {
      continue;
    }

    addIconAlias(m_appIcons, entry.id, entry.icon);
    addIconAlias(m_appIcons, entry.name, entry.icon);
    addIconAlias(m_appIcons, entry.nameLower, entry.icon);
    addIconAlias(m_appIcons, entry.icon, entry.icon);
    addIconAlias(m_appIcons, execBasename(entry.exec), entry.icon);
  }
  m_desktopEntriesVersion = desktopEntriesVersion();
}

std::string TrayWidget::resolveIconPath(const TrayItemInfo& item) {
  if (const auto it = m_preferredIconPaths.find(item.id);
      it != m_preferredIconPaths.end() && !it->second.empty()) {
    return it->second;
  }

  const std::string preferred =
      item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName : item.iconName;

  auto resolveMapped = [this](const std::string& name) -> std::string {
    if (name.empty()) {
      return {};
    }

    if (const auto it = m_appIcons.find(name); it != m_appIcons.end()) {
      if (const auto mapped = m_iconResolver.resolve(it->second); !mapped.empty()) {
        return mapped;
      }
    }

    const std::string lower = toLower(name);
    if (const auto it = m_appIcons.find(lower); it != m_appIcons.end()) {
      if (const auto mapped = m_iconResolver.resolve(it->second); !mapped.empty()) {
        return mapped;
      }
    }

    if (const auto dot = name.rfind('.'); dot != std::string::npos && dot + 1 < name.size()) {
      const auto tail = name.substr(dot + 1);
      if (const auto it = m_appIcons.find(tail); it != m_appIcons.end()) {
        if (const auto mapped = m_iconResolver.resolve(it->second); !mapped.empty()) {
          return mapped;
        }
      }
      const std::string tailLower = toLower(tail);
      if (const auto it = m_appIcons.find(tailLower); it != m_appIcons.end()) {
        if (const auto mapped = m_iconResolver.resolve(it->second); !mapped.empty()) {
          return mapped;
        }
      }
    }

    return {};
  };

  auto resolveDirect = [this](const std::string& name) -> std::string {
    if (name.empty()) {
      return {};
    }
    return m_iconResolver.resolve(name);
  };

  std::string symbolicFallback;

  for (const auto& [label, candidate] : std::array<std::pair<const char*, const std::string*>, 6>{
           {{"preferred", &preferred},
            {"itemName", &item.itemName},
            {"title", &item.title},
            {"busName", &item.busName},
            {"objectPath", &item.objectPath},
            {"id", &item.id}}}) {
    (void)label;
    for (const auto& variant : identifierVariants(*candidate)) {
      if (const auto mapped = resolveMapped(variant); !mapped.empty()) {
        if (!isSymbolicIconPath(mapped)) {
          m_preferredIconPaths[item.id] = mapped;
          return mapped;
        }
        if (symbolicFallback.empty()) {
          symbolicFallback = mapped;
        }
      }

      if (const auto direct = resolveDirect(variant); !direct.empty()) {
        if (!isSymbolicIconName(variant) && !isSymbolicIconPath(direct)) {
          m_preferredIconPaths[item.id] = direct;
          return direct;
        }
        if (symbolicFallback.empty()) {
          symbolicFallback = direct;
        }
      }
    }
  }

  return symbolicFallback;
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

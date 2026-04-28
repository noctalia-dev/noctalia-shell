#include "shell/bar/widgets/tray_widget.h"

#include "core/log.h"
#include "core/ui_phase.h"
#include "dbus/tray/tray_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/glyph_registry.h"
#include "ui/controls/image.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <linux/input-event-codes.h>
#include <memory>
#include <string>

namespace {

  namespace fs = std::filesystem;

  constexpr Logger kLog("tray");

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

    auto pushReducedForms = [&pushUnique](std::string candidate) {
      if (candidate.empty()) {
        return;
      }

      pushUnique(candidate);
      pushUnique(toLower(candidate));

      bool changed = true;
      while (changed && !candidate.empty()) {
        changed = false;

        for (const auto& suffix : {"_client", "-client", ".desktop", "_indicator", "-indicator", "_tray", "-tray",
                                   "_status", "-status", "_panel", "-panel"}) {
          if (candidate.size() > std::char_traits<char>::length(suffix) && candidate.ends_with(suffix)) {
            candidate = candidate.substr(0, candidate.size() - std::char_traits<char>::length(suffix));
            pushUnique(candidate);
            pushUnique(toLower(candidate));
            changed = true;
            break;
          }
        }

        if (changed || candidate.empty()) {
          continue;
        }

        const auto separator = candidate.find_last_of("-_");
        if (separator != std::string::npos && separator + 1 < candidate.size()) {
          const std::string tail = candidate.substr(separator + 1);
          const bool numericTail = std::ranges::all_of(tail, [](unsigned char c) { return std::isdigit(c) != 0; });
          if (numericTail) {
            candidate = candidate.substr(0, separator);
            pushUnique(candidate);
            pushUnique(toLower(candidate));
            changed = true;
            continue;
          }
        }

        for (const auto& suffix : {"-linux", "_linux"}) {
          if (candidate.size() > std::char_traits<char>::length(suffix) && candidate.ends_with(suffix)) {
            candidate = candidate.substr(0, candidate.size() - std::char_traits<char>::length(suffix));
            pushUnique(candidate);
            pushUnique(toLower(candidate));
            changed = true;
            break;
          }
        }
      }
    };

    for (const auto& candidate : std::vector<std::string>{base, dashed, underscored}) {
      pushReducedForms(candidate);
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

  bool isUniqueBusName(std::string_view value) { return !value.empty() && value.front() == ':'; }

} // namespace

TrayWidget::TrayWidget(TrayService* tray, std::vector<std::string> hiddenItems)
    : m_tray(tray), m_hiddenItems(std::move(hiddenItems)) {
  std::vector<std::string> normalized;
  normalized.reserve(m_hiddenItems.size());
  for (const auto& token : m_hiddenItems) {
    for (const auto& variant : identifierVariants(token)) {
      if (std::ranges::find(normalized, variant) == normalized.end()) {
        normalized.push_back(variant);
      }
    }
  }
  m_hiddenItems = std::move(normalized);
  buildDesktopIconIndex();
}

std::string TrayWidget::resolveFromTrayThemePath(std::string_view themePath, std::string_view iconName) {
  if (themePath.empty() || iconName.empty()) {
    return {};
  }

  const std::string themePathKey(themePath);
  auto [cacheIt, inserted] = m_trayThemePathIcons.try_emplace(themePathKey);
  if (inserted) {
    std::error_code ec;
    if (!fs::is_directory(themePathKey, ec)) {
      return {};
    }

    auto& iconIndex = cacheIt->second;
    for (fs::recursive_directory_iterator it(themePathKey, fs::directory_options::skip_permission_denied, ec), end;
         !ec && it != end; it.increment(ec)) {
      if (ec || !it->is_regular_file()) {
        continue;
      }

      const fs::path path = it->path();
      const auto extension = toLower(path.extension().string());
      if (extension != ".svg" && extension != ".png") {
        continue;
      }

      const std::string stem = path.stem().string();
      for (const auto& variant : identifierVariants(stem)) {
        iconIndex.try_emplace(variant, path.string());
      }
    }
  }

  const auto& iconIndex = cacheIt->second;
  for (const auto& variant : identifierVariants(iconName)) {
    if (const auto it = iconIndex.find(variant); it != iconIndex.end()) {
      return it->second;
    }
  }

  return {};
}

void TrayWidget::create() {
  auto container = std::make_unique<Flex>();
  container->setRowLayout();
  container->setAlign(FlexAlign::Center);
  container->setGap(Style::spaceXs * m_contentScale);
  m_container = container.get();

  setRoot(std::move(container));
}

void TrayWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  if (m_container == nullptr) {
    return;
  }
  const bool vertical = containerHeight > containerWidth;
  if (vertical != m_isVertical) {
    m_isVertical = vertical;
    m_container->setDirection(m_isVertical ? FlexDirection::Vertical : FlexDirection::Horizontal);
  }
  syncState(renderer);
  if (containerHeight > 0.0f && std::abs(containerHeight - m_contentHeight) > 0.5f) {
    m_contentHeight = containerHeight;
    m_rebuildPending = true;
  }
  if (m_rebuildPending) {
    rebuild(renderer);
    m_rebuildPending = false;
  }

  m_container->setGap(Style::spaceXs * m_contentScale);
  m_container->layout(renderer);
}

void TrayWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void TrayWidget::syncState(Renderer& renderer) {
  (void)renderer;
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
  m_rebuildPending = true;
  if (root() != nullptr) {
    root()->markLayoutDirty();
  }
}

void TrayWidget::rebuild(Renderer& renderer) {
  uiAssertNotRendering("TrayWidget::rebuild");
  if (m_container == nullptr) {
    return;
  }

  for (auto* image : m_loadedImages) {
    if (image != nullptr) {
      image->clear(renderer);
    }
  }
  m_loadedImages.clear();

  while (!m_container->children().empty()) {
    m_container->removeChild(m_container->children().back().get());
  }

  for (const auto& item : m_items) {
    if (isHiddenItem(item)) {
      continue;
    }
    const std::string iconPath = resolveIconPath(item);
    const float slotSize = Style::barGlyphSize * m_contentScale;
    const float iconSize = Style::fontSizeBody * m_contentScale;
    const float fallbackGlyphSize = Style::barGlyphSize * m_contentScale;
    float itemSize = std::max(slotSize, iconSize);
    const int iconRequestSize = static_cast<int>(std::round(iconSize));

    std::unique_ptr<Node> iconNode;
    float iconW = iconSize;
    float iconH = iconSize;

    if (!iconPath.empty()) {
      auto image = std::make_unique<Image>();
      image->setFit(ImageFit::Contain);
      image->setSize(iconSize, iconSize);
      if (image->setSourceFile(renderer, iconPath, iconRequestSize, true)) {
        iconW = iconSize;
        iconH = iconSize;
        kLog.debug("tray widget icon id={} source=file path={} size={}x{}", item.id, iconPath, image->sourceWidth(),
                   image->sourceHeight());
        m_loadedImages.push_back(image.get());
        iconNode = std::move(image);
      } else {
        kLog.debug("tray widget icon id={} source=file path={} failed-to-load", item.id, iconPath);
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
        auto image = std::make_unique<Image>();
        image->setFit(ImageFit::Contain);
        image->setSize(iconSize, iconSize);
        if (image->setSourceRaw(renderer, pixmap.data(), pixmap.size(), pixmapW, pixmapH, 0, PixmapFormat::ARGB,
                                true)) {
          iconW = iconSize;
          iconH = iconSize;
          kLog.debug("tray widget icon id={} source=pixmap size={}x{} (bytes={})", item.id, pixmapW, pixmapH,
                     pixmap.size());
          m_loadedImages.push_back(image.get());
          iconNode = std::move(image);
        } else {
          kLog.debug("tray widget icon id={} source=pixmap size={}x{} failed-to-load", item.id, pixmapW, pixmapH);
        }
      }
    }

    if (iconNode == nullptr) {
      auto glyph = std::make_unique<Glyph>();
      const std::string fallback = iconForItem(item);
      glyph->setGlyph(fallback);
      glyph->setGlyphSize(fallbackGlyphSize);
      glyph->setColor(item.needsAttention ? roleColor(ColorRole::Error)
                                          : widgetForegroundOr(roleColor(ColorRole::OnSurface)));
      glyph->measure(renderer);
      iconW = glyph->width();
      iconH = glyph->height();
      itemSize = std::max({itemSize, iconW, iconH});
      iconNode = std::move(glyph);
      kLog.debug("tray widget icon id={} source=glyph name={}", item.id, fallback);
    }

    // Wrap icon in InputArea for click handling
    auto area = std::make_unique<InputArea>();
    area->setSize(itemSize, itemSize);
    iconNode->setPosition(std::round((itemSize - iconW) * 0.5f), std::round((itemSize - iconH) * 0.5f));
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

bool TrayWidget::isHiddenItem(const TrayItemInfo& item) const {
  if (m_hiddenItems.empty()) {
    return false;
  }

  std::vector<std::string> candidates;
  auto appendVariants = [&candidates](std::string_view text) {
    for (const auto& variant : identifierVariants(text)) {
      if (std::ranges::find(candidates, variant) == candidates.end()) {
        candidates.push_back(variant);
      }
    }
  };

  appendVariants(item.id);
  appendVariants(item.busName);
  appendVariants(item.objectPath);
  appendVariants(item.itemName);
  appendVariants(item.title);
  appendVariants(item.iconName);
  appendVariants(item.attentionIconName);

  for (const auto& needle : m_hiddenItems) {
    if (std::ranges::find(candidates, needle) != candidates.end()) {
      return true;
    }
  }

  return false;
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
  if (const auto it = m_preferredIconPaths.find(item.id); it != m_preferredIconPaths.end() && !it->second.empty()) {
    kLog.debug("tray widget resolve id={} source=cached path={}", item.id, it->second);
    return it->second;
  }

  const std::string preferred =
      item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName : item.iconName;

  if (const auto themed = resolveFromTrayThemePath(item.iconThemePath, preferred); !themed.empty()) {
    kLog.debug("tray widget resolve id={} source=theme-path variant='{}' path={}", item.id, preferred, themed);
    m_preferredIconPaths[item.id] = themed;
    return themed;
  }

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

  const std::string stableBusName = isUniqueBusName(item.busName) ? std::string{} : item.busName;
  const std::string stableItemId = (!item.id.empty() && !isUniqueBusName(item.id))
                                       ? item.id
                                       : (isUniqueBusName(item.busName) ? item.objectPath : item.id);

  for (const auto& [label, candidate] :
       std::array<std::pair<const char*, const std::string*>, 6>{{{"preferred", &preferred},
                                                                  {"itemName", &item.itemName},
                                                                  {"title", &item.title},
                                                                  {"objectPath", &item.objectPath},
                                                                  {"busName", &stableBusName},
                                                                  {"id", &stableItemId}}}) {
    for (const auto& variant : identifierVariants(*candidate)) {
      if (const auto mapped = resolveMapped(variant); !mapped.empty()) {
        if (!isSymbolicIconPath(mapped)) {
          kLog.debug("tray widget resolve id={} source=mapped label={} variant='{}' path={}", item.id, label, variant,
                     mapped);
          m_preferredIconPaths[item.id] = mapped;
          return mapped;
        }
        if (symbolicFallback.empty()) {
          kLog.debug("tray widget resolve id={} source=mapped-symbolic label={} variant='{}' path={}", item.id, label,
                     variant, mapped);
          symbolicFallback = mapped;
        }
      }

      if (const auto direct = resolveDirect(variant); !direct.empty()) {
        if (!isSymbolicIconName(variant) && !isSymbolicIconPath(direct)) {
          kLog.debug("tray widget resolve id={} source=direct label={} variant='{}' path={}", item.id, label, variant,
                     direct);
          m_preferredIconPaths[item.id] = direct;
          return direct;
        }
        if (symbolicFallback.empty()) {
          kLog.debug("tray widget resolve id={} source=direct-symbolic label={} variant='{}' path={}", item.id, label,
                     variant, direct);
          symbolicFallback = direct;
        }
      }
    }
  }

  kLog.debug("tray widget resolve id={} fallback={} preferred='{}' itemName='{}' title='{}' bus='{}' objectPath='{}' "
             "stableBus='{}' stableId='{}'",
             item.id, symbolicFallback, preferred, item.itemName, item.title, item.busName, item.objectPath,
             stableBusName, stableItemId);
  return symbolicFallback;
}

std::string TrayWidget::iconForItem(const TrayItemInfo& item) const {
  const std::string preferred =
      item.needsAttention && !item.attentionIconName.empty() ? item.attentionIconName : item.iconName;
  if (!preferred.empty() && GlyphRegistry::lookup(preferred) != 0) {
    return preferred;
  }
  if (item.needsAttention) {
    return "warning";
  }
  return "menu";
}

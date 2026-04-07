#pragma once

#include "dbus/tray/tray_service.h"
#include "launcher/desktop_entry.h"
#include "render/core/texture_manager.h"
#include "shell/widget/widget.h"
#include "system/icon_resolver.h"

#include <string>
#include <unordered_map>
#include <vector>

class Flex;
class TrayService;

class TrayWidget : public Widget {
public:
  explicit TrayWidget(TrayService* tray);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void buildDesktopIconIndex();
  [[nodiscard]] std::string resolveIconPath(const TrayItemInfo& item);
  void syncState(Renderer& renderer);
  void rebuild(Renderer& renderer);
  [[nodiscard]] std::string iconForItem(const TrayItemInfo& item) const;

  TrayService* m_tray = nullptr;
  Flex* m_container = nullptr;
  IconResolver m_iconResolver;
  std::unordered_map<std::string, std::string> m_appIcons;
  std::unordered_map<std::string, std::string> m_preferredIconPaths;
  std::vector<TrayItemInfo> m_items;
  std::vector<TextureHandle> m_loadedTextures;
};

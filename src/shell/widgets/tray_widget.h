#pragma once

#include "dbus/tray/tray_service.h"
#include "render/core/texture_manager.h"
#include "shell/widget/widget.h"

#include <string>
#include <vector>

class Box;
class TrayService;

class TrayWidget : public Widget {
public:
  explicit TrayWidget(TrayService* tray);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);
  void rebuild(Renderer& renderer);
  [[nodiscard]] std::string iconForItem(const TrayItemInfo& item) const;

  TrayService* m_tray = nullptr;
  Box* m_container = nullptr;
  std::vector<TrayItemInfo> m_items;
  std::vector<TextureHandle> m_loadedTextures;
};

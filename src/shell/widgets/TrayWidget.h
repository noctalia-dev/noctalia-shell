#pragma once

#include "dbus/tray/TrayService.h"
#include "render/core/TextureManager.h"
#include "shell/Widget.h"

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
  void onPointerEnter(float localX, float localY) override;
  void onPointerLeave() override;
  void onPointerMotion(float localX, float localY) override;
  bool onPointerButton(std::uint32_t button, bool pressed) override;
  std::uint32_t cursorShape() const override;

private:
  void syncState(Renderer& renderer);
  void rebuild(Renderer& renderer);
  int iconIndexAt(float localX, float localY) const;
  [[nodiscard]] std::string iconForItem(const TrayItemInfo& item) const;

  TrayService* m_tray = nullptr;
  Box* m_container = nullptr;
  std::vector<TrayItemInfo> m_items;
  std::vector<std::string> m_item_ids;
  std::vector<TextureHandle> m_loadedTextures;
  int m_hovered_index = -1;
};

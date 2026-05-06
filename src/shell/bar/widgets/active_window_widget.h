#pragma once

#include "shell/bar/widget.h"
#include "system/icon_resolver.h"

#include <cstdint>
#include <string>
#include <unordered_map>

class Image;
class Label;
class Renderer;
class WaylandConnection;
class InputArea;

enum class ActiveWindowTitleScrollMode : std::uint8_t {
  None,
  Always,
  OnHover,
};

class ActiveWindowWidget : public Widget {
public:
  ActiveWindowWidget(WaylandConnection& connection, float maxWidth, float minWidth, float iconSize,
                     ActiveWindowTitleScrollMode titleScrollMode);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void applyTitleScrollMode(bool titleVisible);
  void syncState(Renderer& renderer);
  [[nodiscard]] std::string resolveIconPath(const std::string& appId);
  void buildDesktopIconIndex();

  WaylandConnection& m_connection;
  float m_maxWidth = 260.0f;
  float m_minWidth = 80.0f;
  float m_iconSize = 16.0f;
  ActiveWindowTitleScrollMode m_titleScrollMode = ActiveWindowTitleScrollMode::None;
  InputArea* m_area = nullptr;
  Image* m_icon = nullptr;
  Label* m_title = nullptr;

  IconResolver m_iconResolver;
  std::unordered_map<std::string, std::string> m_appIcons;
  std::uint64_t m_desktopEntriesVersion = 0;

  std::string m_lastIdentifier;
  std::string m_lastTitle;
  std::string m_lastAppId;
  std::string m_lastIconPath;
  bool m_lastEmptyState = false;
};

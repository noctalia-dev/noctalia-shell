#pragma once

#include "shell/widget/widget.h"
#include "system/icon_resolver.h"

#include <string>
#include <unordered_map>

class Image;
class Label;
class Renderer;
class WaylandConnection;

class ActiveWindowWidget : public Widget {
public:
  ActiveWindowWidget(WaylandConnection& connection, float maxTitleWidth, float iconSize);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);
  [[nodiscard]] std::string resolveIconPath(const std::string& appId);
  void buildDesktopIconIndex();

  WaylandConnection& m_connection;
  float m_maxTitleWidth = 240.0f;
  float m_iconSize = 16.0f;
  Image* m_icon = nullptr;
  Label* m_title = nullptr;

  IconResolver m_iconResolver;
  std::unordered_map<std::string, std::string> m_appIcons;

  std::string m_lastIdentifier;
  std::string m_lastTitle;
  std::string m_lastAppId;
  std::string m_lastIconPath;
};

#pragma once

#include "render/scene/node.h"
#include "ui/signal.h"

#include <functional>

class InputArea;
class RectNode;

class Scrollbar : public Node {
public:
  Scrollbar();

  void setOnScrollChanged(std::function<void(float)> callback);

  void update(float viewportHeight, float contentHeight, float scrollOffset);

  [[nodiscard]] float thumbTravel() const noexcept { return m_thumbTravel; }
  [[nodiscard]] bool visible() const noexcept { return m_shown; }

private:
  void applyPalette();
  void applyThumbPosition(float scrollOffset, float maxScroll);

  RectNode* m_track = nullptr;
  RectNode* m_thumb = nullptr;
  InputArea* m_trackArea = nullptr;
  InputArea* m_thumbArea = nullptr;

  Signal<>::ScopedConnection m_paletteConn;
  std::function<void(float)> m_onScrollChanged;

  float m_viewportHeight = 0.0f;
  float m_contentHeight = 0.0f;
  float m_maxScroll = 0.0f;
  float m_thumbTravel = 0.0f;
  float m_dragStartY = 0.0f;
  float m_dragStartOffset = 0.0f;
  bool m_shown = false;
};

#pragma once

#include "ui/controls/box.h"

#include <functional>

class InputArea;
class RectNode;
class Renderer;

class ScrollView : public Box {
public:
  ScrollView();

  [[nodiscard]] Box* content() noexcept { return m_content; }
  [[nodiscard]] const Box* content() const noexcept { return m_content; }

  void setScrollOffset(float offset);
  void scrollBy(float delta);
  void setScrollStep(float step);
  void setScrollbarVisible(bool visible);
  void setOnScrollChanged(std::function<void(float)> callback);

  [[nodiscard]] float scrollOffset() const noexcept { return m_scrollOffset; }
  [[nodiscard]] float maxScrollOffset() const noexcept { return m_maxScrollOffset; }
  [[nodiscard]] bool scrollable() const noexcept { return m_maxScrollOffset > 0.0f; }

  void layout(Renderer& renderer) override;

private:
  void applyScrollOffset();
  void updateScrollbarGeometry(float viewportHeight, float contentHeight);
  [[nodiscard]] float clampOffset(float offset) const noexcept;

  RectNode* m_background = nullptr;
  InputArea* m_viewportArea = nullptr;
  Box* m_content = nullptr;
  RectNode* m_scrollbarTrack = nullptr;
  RectNode* m_scrollbarThumb = nullptr;
  InputArea* m_scrollbarThumbArea = nullptr;

  std::function<void(float)> m_onScrollChanged;

  float m_scrollOffset = 0.0f;
  float m_maxScrollOffset = 0.0f;
  float m_scrollStep = 42.0f;
  float m_dragStartLocalY = 0.0f;
  float m_dragStartOffset = 0.0f;
  float m_thumbTravel = 0.0f;
  bool m_showScrollbar = true;
};

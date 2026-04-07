#pragma once

#include "ui/controls/flex.h"
#include "ui/style.h"

#include <functional>

class InputArea;
class RectNode;
class Renderer;

class ScrollView : public Flex {
public:
  ScrollView();

  [[nodiscard]] Flex* content() noexcept { return m_content; }
  [[nodiscard]] const Flex* content() const noexcept { return m_content; }

  void setScrollOffset(float offset);
  void scrollBy(float delta);
  void setScrollbarVisible(bool visible);
  void setViewportPaddingH(float padding);
  void setBackgroundStyle(const Color& fill, const Color& border, float borderWidth);
  void setOnScrollChanged(std::function<void(float)> callback);

  [[nodiscard]] float scrollOffset() const noexcept { return m_scrollOffset; }
  [[nodiscard]] float maxScrollOffset() const noexcept { return m_maxScrollOffset; }
  [[nodiscard]] bool scrollable() const noexcept { return m_maxScrollOffset > 0.0f; }
  [[nodiscard]] float contentViewportWidth() const noexcept;

  void layout(Renderer& renderer) override;

private:
  void applyScrollOffset();
  void updateScrollbarGeometry(float viewportHeight, float contentHeight);
  [[nodiscard]] float clampOffset(float offset) const noexcept;

  RectNode* m_background = nullptr;
  InputArea* m_viewportArea = nullptr;
  Flex* m_content = nullptr;
  RectNode* m_scrollbarTrack = nullptr;
  RectNode* m_scrollbarThumb = nullptr;
  InputArea* m_scrollbarThumbArea = nullptr;

  std::function<void(float)> m_onScrollChanged;

  float m_viewportPaddingH = Style::spaceXs;
  float m_scrollOffset = 0.0f;
  float m_maxScrollOffset = 0.0f;
  float m_scrollWheelStep = Style::scrollWheelStep;
  float m_dragStartLocalY = 0.0f;
  float m_dragStartOffset = 0.0f;
  float m_thumbTravel = 0.0f;
  float m_viewportHeight = 0.0f;
  float m_viewportWidth = 0.0f;
  bool m_scrollbarShown = false;
  bool m_showScrollbar = true;
};

#pragma once

#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/signal.h"
#include "ui/style.h"

#include <functional>
#include <optional>

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
  void setViewportPaddingV(float padding);
  void setBackgroundStyle(const ThemeColor& fill, const ThemeColor& border, float borderWidth);
  void setBackgroundStyle(const Color& fill, const Color& border, float borderWidth);
  void clearBackgroundStyle();
  void setBackgroundRoles(ColorRole fillRole, ColorRole borderRole, float borderWidth);
  void setOnScrollChanged(std::function<void(float)> callback);

  [[nodiscard]] float scrollOffset() const noexcept { return m_scrollOffset; }
  [[nodiscard]] float maxScrollOffset() const noexcept { return m_maxScrollOffset; }
  [[nodiscard]] bool scrollable() const noexcept { return m_maxScrollOffset > 0.0f; }
  [[nodiscard]] float contentViewportWidth() const noexcept;

private:
  void doLayout(Renderer& renderer) override;
  void applyPalette();
  void applyScrollOffset();
  void updateScrollbarGeometry(float viewportHeight, float contentHeight);
  [[nodiscard]] float clampOffset(float offset) const noexcept;

  RectNode* m_background = nullptr;
  InputArea* m_viewportArea = nullptr;
  Flex* m_content = nullptr;
  RectNode* m_scrollbarTrack = nullptr;
  RectNode* m_scrollbarThumb = nullptr;
  InputArea* m_scrollbarTrackArea = nullptr;
  InputArea* m_scrollbarThumbArea = nullptr;

  std::function<void(float)> m_onScrollChanged;
  ThemeColor m_backgroundFill = clearThemeColor();
  ThemeColor m_backgroundBorder = clearThemeColor();
  ThemeColor m_scrollbarTrackColor = roleColor(ColorRole::Outline, 0.45f);
  ThemeColor m_scrollbarThumbColor = roleColor(ColorRole::Primary);
  Signal<>::ScopedConnection m_paletteConn;

  float m_viewportPaddingH = Style::spaceXs;
  float m_viewportPaddingV = Style::spaceSm;
  float m_scrollOffset = 0.0f;
  float m_maxScrollOffset = 0.0f;
  float m_scrollWheelStep = Style::scrollWheelStep;
  float m_dragStartLocalY = 0.0f;
  float m_dragStartOffset = 0.0f;
  float m_thumbTravel = 0.0f;
  float m_viewportHeight = 0.0f;
  float m_viewportWidth = 0.0f;
  float m_backgroundBorderWidth = 0.0f;
  bool m_scrollbarShown = false;
  bool m_showScrollbar = true;
};

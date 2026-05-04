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

struct ScrollViewState {
  float offset = 0.0f;
};

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
  void setFill(const ColorSpec& fill);
  void setFill(const Color& fill);
  void clearFill();
  void setBorder(const ColorSpec& border, float width);
  void setBorder(const Color& border, float width);
  void clearBorder();
  void setRadius(float radius);
  void setSoftness(float softness);
  void setCardStyle(float scale = 1.0f);
  void bindState(ScrollViewState* state);
  void setOnScrollChanged(std::function<void(float)> callback);

  [[nodiscard]] float scrollOffset() const noexcept { return m_scrollOffset; }
  [[nodiscard]] float maxScrollOffset() const noexcept { return m_maxScrollOffset; }
  [[nodiscard]] bool scrollable() const noexcept { return m_maxScrollOffset > 0.0f; }
  [[nodiscard]] float contentViewportWidth() const noexcept;
  [[nodiscard]] float viewportPaddingH() const noexcept { return m_viewportPaddingH; }
  [[nodiscard]] float viewportPaddingV() const noexcept { return m_viewportPaddingV; }

private:
  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;
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

  ScrollViewState* m_boundState = nullptr;
  std::function<void(float)> m_onScrollChanged;
  ColorSpec m_backgroundFill = clearColorSpec();
  ColorSpec m_backgroundBorder = clearColorSpec();
  ColorSpec m_scrollbarTrackColor = colorSpecFromRole(ColorRole::Outline, 0.45f);
  ColorSpec m_scrollbarThumbColor = colorSpecFromRole(ColorRole::Primary);
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
  float m_backgroundRadius = Style::radiusMd;
  float m_backgroundSoftness = 1.0f;
  bool m_scrollbarShown = false;
  bool m_showScrollbar = true;
};

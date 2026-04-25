#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"

#include <optional>

class Renderer;
class RectNode;

enum class FlexDirection : std::uint8_t {
  Horizontal,
  Vertical,
};

enum class FlexAlign : std::uint8_t {
  Start,
  Center,
  End,
  Stretch,
};

enum class FlexJustify : std::uint8_t {
  Start,
  Center,
  End,
  SpaceBetween,
};

class Flex : public Node {
public:
  Flex();

  void setDirection(FlexDirection direction);
  void setGap(float gap);
  void setAlign(FlexAlign align);
  void setJustify(FlexJustify justify);
  void setPadding(float top, float right, float bottom, float left);
  void setPadding(float all);
  void setPadding(float vertical, float horizontal);

  void setFill(const ThemeColor& color);
  // Explicit fixed color.
  void setFill(const Color& color);
  void clearFill();
  void setRadius(float radius);
  void setBorder(const ThemeColor& color, float width);
  // Explicit fixed color.
  void setBorder(const Color& color, float width);
  void clearBorder();
  void setSoftness(float softness);

  // Default app card chrome: filled surface variant with a soft outline.
  void setCardStyle(float scale = 1.0f);

  void setMinWidth(float minWidth);
  void setMinHeight(float minHeight);
  void setMaxWidth(float maxWidth);
  void setMaxHeight(float maxHeight);
  void setFillParentMainAxis(bool fill);

  void setRowLayout();

  [[nodiscard]] FlexDirection direction() const noexcept { return m_direction; }
  [[nodiscard]] float gap() const noexcept { return m_gap; }
  [[nodiscard]] FlexAlign align() const noexcept { return m_align; }
  [[nodiscard]] FlexJustify justify() const noexcept { return m_justify; }
  [[nodiscard]] float paddingTop() const noexcept { return m_paddingTop; }
  [[nodiscard]] float paddingRight() const noexcept { return m_paddingRight; }
  [[nodiscard]] float paddingBottom() const noexcept { return m_paddingBottom; }
  [[nodiscard]] float paddingLeft() const noexcept { return m_paddingLeft; }

  void setSize(float width, float height) override;
  void setFrameSize(float width, float height);

protected:
  void doLayout(Renderer& renderer) override;

private:
  void ensureBackground();
  void applyPalette();

  RectNode* m_background = nullptr;
  ThemeColor m_fill = clearThemeColor();
  ThemeColor m_border = clearThemeColor();
  Signal<>::ScopedConnection m_paletteConn;
  FlexDirection m_direction = FlexDirection::Horizontal;
  FlexAlign m_align = FlexAlign::Center;
  FlexJustify m_justify = FlexJustify::Start;
  float m_gap = 0.0f;
  float m_paddingTop = 0.0f;
  float m_paddingRight = 0.0f;
  float m_paddingBottom = 0.0f;
  float m_paddingLeft = 0.0f;
  float m_minWidth = 0.0f;
  float m_minHeight = 0.0f;
  float m_maxWidth = 0.0f;
  float m_maxHeight = 0.0f;
  bool m_fillParentMainAxis = false;
};

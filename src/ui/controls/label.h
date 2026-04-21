#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"
#include "render/scene/text_node.h"
#include "ui/palette.h"

#include <optional>
#include <string>
#include <string_view>

class Renderer;

class Label : public Node {
public:
  Label();

  void setText(std::string_view text);
  void setFontSize(float size);
  void setColor(const ThemeColor& color);
  // Explicit fixed color.
  void setColor(const Color& color);
  void setMinWidth(float minWidth);
  void setMaxWidth(float maxWidth);
  void setMaxLines(int maxLines);
  void setBold(bool bold);
  void setTextAlign(TextAlign align);
  // Enable stable-baseline centering for single-line labels whose text changes
  // frequently (clocks, counters). Caps are centered using the font's caps
  // reference instead of the current text's ink, so the baseline stays fixed
  // when descenders appear/disappear (e.g. "Mar" ↔ "Apr"). Also aligns with
  // dynamic-mode sibling labels that happen to contain caps-only text.
  void setStableBaseline(bool stable);
  void setShadow(const Color& color, float offsetX, float offsetY);
  void clearShadow();

  [[nodiscard]] const std::string& text() const noexcept;
  [[nodiscard]] float fontSize() const noexcept;
  [[nodiscard]] const Color& color() const noexcept;
  [[nodiscard]] float maxWidth() const noexcept;
  [[nodiscard]] bool bold() const noexcept;
  [[nodiscard]] TextAlign textAlign() const noexcept;
  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

  void measure(Renderer& renderer);

  void setCaptionStyle();

private:
  void doLayout(Renderer& renderer) override;
  void applyPalette();

  TextNode* m_textNode = nullptr;
  float m_minWidth = 0.0f;
  float m_baselineOffset = 0.0f;
  ThemeColor m_color = roleColor(ColorRole::OnSurface);
  Signal<>::ScopedConnection m_paletteConn;

  // Memoized measure() inputs — lets repeated layout passes with identical
  // text skip the Pango/fontconfig path entirely.
  std::string m_cachedText;
  float m_cachedFontSize = 0.0f;
  float m_cachedMaxWidth = 0.0f;
  float m_cachedMinWidth = 0.0f;
  float m_cachedAssignedWidth = -1.0f;
  float m_cachedFlexGrow = 0.0f;
  int m_cachedMaxLines = 0;
  TextAlign m_cachedTextAlign = TextAlign::Start;
  bool m_cachedBold = false;
  bool m_cachedStableBaseline = false;
  bool m_measureCached = false;
  bool m_stableBaseline = false;
};

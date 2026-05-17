#pragma once

#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/signal.h"
#include "ui/style.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

class Box;
class InputArea;
class Glyph;
class Label;
class Node;
class RectNode;
class Renderer;

class Select : public Flex {
public:
  Select();
  ~Select() override;

  void setOptions(std::vector<std::string> options);
  void setSelectedIndex(std::size_t index);
  void clearSelection();
  void setEnabled(bool enabled);
  void setPlaceholder(std::string_view placeholder);
  void setFontSize(float size);
  void setControlHeight(float height);
  void setHorizontalPadding(float padding);
  void setGlyphSize(float size);
  void setOptionIndicators(std::vector<ColorSpec> colors);
  void setOnSelectionChanged(std::function<void(std::size_t, std::string_view)> callback);

  [[nodiscard]] std::size_t selectedIndex() const noexcept { return m_selectedIndex; }
  [[nodiscard]] std::string_view selectedText() const noexcept;
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool open() const noexcept { return m_open; }

private:
  static constexpr std::size_t npos = static_cast<std::size_t>(-1);

  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;
  void syncTriggerText();
  void applyVisualState();
  void handleKey(std::uint32_t sym, std::uint32_t utf32, bool pressed);
  void toggleOpen();
  void closeMenu();
  void openPopupDropdown();

  RectNode* m_triggerBackground = nullptr;
  Box* m_triggerIndicator = nullptr;
  Label* m_triggerLabel = nullptr;
  Glyph* m_triggerGlyph = nullptr;
  InputArea* m_triggerArea = nullptr;

  std::vector<std::string> m_options;
  std::size_t m_selectedIndex = npos;
  std::string m_placeholder;
  bool m_enabled = true;
  bool m_open = false;
  float m_fixedWidth = 0.0f;
  float m_fontSize = Style::fontSizeBody;
  float m_controlHeight = Style::controlHeight;
  float m_horizontalPadding = Style::spaceMd;
  float m_glyphSize = 14.0f;
  std::vector<ColorSpec> m_indicatorColors;
  Signal<>::ScopedConnection m_paletteConn;

  std::function<void(std::size_t, std::string_view)> m_onSelectionChanged;
};

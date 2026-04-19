#pragma once

#include "render/scene/node.h"
#include "ui/signal.h"
#include "ui/style.h"

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

class ClipboardService;
class GlyphNode;
class InputArea;
class Label;
class RectNode;
class Renderer;

class Input : public Node {
public:
  enum class PasswordMaskStyle : std::uint8_t {
    CircleFilled = 0,
    RandomIcons = 1,
  };

  Input();

  void setValue(std::string_view value);
  void setPlaceholder(std::string_view placeholder);
  void setFontSize(float size);
  void setControlHeight(float height);
  void setHorizontalPadding(float padding);
  void setPasswordMode(bool enabled);
  void setOnChange(std::function<void(const std::string&)> callback);
  void setOnSubmit(std::function<void(const std::string&)> callback);
  void setOnKeyEvent(std::function<bool(std::uint32_t sym, std::uint32_t modifiers)> callback);
  void selectAll();

  // Set once at application startup; all Input instances use this for Ctrl+C/X/V.
  static void setClipboardService(ClipboardService* clipboard) noexcept;
  static void setPasswordMaskStyle(PasswordMaskStyle style) noexcept;
  void clearSelection();

  [[nodiscard]] const std::string& value() const noexcept { return m_value; }
  [[nodiscard]] InputArea* inputArea() const noexcept { return m_inputArea; }

private:
  void doLayout(Renderer& renderer) override;
  void handleKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers, bool preedit = false);
  void applyVisualState();
  void updateDisplayText();
  void updateInteractiveGeometry();
  [[nodiscard]] float measureCursorX(Renderer& renderer) const;
  [[nodiscard]] bool hasSelection() const noexcept;
  [[nodiscard]] std::size_t selectionStart() const noexcept;
  [[nodiscard]] std::size_t selectionEnd() const noexcept;
  void deleteSelection();
  [[nodiscard]] std::size_t xToByteOffset(float localX) const;
  [[nodiscard]] float stopXForByte(std::size_t bytePos) const;
  void syncPasswordGlyphNodes(std::size_t count);

  static std::size_t nextCharPos(const std::string& s, std::size_t pos);
  static std::size_t prevCharPos(const std::string& s, std::size_t pos);
  static std::string utf32ToUtf8(std::uint32_t codepoint);

  RectNode* m_background = nullptr;
  RectNode* m_selectionRect = nullptr;
  Label* m_label = nullptr;
  RectNode* m_cursor = nullptr;
  InputArea* m_inputArea = nullptr;

  std::string m_value;
  std::string m_placeholder;
  std::size_t m_cursorPos = 0;
  std::size_t m_selectionAnchor = 0;
  std::size_t m_preeditStart = 0;
  std::size_t m_preeditLen = 0;

  std::vector<float> m_stopX;
  std::vector<std::size_t> m_stopByte;
  std::vector<GlyphNode*> m_passwordGlyphs;

  std::function<void(const std::string&)> m_onChange;
  std::function<void(const std::string&)> m_onSubmit;
  std::function<bool(std::uint32_t, std::uint32_t)> m_onKeyEvent;
  float m_fontSize = Style::fontSizeBody;
  float m_controlHeight = Style::controlHeight;
  float m_horizontalPadding = Style::spaceMd;
  bool m_passwordMode = false;
  Signal<>::ScopedConnection m_paletteConn;
};

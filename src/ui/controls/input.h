#pragma once

#include "render/scene/node.h"

#include <functional>
#include <string>
#include <string_view>

class InputArea;
class RectNode;
class Renderer;
class TextNode;

class Input : public Node {
public:
  Input();

  void setValue(std::string_view value);
  void setPlaceholder(std::string_view placeholder);
  void setOnChange(std::function<void(const std::string&)> callback);
  void setOnSubmit(std::function<void(const std::string&)> callback);

  [[nodiscard]] const std::string& value() const noexcept { return m_value; }

  void layout(Renderer& renderer);

private:
  void handleKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers);
  void applyVisualState();
  void updateDisplayText();
  [[nodiscard]] float measureCursorX(Renderer& renderer) const;

  static std::size_t nextCharPos(const std::string& s, std::size_t pos);
  static std::size_t prevCharPos(const std::string& s, std::size_t pos);
  static std::string utf32ToUtf8(std::uint32_t codepoint);

  RectNode* m_background = nullptr;
  TextNode* m_textNode = nullptr;
  RectNode* m_cursor = nullptr;
  InputArea* m_inputArea = nullptr;

  std::string m_value;
  std::string m_placeholder;
  std::size_t m_cursorPos = 0;

  std::function<void(const std::string&)> m_onChange;
  std::function<void(const std::string&)> m_onSubmit;
};

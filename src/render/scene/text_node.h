#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <string>

enum class TextAlign : std::uint8_t { Start, Center, End };

class TextNode : public Node {
public:
  TextNode() : Node(NodeType::Text) {}

  [[nodiscard]] const std::string& text() const noexcept { return m_text; }
  [[nodiscard]] float fontSize() const noexcept { return m_fontSize; }
  [[nodiscard]] const Color& color() const noexcept { return m_color; }
  [[nodiscard]] float maxWidth() const noexcept { return m_maxWidth; }
  [[nodiscard]] int maxLines() const noexcept { return m_maxLines; }
  [[nodiscard]] bool bold() const noexcept { return m_bold; }

  void setText(std::string text) {
    if (m_text == text) {
      return;
    }
    m_text = std::move(text);
    markLayoutDirty();
  }

  void setFontSize(float size) {
    if (m_fontSize == size) {
      return;
    }
    m_fontSize = size;
    markLayoutDirty();
  }

  void setColor(const Color& color) {
    if (m_color == color) {
      return;
    }
    m_color = color;
    markPaintDirty();
  }

  void setMaxWidth(float maxWidth) {
    if (m_maxWidth == maxWidth) {
      return;
    }
    m_maxWidth = maxWidth;
    markLayoutDirty();
  }

  void setMaxLines(int maxLines) {
    if (m_maxLines == maxLines) {
      return;
    }
    m_maxLines = maxLines;
    markLayoutDirty();
  }

  void setBold(bool bold) {
    if (m_bold == bold) {
      return;
    }
    m_bold = bold;
    markLayoutDirty();
  }

  [[nodiscard]] TextAlign textAlign() const noexcept { return m_textAlign; }

  void setTextAlign(TextAlign align) {
    if (m_textAlign == align) {
      return;
    }
    m_textAlign = align;
    markLayoutDirty();
  }

private:
  std::string m_text;
  float m_fontSize = 14.0f;
  float m_maxWidth = 0.0f;
  int m_maxLines = 0;
  Color m_color;
  TextAlign m_textAlign = TextAlign::Start;
  bool m_bold = false;
};

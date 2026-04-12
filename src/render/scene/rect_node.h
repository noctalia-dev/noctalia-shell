#pragma once

#include "render/programs/rounded_rect_program.h"
#include "render/scene/node.h"

class RectNode : public Node {
public:
  RectNode() : Node(NodeType::Rect) {}

  [[nodiscard]] const RoundedRectStyle& style() const noexcept { return m_style; }

  void setStyle(const RoundedRectStyle& style) {
    if (m_style == style) {
      return;
    }
    m_style = style;
    markPaintDirty();
  }

private:
  RoundedRectStyle m_style;
};

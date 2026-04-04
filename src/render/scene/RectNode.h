#pragma once

#include "render/programs/RoundedRectProgram.h"
#include "render/scene/Node.h"

class RectNode : public Node {
public:
  RectNode() : Node(NodeType::Rect) {}

  [[nodiscard]] const RoundedRectStyle& style() const noexcept { return m_style; }

  void setStyle(const RoundedRectStyle& style) {
    m_style = style;
    markDirty();
  }

private:
  RoundedRectStyle m_style;
};

#pragma once

#include "render/core/Color.h"
#include "render/programs/SpinnerProgram.h"
#include "render/scene/Node.h"

class SpinnerNode : public Node {
public:
  SpinnerNode() : Node(NodeType::Spinner) {}

  void setColor(const Color& color) { m_style.color = color; }
  void setThickness(float thickness) { m_style.thickness = thickness; }

  [[nodiscard]] const Color& color() const noexcept { return m_style.color; }
  [[nodiscard]] float thickness() const noexcept { return m_style.thickness; }
  [[nodiscard]] const SpinnerStyle& style() const noexcept { return m_style; }

private:
  SpinnerStyle m_style;
};

#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <string_view>

class IconNode;
class Renderer;

class Icon : public Node {
public:
  Icon();

  void setIcon(std::string_view name);
  void setCodepoint(char32_t codepoint);
  void setIconSize(float size);
  void setColor(const Color& color);

  void measure(Renderer& renderer);

  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

private:
  IconNode* m_iconNode = nullptr;
  float m_baselineOffset = 0.0f;
};

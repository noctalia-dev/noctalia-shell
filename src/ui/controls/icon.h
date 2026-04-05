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
  void setSize(float size);
  void setColor(const Color& color);

  void measure(Renderer& renderer);

private:
  IconNode* m_iconNode = nullptr;
};

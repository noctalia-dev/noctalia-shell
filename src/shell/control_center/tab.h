#pragma once

#include "render/core/color.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>
#include <string>

class Flex;
class Label;
class Renderer;

namespace control_center {

constexpr Color alphaSurfaceVariant(float alpha) {
  return rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, alpha);
}

void applyCard(Flex& card);
Label* addTitle(Flex& parent, const std::string& text);
void addBody(Flex& parent, const std::string& text);

} // namespace control_center

class Tab {
public:
  virtual ~Tab() = default;

  // Creates and returns the tab's root Flex container.
  // The returned node is owned by the caller (added to m_tabBodies).
  // Implementations may cache a raw pointer to it for later use.
  virtual std::unique_ptr<Flex> build(Renderer& renderer) = 0;

  // Called by ControlCenterPanel::layout() with the available content dimensions.
  virtual void layout(Renderer& renderer, float contentWidth, float bodyHeight) {
    (void)renderer;
    (void)contentWidth;
    (void)bodyHeight;
  }

  // Called by ControlCenterPanel::update() every frame.
  virtual void update(Renderer& renderer) { (void)renderer; }

  // Called when the panel closes. Null out all raw pointers to freed nodes.
  virtual void onClose() {}
};

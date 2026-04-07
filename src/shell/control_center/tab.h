#pragma once

#include <memory>

class Flex;
class Renderer;

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

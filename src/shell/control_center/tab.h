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

  void applyCard(Flex& card, float scale = 1.0f);
  Label* addTitle(Flex& parent, const std::string& text, float scale = 1.0f);
  void addBody(Flex& parent, const std::string& text, float scale = 1.0f);

} // namespace control_center

class Tab {
public:
  virtual ~Tab() = default;

  // Creates and returns the tab's root Flex container.
  // The returned node is owned by the caller (added to m_tabBodies).
  // Implementations may cache a raw pointer to it for later use.
  virtual std::unique_ptr<Flex> create() = 0;

  // Optional trailing header actions shown in the shared control-center header
  // while this tab is active.
  virtual std::unique_ptr<Flex> createHeaderActions();

  // Called by ControlCenterPanel::layout() with the available content dimensions.
  virtual void layout(Renderer& renderer, float contentWidth, float bodyHeight) {
    (void)renderer;
    (void)contentWidth;
    (void)bodyHeight;
  }

  // Called by ControlCenterPanel::update() every frame.
  virtual void update(Renderer& renderer) { (void)renderer; }

  // Called every Wayland frame callback with elapsed milliseconds. Default is a no-op.
  // Tabs override this to advance per-frame animations independently of data arrival.
  virtual void onFrameTick(float deltaMs) { (void)deltaMs; }

  // Called when the tab becomes visible or hidden.
  virtual void setActive(bool active) { (void)active; }

  // Called when the panel closes. Null out all raw pointers to freed nodes.
  virtual void onClose() {}

  void setContentScale(float scale) noexcept { m_contentScale = scale; }

protected:
  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }
  [[nodiscard]] float scaled(float value) const noexcept { return value * m_contentScale; }

private:
  float m_contentScale = 1.0f;
};

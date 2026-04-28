#pragma once

#include "core/ui_phase.h"
#include "render/scene/node.h"
#include "wayland/layer_surface.h"

#include <cstdint>
#include <memory>
#include <string_view>

class AnimationManager;
class InputArea;
class Renderer;

class Panel {
public:
  virtual ~Panel() = default;

  virtual void create() = 0;
  void layout(Renderer& renderer, float width, float height) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    doLayout(renderer, width, height);
  }
  void update(Renderer& renderer) {
    UiPhaseScope updatePhase(UiPhase::Update);
    doUpdate(renderer);
  }
  virtual void onFrameTick(float deltaMs) { (void)deltaMs; }
  virtual void onOpen(std::string_view context) { (void)context; }
  virtual void onClose() {}
  virtual void onIconThemeChanged() {}
  [[nodiscard]] virtual bool isContextActive(std::string_view context) const {
    (void)context;
    return false;
  }
  [[nodiscard]] virtual bool handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) {
    (void)sym;
    (void)modifiers;
    (void)pressed;
    (void)preedit;
    return false;
  }
  [[nodiscard]] virtual bool deferExternalRefresh() const { return false; }
  [[nodiscard]] virtual bool deferPointerRelayout() const { return false; }

  [[nodiscard]] virtual float preferredWidth() const = 0;
  [[nodiscard]] virtual float preferredHeight() const = 0;
  [[nodiscard]] virtual bool centeredHorizontally() const { return true; }
  [[nodiscard]] virtual bool centeredVertically() const { return true; }
  [[nodiscard]] virtual bool hasDecoration() const { return true; }
  [[nodiscard]] virtual LayerShellLayer layer() const { return LayerShellLayer::Top; }
  [[nodiscard]] virtual LayerShellKeyboard keyboardMode() const { return LayerShellKeyboard::OnDemand; }
  [[nodiscard]] virtual InputArea* initialFocusArea() const { return nullptr; }
  // Opt-in: when true and a suitable bar exists, the panel renders as a wl_subsurface
  // attached to the bar with concave-corner merging. Falls back to a layer surface if no
  // matching bar is available.
  [[nodiscard]] virtual bool prefersAttachedToBar() const noexcept { return false; }
  // For attached panels: which bar edge to attach to when more than one bar exists on
  // the target output. Returned value must outlive the call (use a string literal).
  [[nodiscard]] virtual std::string_view preferredAttachedBarPosition() const noexcept { return "top"; }
  // For attached panels: when true (default), the panel's background opacity tracks the
  // host bar's `backgroundOpacity` config and updates live. When false, the panel uses
  // attachedBackgroundOpacityOverride() instead — useful for panels whose contents need
  // a fixed alpha for legibility (e.g. wallpaper thumbnails).
  [[nodiscard]] virtual bool inheritsBarBackgroundOpacity() const noexcept { return true; }
  [[nodiscard]] virtual float attachedBackgroundOpacityOverride() const noexcept { return 1.0f; }

  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }
  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }

  void setContentScale(float scale) noexcept { m_contentScale = scale; }

  std::unique_ptr<Node> releaseRoot() {
    m_rootPtr = m_root.get();
    return std::move(m_root);
  }

  void setAnimationManager(AnimationManager* mgr) noexcept { m_animations = mgr; }

protected:
  [[nodiscard]] float scaled(float value) const noexcept { return value * m_contentScale; }
  void setRoot(std::unique_ptr<Node> root) { m_root = std::move(root); }
  void clearReleasedRoot() noexcept { m_rootPtr = nullptr; }
  virtual void doLayout(Renderer& renderer, float width, float height) = 0;
  virtual void doUpdate(Renderer& renderer) { (void)renderer; }

  float m_contentScale = 1.0f;
  AnimationManager* m_animations = nullptr;

private:
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
};

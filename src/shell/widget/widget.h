#pragma once

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/scene/node.h"

#include <functional>
#include <memory>
#include <optional>

class AnimationManager;
class Box;
class Renderer;

class Widget {
public:
  using RedrawCallback = std::function<void()>;

  virtual ~Widget() = default;

  virtual void create() = 0;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    doLayout(renderer, containerWidth, containerHeight);
  }
  void update(Renderer& renderer) {
    UiPhaseScope updatePhase(UiPhase::Update);
    doUpdate(renderer);
  }
  virtual void onFrameTick(float deltaMs) { (void)deltaMs; }
  [[nodiscard]] virtual bool needsFrameTick() const { return false; }

  // Input events. Coordinates are widget-local (relative to widget root node).
  virtual void onPointerEnter(float localX, float localY);
  virtual void onPointerLeave();
  virtual void onPointerMotion(float localX, float localY);
  virtual bool onPointerButton(std::uint32_t button, bool pressed);
  [[nodiscard]] virtual std::uint32_t cursorShape() const;

  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }
  [[nodiscard]] float width() const noexcept;
  [[nodiscard]] float height() const noexcept;

  std::unique_ptr<Node> releaseRoot();

  void setAnimationManager(AnimationManager* mgr) noexcept;
  void setRedrawCallback(RedrawCallback callback);
  void setContentScale(float scale) noexcept { m_contentScale = scale; }
  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }
  void setAnchor(bool anchor) noexcept { m_anchor = anchor; }
  [[nodiscard]] bool isAnchor() const noexcept { return m_anchor; }

  void setBarCapsuleSpec(WidgetBarCapsuleSpec spec) noexcept { m_barCapsuleSpec = std::move(spec); }
  void setWidgetForeground(std::optional<ThemeColor> color) noexcept { m_widgetForeground = std::move(color); }
  [[nodiscard]] const WidgetBarCapsuleSpec& barCapsuleSpec() const noexcept { return m_barCapsuleSpec; }
  void setBarCapsuleScene(Node* shell, Box* box) noexcept;
  [[nodiscard]] Node* barCapsuleShell() const noexcept { return m_capsuleShell; }
  [[nodiscard]] Box* barCapsuleBox() const noexcept { return m_capsuleBox; }
  // Outermost node for flex layout / anchor alignment (capsule shell when enabled).
  [[nodiscard]] Node* layoutBoundsNode() const noexcept { return m_capsuleShell != nullptr ? m_capsuleShell : root(); }

  // Whether the bar should paint the decorative capsule for this frame (spec enabled + visible ink).
  [[nodiscard]] virtual bool shouldShowBarCapsule() const;

  // Resolved icon + primary label color: `[widget.*] color` when set, else `capsule_foreground` when the capsule is
  // visible, else `fallback` (e.g. roleColor(OnSurface)).
  [[nodiscard]] ThemeColor widgetForegroundOr(const ThemeColor& fallback) const noexcept;

protected:
  void requestRedraw();
  void setRoot(std::unique_ptr<Node> root) { m_root = std::move(root); }
  void clearReleasedRoot() noexcept { m_rootPtr = nullptr; }
  virtual void doLayout(Renderer& renderer, float containerWidth, float containerHeight) = 0;
  virtual void doUpdate(Renderer& renderer) { (void)renderer; }

  float m_contentScale = 1.0f;
  bool m_anchor = false;
  AnimationManager* m_animations = nullptr;
  RedrawCallback m_redrawCallback;
  WidgetBarCapsuleSpec m_barCapsuleSpec{};
  std::optional<ThemeColor> m_widgetForeground;
  Node* m_capsuleShell = nullptr;
  Box* m_capsuleBox = nullptr;

private:
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
};

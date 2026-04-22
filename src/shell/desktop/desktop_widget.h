#pragma once

#include "core/ui_phase.h"
#include "render/scene/node.h"
#include "ui/palette.h"

#include <functional>
#include <memory>

class AnimationManager;
class Box;
class Renderer;

class DesktopWidget {
public:
  using UpdateCallback = std::function<void()>;
  using RedrawCallback = std::function<void()>;

  virtual ~DesktopWidget() = default;

  virtual void create() = 0;

  void layout(Renderer& renderer);
  void update(Renderer& renderer);

  [[nodiscard]] virtual bool wantsSecondTicks() const { return false; }
  [[nodiscard]] virtual bool needsFrameTick() const { return false; }
  virtual void onFrameTick(float deltaMs, Renderer& renderer) {
    (void)deltaMs;
    (void)renderer;
  }

  [[nodiscard]] Node* root() const noexcept { return m_contentRoot; }
  [[nodiscard]] float intrinsicWidth() const noexcept;
  [[nodiscard]] float intrinsicHeight() const noexcept;
  std::unique_ptr<Node> releaseRoot();

  void setAnimationManager(AnimationManager* manager) noexcept { m_animations = manager; }
  void setUpdateCallback(UpdateCallback callback) { m_updateCallback = std::move(callback); }
  void setRedrawCallback(RedrawCallback callback) { m_redrawCallback = std::move(callback); }
  void setContentScale(float scale) noexcept { m_contentScale = scale; }
  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }
  void setBackgroundStyle(const ThemeColor& color, float radius, float padding);

protected:
  void setRoot(std::unique_ptr<Node> root);

  void requestUpdate() {
    if (m_updateCallback) {
      m_updateCallback();
    }
  }

  void requestRedraw() {
    if (m_redrawCallback) {
      m_redrawCallback();
    }
  }

  virtual void doLayout(Renderer& renderer) = 0;
  virtual void doUpdate(Renderer& renderer) { (void)renderer; }

  float m_contentScale = 1.0f;
  AnimationManager* m_animations = nullptr;

private:
  void applyBackground();

  std::unique_ptr<Node> m_outerRoot;
  std::unique_ptr<Node> m_contentOwned;
  Node* m_contentRoot = nullptr;
  Node* m_outerRootPtr = nullptr;
  Box* m_bgBox = nullptr;
  UpdateCallback m_updateCallback;
  RedrawCallback m_redrawCallback;

  bool m_bgEnabled = false;
  ThemeColor m_bgColor;
  float m_bgRadius = 0.0f;
  float m_bgPadding = 0.0f;
};

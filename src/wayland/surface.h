#pragma once

#include "render/render_target.h"

#include <cstdint>
#include <functional>

struct wl_callback;
struct wl_surface;

class AnimationManager;
class Node;
class RenderContext;
class WaylandConnection;

class Surface {
public:
  using ConfigureCallback = std::function<void(std::uint32_t width, std::uint32_t height)>;
  using UpdateCallback = std::function<void()>;

  explicit Surface(WaylandConnection& connection);
  virtual ~Surface();

  Surface(const Surface&) = delete;
  Surface& operator=(const Surface&) = delete;

  virtual bool initialize() = 0;

  [[nodiscard]] bool isRunning() const noexcept;

  void setConfigureCallback(ConfigureCallback callback);
  void setUpdateCallback(UpdateCallback callback);
  void requestRedraw();
  void renderNow();
  void setAnimationManager(AnimationManager* manager) noexcept { m_animationManager = manager; }
  void setSceneRoot(Node* root) noexcept { m_sceneRoot = root; }
  void setRenderContext(RenderContext* ctx) noexcept { m_renderContext = ctx; }
  [[nodiscard]] RenderContext* renderContext() const noexcept { return m_renderContext; }
  [[nodiscard]] RenderTarget& renderTarget() noexcept { return m_renderTarget; }
  [[nodiscard]] wl_surface* wlSurface() const noexcept { return m_surface; }
  [[nodiscard]] std::uint32_t width() const noexcept { return m_width; }
  [[nodiscard]] std::uint32_t height() const noexcept { return m_height; }
  [[nodiscard]] std::int32_t scale() const noexcept { return m_scale; }

  static void handleFrameDone(void* data, wl_callback* callback, std::uint32_t callbackData);

protected:
  virtual bool createWlSurface();
  virtual void onConfigure(std::uint32_t width, std::uint32_t height);
  virtual void render();
  void requestFrame();
  void destroySurface();

  void setRunning(bool running) noexcept { m_running = running; }
  void setScale(std::int32_t scale) noexcept { m_scale = scale; }

  WaylandConnection& m_connection;
  wl_surface* m_surface = nullptr;

private:
  RenderContext* m_renderContext = nullptr;
  RenderTarget m_renderTarget;
  AnimationManager* m_animationManager = nullptr;
  Node* m_sceneRoot = nullptr;
  ConfigureCallback m_configureCallback;
  UpdateCallback m_updateCallback;
  wl_callback* m_frameCallback = nullptr;
  std::uint32_t m_lastFrameTime = 0;
  bool m_running = false;
  bool m_configured = false;
  std::uint32_t m_width = 0;
  std::uint32_t m_height = 0;
  std::int32_t m_scale = 1;
};

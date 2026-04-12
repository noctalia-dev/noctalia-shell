#pragma once

#include "render/render_target.h"

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

struct wl_callback;
struct wl_surface;

class AnimationManager;
class Node;
class RenderContext;
class WaylandConnection;

struct InputRect {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
};

class Surface {
public:
  using ConfigureCallback = std::function<void(std::uint32_t width, std::uint32_t height)>;
  using PrepareFrameCallback = std::function<void(bool needsUpdate, bool needsLayout)>;
  using UpdateCallback = std::function<void()>;
  using FrameTickCallback = std::function<void(float deltaMs)>;

  explicit Surface(WaylandConnection& connection);
  virtual ~Surface();

  Surface(const Surface&) = delete;
  Surface& operator=(const Surface&) = delete;

  virtual bool initialize() = 0;

  [[nodiscard]] bool isRunning() const noexcept;

  void setConfigureCallback(ConfigureCallback callback);
  void setPrepareFrameCallback(PrepareFrameCallback callback);
  void setUpdateCallback(UpdateCallback callback);
  void setFrameTickCallback(FrameTickCallback callback);
  void setInputRegion(const std::vector<InputRect>& rects);
  void requestUpdate();
  void requestLayout();
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
  [[nodiscard]] std::int32_t bufferScale() const noexcept { return m_bufferScale; }

  static void handleFrameDone(void* data, wl_callback* callback, std::uint32_t callbackData);

protected:
  virtual bool createWlSurface();
  virtual void onConfigure(std::uint32_t width, std::uint32_t height);
  virtual void render();
  void requestFrame();
  void destroySurface();

  void setRunning(bool running) noexcept { m_running = running; }
  void setBufferScale(std::int32_t bufferScale) noexcept { m_bufferScale = bufferScale; }

  WaylandConnection& m_connection;
  wl_surface* m_surface = nullptr;

private:
  void preparePendingFrame();
  void kickFrameLoop();

  RenderContext* m_renderContext = nullptr;
  RenderTarget m_renderTarget;
  AnimationManager* m_animationManager = nullptr;
  Node* m_sceneRoot = nullptr;
  ConfigureCallback m_configureCallback;
  PrepareFrameCallback m_prepareFrameCallback;
  UpdateCallback m_updateCallback;
  FrameTickCallback m_frameTickCallback;
  wl_callback* m_frameCallback = nullptr;
  std::optional<std::chrono::steady_clock::time_point> m_lastFrameAt;
  bool m_updateRequested = false;
  bool m_layoutRequested = false;
  bool m_redrawRequested = false;
  bool m_running = false;
  bool m_configured = false;
  std::uint32_t m_width = 0;
  std::uint32_t m_height = 0;
  std::int32_t m_bufferScale = 1;
};

#pragma once

#include <functional>
#include <memory>

class IpcService;
class LayerSurface;
class RenderContext;
class WaylandConnection;
struct zwp_idle_inhibit_manager_v1;
struct zwp_idle_inhibitor_v1;

class IdleInhibitor {
public:
  using ChangeCallback = std::function<void()>;

  IdleInhibitor();
  ~IdleInhibitor();

  IdleInhibitor(const IdleInhibitor&) = delete;
  IdleInhibitor& operator=(const IdleInhibitor&) = delete;

  bool initialize(WaylandConnection& wayland, RenderContext* renderContext);
  void toggle();
  void setEnabled(bool enabled);
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool available() const noexcept { return m_manager != nullptr; }
  void setChangeCallback(ChangeCallback callback);

  void registerIpc(IpcService& ipc);
  /// Recreate the 1x1 layer-shell anchor when outputs change (hotplug). Keeps this service instance stable.
  void onOutputChange();

private:
  void ensureSurface();
  void syncInhibitor(bool logTransitions = true);
  void destroyInhibitor(bool logDisable = true);
  void notifyChanged();

  WaylandConnection* m_wayland = nullptr;
  RenderContext* m_renderContext = nullptr;
  zwp_idle_inhibit_manager_v1* m_manager = nullptr;
  zwp_idle_inhibitor_v1* m_inhibitor = nullptr;
  std::unique_ptr<LayerSurface> m_surface;
  ChangeCallback m_changeCallback;
  bool m_enabled = false;
};

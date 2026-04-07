#pragma once

#include "auth/pam_authenticator.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

struct KeyboardEvent;
struct PointerEvent;
struct WaylandOutput;
struct ext_session_lock_v1;
struct wl_surface;
struct wl_output;
class StateService;

class LockSurface;
class RenderContext;
class WaylandConnection;

class LockScreen {
public:
  LockScreen();
  ~LockScreen();

  bool initialize(WaylandConnection& wayland, RenderContext* renderContext, StateService* stateService);
  bool lock();
  void unlock();
  void onOutputChange();
  void onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);
  [[nodiscard]] bool isActive() const noexcept;

  static void handleLocked(void* data, ext_session_lock_v1* lock);
  static void handleFinished(void* data, ext_session_lock_v1* lock);

private:
  struct Instance {
    std::uint32_t outputName = 0;
    wl_output* output = nullptr;
    std::unique_ptr<LockSurface> surface;
  };

  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void resetLockState();
  void clearInstances();
  void updatePromptOnSurfaces();
  void tryAuthenticate();
  static void clearSensitiveString(std::string& value);

  WaylandConnection* m_wayland = nullptr;
  RenderContext* m_renderContext = nullptr;
  StateService* m_stateService = nullptr;
  ext_session_lock_v1* m_lock = nullptr;
  std::vector<Instance> m_instances;
  PamAuthenticator m_authenticator;
  std::string m_user;
  std::string m_password;
  std::string m_status;
  wl_surface* m_pointerSurface = nullptr;
  bool m_statusIsError = false;
  bool m_lockPending = false;
  bool m_locked = false;
};

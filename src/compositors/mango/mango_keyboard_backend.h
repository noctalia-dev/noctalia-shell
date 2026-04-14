#pragma once

#include "compositors/keyboard_backend.h"

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

struct wl_display;
struct wl_output;
struct wl_registry;
struct zdwl_ipc_manager_v2;
struct zdwl_ipc_output_v2;

class MangoKeyboardBackend {
public:
  explicit MangoKeyboardBackend(std::string_view compositorHint);
  ~MangoKeyboardBackend();

  MangoKeyboardBackend(const MangoKeyboardBackend&) = delete;
  MangoKeyboardBackend& operator=(const MangoKeyboardBackend&) = delete;
  MangoKeyboardBackend(MangoKeyboardBackend&&) = delete;
  MangoKeyboardBackend& operator=(MangoKeyboardBackend&&) = delete;

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] bool cycleLayout() const;
  [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const;
  [[nodiscard]] std::optional<std::string> currentLayoutName() const;

  void onRegistryGlobal(std::uint32_t name, const char* interfaceName, std::uint32_t version);
  void onRegistryGlobalRemove(std::uint32_t name);
  void onOutputActive(zdwl_ipc_output_v2* handle, std::uint32_t active);
  void onOutputKeyboardLayout(zdwl_ipc_output_v2* handle, const char* layout);
  void onOutputFrame(zdwl_ipc_output_v2* handle);

private:
  void invalidateCachedState() const;
  struct OutputState {
    struct PendingState {
      bool hasActive = false;
      bool active = false;
      bool hasKeyboardLayout = false;
      std::string keyboardLayout;
    } pending;

    wl_output* output = nullptr;
    zdwl_ipc_output_v2* handle = nullptr;
    bool active = false;
    std::string keyboardLayout;
  };

  void ensureConnected() const;
  [[nodiscard]] bool syncState() const;
  void cleanup();

  void bindOutput(std::uint32_t name);
  void bindOutputHandle(wl_output* output);
  void releaseOutput(wl_output* output);
  [[nodiscard]] const OutputState* preferredOutputState() const;

  bool m_enabled = false;
  mutable bool m_initialized = false;
  mutable bool m_failed = false;
  mutable wl_display* m_display = nullptr;
  mutable wl_registry* m_registry = nullptr;
  mutable zdwl_ipc_manager_v2* m_manager = nullptr;
  mutable std::unordered_map<std::uint32_t, wl_output*> m_outputsByName;
  mutable std::unordered_map<wl_output*, OutputState> m_outputs;
  mutable std::unordered_map<zdwl_ipc_output_v2*, wl_output*> m_outputByHandle;
  mutable std::chrono::steady_clock::time_point m_lastSync;
  mutable bool m_hasSynced = false;
};
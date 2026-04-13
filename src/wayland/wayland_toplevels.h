#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>

struct zwlr_foreign_toplevel_handle_v1;
struct zwlr_foreign_toplevel_manager_v1;
struct wl_array;
struct wl_output;
struct wl_seat;

struct ActiveToplevel {
  std::string title;
  std::string appId;
  std::string identifier;
};

struct ToplevelInfo {
  std::string title;
  std::string appId;
  zwlr_foreign_toplevel_handle_v1* handle = nullptr;
};

class WaylandToplevels {
public:
  using ChangeCallback = std::function<void()>;

  void bind(zwlr_foreign_toplevel_manager_v1* manager);
  void setChangeCallback(ChangeCallback callback);
  void cleanup();

  [[nodiscard]] std::optional<ActiveToplevel> current() const;
  [[nodiscard]] wl_output* currentOutput() const;
  [[nodiscard]] std::vector<std::string> allAppIds(wl_output* outputFilter = nullptr) const;
  [[nodiscard]] std::vector<ToplevelInfo> windowsForApp(const std::string& idLower, const std::string& wmClassLower,
                                                        wl_output* outputFilter = nullptr) const;
  void activateHandle(zwlr_foreign_toplevel_handle_v1* handle, wl_seat* seat);
  void closeHandle(zwlr_foreign_toplevel_handle_v1* handle);

  // Listener entrypoints called by C callbacks
  void onToplevelCreated(zwlr_foreign_toplevel_handle_v1* handle);
  void onManagerFinished();
  void onHandleClosed(zwlr_foreign_toplevel_handle_v1* handle);
  void onHandleDone(zwlr_foreign_toplevel_handle_v1* handle);
  void onHandleTitle(zwlr_foreign_toplevel_handle_v1* handle, const char* title);
  void onHandleAppId(zwlr_foreign_toplevel_handle_v1* handle, const char* appId);
  void onHandleState(zwlr_foreign_toplevel_handle_v1* handle, wl_array* state);
  void onHandleOutputEnter(zwlr_foreign_toplevel_handle_v1* handle, wl_output* output);
  void onHandleOutputLeave(zwlr_foreign_toplevel_handle_v1* handle, wl_output* output);

private:
  struct ToplevelState {
    std::string title;
    std::string appId;
    wl_output* output = nullptr;
    bool activated = false;
    bool dirty = false;
    std::uint64_t generation = 0;
  };

  void notifyIfChanged(const std::optional<ActiveToplevel>& before);
  void selectFallbackCurrent();

  zwlr_foreign_toplevel_manager_v1* m_manager = nullptr;
  std::unordered_map<zwlr_foreign_toplevel_handle_v1*, ToplevelState> m_handles;
  zwlr_foreign_toplevel_handle_v1* m_currentHandle = nullptr;
  std::uint64_t m_generation = 0;
  ChangeCallback m_changeCallback;
};

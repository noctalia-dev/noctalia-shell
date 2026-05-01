#include "wayland/wayland_toplevels.h"

#include "system/internal_app_metadata.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include <algorithm>
#include <cctype>
#include <wayland-client.h>

namespace {

  void managerToplevel(void* data, zwlr_foreign_toplevel_manager_v1* /*manager*/,
                       zwlr_foreign_toplevel_handle_v1* handle) {
    static_cast<WaylandToplevels*>(data)->onToplevelCreated(handle);
  }

  void managerFinished(void* data, zwlr_foreign_toplevel_manager_v1* /*manager*/) {
    static_cast<WaylandToplevels*>(data)->onManagerFinished();
  }

  const zwlr_foreign_toplevel_manager_v1_listener kManagerListener = {
      .toplevel = managerToplevel,
      .finished = managerFinished,
  };

  void handleClosed(void* data, zwlr_foreign_toplevel_handle_v1* handle) {
    static_cast<WaylandToplevels*>(data)->onHandleClosed(handle);
  }

  void handleDone(void* data, zwlr_foreign_toplevel_handle_v1* handle) {
    static_cast<WaylandToplevels*>(data)->onHandleDone(handle);
  }

  void handleTitle(void* data, zwlr_foreign_toplevel_handle_v1* handle, const char* title) {
    static_cast<WaylandToplevels*>(data)->onHandleTitle(handle, title);
  }

  void handleAppId(void* data, zwlr_foreign_toplevel_handle_v1* handle, const char* appId) {
    static_cast<WaylandToplevels*>(data)->onHandleAppId(handle, appId);
  }

  void handleState(void* data, zwlr_foreign_toplevel_handle_v1* handle, wl_array* state) {
    static_cast<WaylandToplevels*>(data)->onHandleState(handle, state);
  }

  void handleOutputEnter(void* data, zwlr_foreign_toplevel_handle_v1* handle, wl_output* output) {
    static_cast<WaylandToplevels*>(data)->onHandleOutputEnter(handle, output);
  }
  void handleOutputLeave(void* data, zwlr_foreign_toplevel_handle_v1* handle, wl_output* output) {
    static_cast<WaylandToplevels*>(data)->onHandleOutputLeave(handle, output);
  }
  void handleParent(void* /*data*/, zwlr_foreign_toplevel_handle_v1* /*handle*/,
                    zwlr_foreign_toplevel_handle_v1* /*parent*/) {}

  const zwlr_foreign_toplevel_handle_v1_listener kHandleListener = {
      .title = handleTitle,
      .app_id = handleAppId,
      .output_enter = handleOutputEnter,
      .output_leave = handleOutputLeave,
      .state = handleState,
      .done = handleDone,
      .closed = handleClosed,
      .parent = handleParent,
  };

  std::string effectiveAppId(const std::string& appId, const std::string& title) {
    if (!appId.empty()) {
      return appId;
    }
    if (const auto* app = internal_apps::appDefinitionForWindowTitle(title); app != nullptr) {
      return std::string(app->appId);
    }
    return {};
  }

} // namespace

void WaylandToplevels::bind(zwlr_foreign_toplevel_manager_v1* manager) {
  m_manager = manager;
  zwlr_foreign_toplevel_manager_v1_add_listener(m_manager, &kManagerListener, this);
}

void WaylandToplevels::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void WaylandToplevels::cleanup() {
  for (auto& [handle, _] : m_handles) {
    if (handle != nullptr) {
      zwlr_foreign_toplevel_handle_v1_destroy(handle);
    }
  }
  m_handles.clear();
  m_currentHandle = nullptr;

  if (m_manager != nullptr) {
    zwlr_foreign_toplevel_manager_v1_stop(m_manager);
    zwlr_foreign_toplevel_manager_v1_destroy(m_manager);
    m_manager = nullptr;
  }
}

std::optional<ActiveToplevel> WaylandToplevels::current() const {
  if (m_currentHandle == nullptr) {
    return std::nullopt;
  }
  const auto it = m_handles.find(m_currentHandle);
  if (it == m_handles.end()) {
    return std::nullopt;
  }
  return ActiveToplevel{
      .title = it->second.title,
      .appId = it->second.appId,
      .identifier = it->second.appId + ":" + it->second.title,
      .handle = m_currentHandle,
  };
}

void WaylandToplevels::onToplevelCreated(zwlr_foreign_toplevel_handle_v1* handle) {
  if (handle == nullptr) {
    return;
  }
  m_handles.try_emplace(handle, ToplevelState{});
  zwlr_foreign_toplevel_handle_v1_add_listener(handle, &kHandleListener, this);
}

void WaylandToplevels::onManagerFinished() {
  if (m_manager != nullptr) {
    zwlr_foreign_toplevel_manager_v1_destroy(m_manager);
    m_manager = nullptr;
  }
}

void WaylandToplevels::onHandleClosed(zwlr_foreign_toplevel_handle_v1* handle) {
  const auto before = current();

  if (handle != nullptr) {
    zwlr_foreign_toplevel_handle_v1_destroy(handle);
    m_handles.erase(handle);
  }
  if (m_currentHandle == handle) {
    m_currentHandle = nullptr;
    selectFallbackCurrent();
  }

  const bool activeChanged = notifyIfChanged(before);
  if (!activeChanged && m_changeCallback) {
    m_changeCallback();
  }
}

void WaylandToplevels::onHandleDone(zwlr_foreign_toplevel_handle_v1* handle) {
  auto it = m_handles.find(handle);
  if (it == m_handles.end()) {
    return;
  }

  const auto before = current();
  const bool hadModelChanges = it->second.dirty;
  if (it->second.activated) {
    m_currentHandle = handle;
  } else if (m_currentHandle == nullptr || it->second.dirty) {
    m_currentHandle = handle;
  }
  it->second.dirty = false;

  const bool activeChanged = notifyIfChanged(before);
  if (hadModelChanges && !activeChanged && m_changeCallback) {
    m_changeCallback();
  }
}

void WaylandToplevels::onHandleTitle(zwlr_foreign_toplevel_handle_v1* handle, const char* title) {
  auto it = m_handles.find(handle);
  if (it == m_handles.end()) {
    return;
  }
  it->second.title = title != nullptr ? title : "";
  it->second.dirty = true;
  it->second.generation = ++m_generation;
}

void WaylandToplevels::onHandleAppId(zwlr_foreign_toplevel_handle_v1* handle, const char* appId) {
  auto it = m_handles.find(handle);
  if (it == m_handles.end()) {
    return;
  }
  it->second.appId = appId != nullptr ? appId : "";
  it->second.dirty = true;
  it->second.generation = ++m_generation;
}

void WaylandToplevels::onHandleState(zwlr_foreign_toplevel_handle_v1* handle, wl_array* state) {
  auto it = m_handles.find(handle);
  if (it == m_handles.end()) {
    return;
  }

  bool activated = false;
  if (state != nullptr) {
    auto* value = static_cast<const std::uint32_t*>(state->data);
    const auto count = state->size / sizeof(std::uint32_t);
    for (std::size_t i = 0; i < count; ++i) {
      if (value[i] == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) {
        activated = true;
        break;
      }
    }
  }
  it->second.activated = activated;
  it->second.dirty = true;
  it->second.generation = ++m_generation;
}

wl_output* WaylandToplevels::currentOutput() const {
  if (m_currentHandle == nullptr) {
    return nullptr;
  }
  const auto it = m_handles.find(m_currentHandle);
  if (it == m_handles.end()) {
    return nullptr;
  }
  return it->second.output;
}

std::vector<std::string> WaylandToplevels::allAppIds(wl_output* outputFilter) const {
  std::vector<std::string> ids;
  ids.reserve(m_handles.size());
  for (const auto& [handle, state] : m_handles) {
    if (outputFilter != nullptr && state.output != outputFilter) {
      continue;
    }
    const auto appId = effectiveAppId(state.appId, state.title);
    if (!appId.empty()) {
      ids.push_back(appId);
    }
  }
  return ids;
}

std::vector<ToplevelInfo> WaylandToplevels::windowsForApp(const std::string& idLower, const std::string& wmClassLower,
                                                          wl_output* outputFilter) const {
  std::vector<ToplevelInfo> out;
  for (const auto& [handle, state] : m_handles) {
    if (outputFilter != nullptr && state.output != outputFilter) {
      continue;
    }
    const auto appId = effectiveAppId(state.appId, state.title);
    if (appId.empty())
      continue;
    const auto appLower = [&] {
      std::string s = appId;
      for (auto& c : s)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      return s;
    }();
    if (appLower == idLower || (!wmClassLower.empty() && appLower == wmClassLower)) {
      out.push_back(ToplevelInfo{
          .title = state.title,
          .appId = appId,
          .handle = handle,
      });
    }
  }
  return out;
}

void WaylandToplevels::activateHandle(zwlr_foreign_toplevel_handle_v1* handle, wl_seat* seat) {
  if (handle == nullptr || seat == nullptr)
    return;
  zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
}

void WaylandToplevels::closeHandle(zwlr_foreign_toplevel_handle_v1* handle) {
  if (handle == nullptr)
    return;
  zwlr_foreign_toplevel_handle_v1_close(handle);
}

void WaylandToplevels::onHandleOutputEnter(zwlr_foreign_toplevel_handle_v1* handle, wl_output* output) {
  auto it = m_handles.find(handle);
  if (it != m_handles.end()) {
    if (it->second.output != output) {
      it->second.output = output;
      it->second.dirty = true;
      it->second.generation = ++m_generation;
    }
  }
}

void WaylandToplevels::onHandleOutputLeave(zwlr_foreign_toplevel_handle_v1* handle, wl_output* output) {
  auto it = m_handles.find(handle);
  if (it != m_handles.end() && it->second.output == output) {
    it->second.output = nullptr;
    it->second.dirty = true;
    it->second.generation = ++m_generation;
  }
}

bool WaylandToplevels::notifyIfChanged(const std::optional<ActiveToplevel>& before) {
  const auto now = current();
  if (before.has_value() != now.has_value()) {
    if (m_changeCallback) {
      m_changeCallback();
    }
    return true;
  }
  if (!before.has_value() || !now.has_value()) {
    return false;
  }
  if (before->title != now->title || before->appId != now->appId || before->identifier != now->identifier ||
      before->handle != now->handle) {
    if (m_changeCallback) {
      m_changeCallback();
    }
    return true;
  }
  return false;
}

void WaylandToplevels::selectFallbackCurrent() {
  if (m_handles.empty()) {
    return;
  }

  auto best = std::max_element(m_handles.begin(), m_handles.end(),
                               [](const auto& a, const auto& b) { return a.second.generation < b.second.generation; });
  if (best != m_handles.end()) {
    m_currentHandle = best->first;
  }
}

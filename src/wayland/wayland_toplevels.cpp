#include "wayland/wayland_toplevels.h"

#include <algorithm>

#include <wayland-client.h>

#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

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

void handleOutputEnter(void* /*data*/, zwlr_foreign_toplevel_handle_v1* /*handle*/, wl_output* /*output*/) {}
void handleOutputLeave(void* /*data*/, zwlr_foreign_toplevel_handle_v1* /*handle*/, wl_output* /*output*/) {}
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

  notifyIfChanged(before);
}

void WaylandToplevels::onHandleDone(zwlr_foreign_toplevel_handle_v1* handle) {
  auto it = m_handles.find(handle);
  if (it == m_handles.end()) {
    return;
  }

  const auto before = current();
  if (it->second.activated) {
    m_currentHandle = handle;
  } else if (m_currentHandle == nullptr || it->second.dirty) {
    m_currentHandle = handle;
  }
  it->second.dirty = false;

  notifyIfChanged(before);
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

void WaylandToplevels::notifyIfChanged(const std::optional<ActiveToplevel>& before) {
  const auto now = current();
  if (before.has_value() != now.has_value()) {
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }
  if (!before.has_value() || !now.has_value()) {
    return;
  }
  if (before->title != now->title || before->appId != now->appId || before->identifier != now->identifier) {
    if (m_changeCallback) {
      m_changeCallback();
    }
  }
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

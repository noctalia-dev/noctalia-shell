#include "wayland/WaylandWorkspaces.h"

#include "core/Log.h"

#include <algorithm>

#include "ext-workspace-v1-client-protocol.h"

namespace {

void groupCapabilities(void* /*data*/, ext_workspace_group_handle_v1* /*group*/, uint32_t /*caps*/) {}

void groupOutputEnter(void* data, ext_workspace_group_handle_v1* group, wl_output* output) {
  static_cast<WaylandWorkspaces*>(data)->onGroupOutputEnter(group, output);
}

void groupOutputLeave(void* data, ext_workspace_group_handle_v1* group, wl_output* output) {
  static_cast<WaylandWorkspaces*>(data)->onGroupOutputLeave(group, output);
}

void groupWorkspaceEnter(void* data, ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
  static_cast<WaylandWorkspaces*>(data)->onGroupWorkspaceEnter(group, workspace);
}

void groupWorkspaceLeave(void* data, ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
  static_cast<WaylandWorkspaces*>(data)->onGroupWorkspaceLeave(group, workspace);
}

void groupRemoved(void* data, ext_workspace_group_handle_v1* group) {
  static_cast<WaylandWorkspaces*>(data)->onGroupRemoved(group);
}

const ext_workspace_group_handle_v1_listener kGroupListener = {
    .capabilities = groupCapabilities,
    .output_enter = groupOutputEnter,
    .output_leave = groupOutputLeave,
    .workspace_enter = groupWorkspaceEnter,
    .workspace_leave = groupWorkspaceLeave,
    .removed = groupRemoved,
};

void workspaceId(void* data, ext_workspace_handle_v1* workspace, const char* id) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceIdChanged(workspace, id);
}

void workspaceName(void* data, ext_workspace_handle_v1* workspace, const char* name) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceNameChanged(workspace, name);
}

void workspaceCoordinates(void* data, ext_workspace_handle_v1* workspace, wl_array* coords) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceCoordinatesChanged(workspace, coords);
}

void workspaceState(void* data, ext_workspace_handle_v1* workspace, uint32_t state) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceStateChanged(workspace, state);
}

void workspaceCapabilities(void* /*data*/, ext_workspace_handle_v1* /*workspace*/, uint32_t /*caps*/) {}

void workspaceRemoved(void* data, ext_workspace_handle_v1* workspace) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceRemoved(workspace);
}

const ext_workspace_handle_v1_listener kWorkspaceListener = {
    .id = workspaceId,
    .name = workspaceName,
    .coordinates = workspaceCoordinates,
    .state = workspaceState,
    .capabilities = workspaceCapabilities,
    .removed = workspaceRemoved,
};

void managerWorkspaceGroup(void* data, ext_workspace_manager_v1* /*manager*/, ext_workspace_group_handle_v1* group) {
  static_cast<WaylandWorkspaces*>(data)->onGroupCreated(group);
}

void managerWorkspace(void* data, ext_workspace_manager_v1* /*manager*/, ext_workspace_handle_v1* workspace) {
  static_cast<WaylandWorkspaces*>(data)->onWorkspaceCreated(workspace);
}

void managerDone(void* data, ext_workspace_manager_v1* /*manager*/) {
  static_cast<WaylandWorkspaces*>(data)->onManagerDone();
}

void managerFinished(void* data, ext_workspace_manager_v1* /*manager*/) {
  static_cast<WaylandWorkspaces*>(data)->onManagerFinished();
}

const ext_workspace_manager_v1_listener kManagerListener = {
    .workspace_group = managerWorkspaceGroup,
    .workspace = managerWorkspace,
    .done = managerDone,
    .finished = managerFinished,
};

} // namespace

void WaylandWorkspaces::bind(ext_workspace_manager_v1* manager) {
  m_manager = manager;
  ext_workspace_manager_v1_add_listener(m_manager, &kManagerListener, this);
}

void WaylandWorkspaces::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void WaylandWorkspaces::activate(const std::string& id) {
  if (m_manager == nullptr) {
    return;
  }

  for (const auto& [handle, ws] : m_workspaces) {
    if (ws.id == id) {
      ext_workspace_handle_v1_activate(handle);
      ext_workspace_manager_v1_commit(m_manager);
      logInfo("workspace: activating \"{}\"", ws.name);
      return;
    }
  }
}

void WaylandWorkspaces::activateForOutput(wl_output* output, const std::string& id) {
  if (m_manager == nullptr || output == nullptr) {
    return;
  }

  for (const auto& group : m_groups) {
    const bool hasOutput = std::find(group.outputs.begin(), group.outputs.end(), output) != group.outputs.end();
    if (!hasOutput) {
      continue;
    }

    for (auto* handle : group.workspaces) {
      auto it = m_workspaces.find(handle);
      if (it == m_workspaces.end()) {
        continue;
      }
      if (it->second.id != id) {
        continue;
      }

      ext_workspace_handle_v1_activate(handle);
      ext_workspace_manager_v1_commit(m_manager);
      logInfo("workspace: activating \"{}\"", it->second.name);
      return;
    }
  }

  // Fallback for compositors that do not expose output/group relationships reliably.
  activate(id);
}

void WaylandWorkspaces::activateForOutput(wl_output* output, const Workspace& workspace) {
  if (m_manager == nullptr || output == nullptr) {
    return;
  }

  auto matchesExact = [&](const Workspace& candidate) {
    return candidate.id == workspace.id && candidate.name == workspace.name &&
           candidate.coordinates == workspace.coordinates;
  };

  auto matchesId = [&](const Workspace& candidate) { return !workspace.id.empty() && candidate.id == workspace.id; };

  for (const auto& group : m_groups) {
    const bool hasOutput = std::find(group.outputs.begin(), group.outputs.end(), output) != group.outputs.end();
    if (!hasOutput) {
      continue;
    }

    // First pass: exact match for the workspace row that was clicked.
    for (auto* handle : group.workspaces) {
      auto it = m_workspaces.find(handle);
      if (it == m_workspaces.end()) {
        continue;
      }
      if (!matchesExact(it->second)) {
        continue;
      }

      ext_workspace_handle_v1_activate(handle);
      ext_workspace_manager_v1_commit(m_manager);
      logInfo("workspace: activating \"{}\"", it->second.name);
      return;
    }

    // Second pass: id-only fallback for compositors with unstable metadata.
    for (auto* handle : group.workspaces) {
      auto it = m_workspaces.find(handle);
      if (it == m_workspaces.end()) {
        continue;
      }
      if (!matchesId(it->second)) {
        continue;
      }

      ext_workspace_handle_v1_activate(handle);
      ext_workspace_manager_v1_commit(m_manager);
      logInfo("workspace: activating \"{}\"", it->second.name);
      return;
    }
  }

  // Last-resort fallback for compositors that do not expose output/group relationships reliably.
  if (!workspace.id.empty()) {
    activate(workspace.id);
  }
}

void WaylandWorkspaces::cleanup() {
  for (auto& [workspace, _] : m_workspaces) {
    if (workspace != nullptr) {
      ext_workspace_handle_v1_destroy(workspace);
    }
  }
  m_workspaces.clear();

  for (auto& group : m_groups) {
    if (group.handle != nullptr) {
      ext_workspace_group_handle_v1_destroy(group.handle);
    }
  }
  m_groups.clear();

  if (m_manager != nullptr) {
    ext_workspace_manager_v1_stop(m_manager);
    ext_workspace_manager_v1_destroy(m_manager);
    m_manager = nullptr;
  }
}

std::vector<Workspace> WaylandWorkspaces::all() const {
  std::vector<Workspace> result;
  std::vector<ext_workspace_handle_v1*> seen;

  for (const auto& group : m_groups) {
    for (auto* handle : group.workspaces) {
      if (std::find(seen.begin(), seen.end(), handle) != seen.end()) {
        continue;
      }
      auto it = m_workspaces.find(handle);
      if (it != m_workspaces.end() && !it->second.name.empty()) {
        result.push_back(it->second);
        seen.push_back(handle);
      }
    }
  }

  for (const auto& [handle, ws] : m_workspaces) {
    if (ws.name.empty() || std::find(seen.begin(), seen.end(), handle) != seen.end()) {
      continue;
    }
    result.push_back(ws);
  }

  std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) { return a.coordinates < b.coordinates; });

  return result;
}

std::vector<Workspace> WaylandWorkspaces::forOutput(wl_output* output) const {
  std::vector<ext_workspace_handle_v1*> handles;
  for (const auto& group : m_groups) {
    bool hasOutput = std::find(group.outputs.begin(), group.outputs.end(), output) != group.outputs.end();
    if (hasOutput) {
      handles.insert(handles.end(), group.workspaces.begin(), group.workspaces.end());
    }
  }

  std::vector<Workspace> result;
  for (auto* handle : handles) {
    auto it = m_workspaces.find(handle);
    if (it != m_workspaces.end() && !it->second.name.empty()) {
      result.push_back(it->second);
    }
  }

  std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) { return a.coordinates < b.coordinates; });

  return result;
}

void WaylandWorkspaces::onGroupCreated(ext_workspace_group_handle_v1* group) {
  if (group == nullptr) {
    return;
  }
  m_groups.push_back(WorkspaceGroup{.handle = group, .outputs = {}, .workspaces = {}});
  ext_workspace_group_handle_v1_add_listener(group, &kGroupListener, this);
}

void WaylandWorkspaces::onGroupRemoved(ext_workspace_group_handle_v1* group) {
  std::erase_if(m_groups, [group](const auto& g) { return g.handle == group; });
  if (group != nullptr) {
    ext_workspace_group_handle_v1_destroy(group);
  }
}

void WaylandWorkspaces::onGroupOutputEnter(ext_workspace_group_handle_v1* group, wl_output* output) {
  for (auto& g : m_groups) {
    if (g.handle == group) {
      g.outputs.push_back(output);
      return;
    }
  }
}

void WaylandWorkspaces::onGroupOutputLeave(ext_workspace_group_handle_v1* group, wl_output* output) {
  for (auto& g : m_groups) {
    if (g.handle == group) {
      std::erase(g.outputs, output);
      return;
    }
  }
}

void WaylandWorkspaces::onGroupWorkspaceEnter(ext_workspace_group_handle_v1* group,
                                              ext_workspace_handle_v1* workspace) {
  for (auto& g : m_groups) {
    if (g.handle == group) {
      g.workspaces.push_back(workspace);
      return;
    }
  }
}

void WaylandWorkspaces::onGroupWorkspaceLeave(ext_workspace_group_handle_v1* group,
                                              ext_workspace_handle_v1* workspace) {
  for (auto& g : m_groups) {
    if (g.handle == group) {
      std::erase(g.workspaces, workspace);
      return;
    }
  }
}

void WaylandWorkspaces::onWorkspaceCreated(ext_workspace_handle_v1* workspace) {
  if (workspace == nullptr) {
    return;
  }
  m_workspaces.emplace(workspace, Workspace{});
  ext_workspace_handle_v1_add_listener(workspace, &kWorkspaceListener, this);
}

void WaylandWorkspaces::onWorkspaceIdChanged(ext_workspace_handle_v1* workspace, const char* id) {
  const auto it = m_workspaces.find(workspace);
  if (it == m_workspaces.end()) {
    return;
  }
  it->second.id = id != nullptr ? id : "";
}

void WaylandWorkspaces::onWorkspaceNameChanged(ext_workspace_handle_v1* workspace, const char* name) {
  const auto it = m_workspaces.find(workspace);
  if (it == m_workspaces.end()) {
    return;
  }
  it->second.name = name != nullptr ? name : "";
}

void WaylandWorkspaces::onWorkspaceCoordinatesChanged(ext_workspace_handle_v1* workspace, wl_array* coordinates) {
  const auto it = m_workspaces.find(workspace);
  if (it == m_workspaces.end()) {
    return;
  }

  it->second.coordinates.clear();
  if (coordinates != nullptr) {
    const auto* coords = static_cast<std::uint32_t*>(coordinates->data);
    const auto count = coordinates->size / sizeof(std::uint32_t);
    it->second.coordinates.assign(coords, coords + count);
  }
}

void WaylandWorkspaces::onWorkspaceStateChanged(ext_workspace_handle_v1* workspace, std::uint32_t state) {
  const auto it = m_workspaces.find(workspace);
  if (it == m_workspaces.end()) {
    return;
  }

  const bool is_active = (state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE) != 0;
  if (it->second.active != is_active) {
    it->second.active = is_active;
    if (is_active) {
      const std::string label = it->second.name.empty() ? "(unnamed)" : it->second.name;
      logInfo("workspace active: {}", label);
    }
    if (m_changeCallback) {
      m_changeCallback();
    }
  }
}

void WaylandWorkspaces::onWorkspaceRemoved(ext_workspace_handle_v1* workspace) {
  m_workspaces.erase(workspace);
  if (workspace != nullptr) {
    ext_workspace_handle_v1_destroy(workspace);
  }
}

void WaylandWorkspaces::onManagerDone() {
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void WaylandWorkspaces::onManagerFinished() {
  m_manager = nullptr;
  m_workspaces.clear();
  m_groups.clear();
}

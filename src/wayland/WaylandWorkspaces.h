#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

struct wl_array;
struct wl_output;
struct ext_workspace_manager_v1;
struct ext_workspace_group_handle_v1;
struct ext_workspace_handle_v1;

struct Workspace {
  std::string id;
  std::string name;
  std::vector<std::uint32_t> coordinates;
  bool active = false;
};

class WaylandWorkspaces {
public:
  using ChangeCallback = std::function<void()>;

  void bind(ext_workspace_manager_v1* manager);
  void setChangeCallback(ChangeCallback callback);
  void activate(const std::string& id);
  void activateForOutput(wl_output* output, const std::string& id);
  void activateForOutput(wl_output* output, const Workspace& workspace);
  void cleanup();

  [[nodiscard]] std::vector<Workspace> all() const;
  [[nodiscard]] std::vector<Workspace> forOutput(wl_output* output) const;

  // Listener entrypoints called by C callbacks
  void onGroupCreated(ext_workspace_group_handle_v1* group);
  void onGroupRemoved(ext_workspace_group_handle_v1* group);
  void onGroupOutputEnter(ext_workspace_group_handle_v1* group, wl_output* output);
  void onGroupOutputLeave(ext_workspace_group_handle_v1* group, wl_output* output);
  void onGroupWorkspaceEnter(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace);
  void onGroupWorkspaceLeave(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace);
  void onWorkspaceCreated(ext_workspace_handle_v1* workspace);
  void onWorkspaceIdChanged(ext_workspace_handle_v1* workspace, const char* id);
  void onWorkspaceNameChanged(ext_workspace_handle_v1* workspace, const char* name);
  void onWorkspaceCoordinatesChanged(ext_workspace_handle_v1* workspace, wl_array* coordinates);
  void onWorkspaceStateChanged(ext_workspace_handle_v1* workspace, std::uint32_t state);
  void onWorkspaceRemoved(ext_workspace_handle_v1* workspace);
  void onManagerDone();
  void onManagerFinished();

private:
  struct WorkspaceGroup {
    ext_workspace_group_handle_v1* handle = nullptr;
    std::vector<wl_output*> outputs;
    std::vector<ext_workspace_handle_v1*> workspaces;
  };

  ext_workspace_manager_v1* m_manager = nullptr;
  std::vector<WorkspaceGroup> m_groups;
  std::unordered_map<ext_workspace_handle_v1*, Workspace> m_workspaces;
  ChangeCallback m_changeCallback;
};

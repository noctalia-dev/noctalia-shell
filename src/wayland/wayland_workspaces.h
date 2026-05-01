#pragma once

#include "compositors/workspace_backend.h"

#include <memory>
#include <string_view>
#include <unordered_map>

struct wl_output;
struct ext_workspace_manager_v1;
struct zdwl_ipc_manager_v2;

class WaylandWorkspaces {
public:
  using ChangeCallback = std::function<void()>;

  WaylandWorkspaces();
  ~WaylandWorkspaces();

  void bindExtWorkspace(ext_workspace_manager_v1* manager);
  void bindMangoWorkspace(zdwl_ipc_manager_v2* manager);
  void setSwayOutputNameResolver(std::function<std::string(wl_output*)> resolver);
  void setHyprlandOutputNameResolver(std::function<std::string(wl_output*)> resolver);
  void initialize(std::string_view compositorHint);
  void onOutputAdded(wl_output* output);
  void onOutputRemoved(wl_output* output);
  void setChangeCallback(ChangeCallback callback);
  void activate(const std::string& id);
  void activateForOutput(wl_output* output, const std::string& id);
  void activateForOutput(wl_output* output, const Workspace& workspace);
  void cleanup();
  [[nodiscard]] int pollFd() const noexcept;
  [[nodiscard]] short pollEvents() const noexcept;
  [[nodiscard]] int pollTimeoutMs() const noexcept;
  void dispatchPoll(short revents);
  [[nodiscard]] const char* backendName() const noexcept;
  [[nodiscard]] std::unordered_map<std::string, std::vector<std::string>> appIdsByWorkspace(wl_output* output) const;
  [[nodiscard]] std::vector<WorkspaceWindow> workspaceWindows(wl_output* output) const;

  [[nodiscard]] std::vector<Workspace> all() const;
  [[nodiscard]] std::vector<Workspace> forOutput(wl_output* output) const;

private:
  void setActiveBackend(WorkspaceBackend* backend);
  void notifyChanged() const;

  std::vector<class OutputBackend*> m_outputBackends;
  std::unique_ptr<class ExtWorkspaceBackend> m_extBackend;
  std::unique_ptr<class MangoWorkspaceBackend> m_mangoBackend;
  std::unique_ptr<class HyprlandWorkspaceBackend> m_hyprlandBackend;
  std::unique_ptr<class SwayWorkspaceBackend> m_swayBackend;
  WorkspaceBackend* m_activeBackend = nullptr;
  ChangeCallback m_changeCallback;
};

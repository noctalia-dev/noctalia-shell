#pragma once

#include <cstdint>
#include <functional>
#include <poll.h>
#include <string>
#include <unordered_map>
#include <vector>

struct wl_output;

struct Workspace {
  std::string id;
  std::string name;
  std::vector<std::uint32_t> coordinates;
  bool active = false;
  bool urgent = false;
  bool occupied = false;
};

struct WorkspaceWindow {
  std::string windowId;
  std::string workspaceKey;
  std::string appId;
  std::string title;
  std::int32_t x = 0;
  std::int32_t y = 0;
};

struct TaskbarWindowCandidate {
  std::uintptr_t handleKey = 0;
  std::vector<std::string> appIds;
  std::string title;
};

enum class TaskbarAssignmentMode {
  Generic,
  WorkspaceOccurrenceTitle,
};

class WorkspaceBackend {
public:
  using ChangeCallback = std::function<void()>;

  virtual ~WorkspaceBackend() = default;

  [[nodiscard]] virtual const char* backendName() const = 0;
  [[nodiscard]] virtual bool isAvailable() const noexcept = 0;
  virtual void setChangeCallback(ChangeCallback callback) = 0;
  virtual void activate(const std::string& id) = 0;
  virtual void activateForOutput(wl_output* output, const std::string& id) = 0;
  virtual void activateForOutput(wl_output* output, const Workspace& workspace) = 0;
  [[nodiscard]] virtual std::vector<Workspace> all() const = 0;
  [[nodiscard]] virtual std::vector<Workspace> forOutput(wl_output* output) const = 0;
  [[nodiscard]] virtual std::unordered_map<std::string, std::vector<std::string>>
  appIdsByWorkspace(wl_output* /*output*/) const {
    return {};
  }
  [[nodiscard]] virtual TaskbarAssignmentMode taskbarAssignmentMode() const noexcept {
    return TaskbarAssignmentMode::Generic;
  }
  [[nodiscard]] virtual std::unordered_map<std::uintptr_t, WorkspaceWindow>
  assignTaskbarWindows(const std::vector<TaskbarWindowCandidate>& /*windows*/, wl_output* /*output*/) const {
    return {};
  }
  [[nodiscard]] virtual std::vector<WorkspaceWindow> workspaceWindows(wl_output* /*output*/) const { return {}; }
  virtual void cleanup() = 0;

  [[nodiscard]] virtual int pollFd() const noexcept { return -1; }
  [[nodiscard]] virtual short pollEvents() const noexcept { return POLLIN | POLLHUP | POLLERR; }
  [[nodiscard]] virtual int pollTimeoutMs() const noexcept { return -1; }
  virtual void dispatchPoll(short /*revents*/) {}
};

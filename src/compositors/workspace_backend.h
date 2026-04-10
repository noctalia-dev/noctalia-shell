#pragma once

#include <cstdint>
#include <functional>
#include <poll.h>
#include <string>
#include <vector>

struct wl_output;

struct Workspace {
  std::string id;
  std::string name;
  std::vector<std::uint32_t> coordinates;
  bool active = false;
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
  virtual void cleanup() = 0;

  virtual void onOutputAdded(wl_output* /*output*/) {}
  virtual void onOutputRemoved(wl_output* /*output*/) {}

  [[nodiscard]] virtual int pollFd() const noexcept { return -1; }
  [[nodiscard]] virtual short pollEvents() const noexcept { return POLLIN | POLLHUP | POLLERR; }
  [[nodiscard]] virtual int pollTimeoutMs() const noexcept { return -1; }
  virtual void dispatchPoll(short /*revents*/) {}
};

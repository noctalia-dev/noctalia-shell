#pragma once

#include "compositors/workspace_backend.h"

#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

class SwayWorkspaceBackend final : public WorkspaceBackend {
public:
  using OutputNameResolver = std::function<std::string(wl_output*)>;

  explicit SwayWorkspaceBackend(OutputNameResolver outputNameResolver);

  bool connectSocket();
  void setOutputNameResolver(OutputNameResolver outputNameResolver);

  [[nodiscard]] const char* backendName() const override { return "sway-ipc"; }
  [[nodiscard]] bool isAvailable() const noexcept override { return m_socketFd >= 0; }
  void setChangeCallback(ChangeCallback callback) override;
  void activate(const std::string& id) override;
  void activateForOutput(wl_output* output, const std::string& id) override;
  void activateForOutput(wl_output* output, const Workspace& workspace) override;
  [[nodiscard]] std::vector<Workspace> all() const override;
  [[nodiscard]] std::vector<Workspace> forOutput(wl_output* output) const override;
  void cleanup() override;

  [[nodiscard]] int pollFd() const noexcept override { return m_socketFd; }
  void dispatchPoll(short revents) override;

private:
  struct SwayWorkspace {
    std::string name;
    std::string output;
    bool visible = false;
    bool urgent = false;
    bool occupied = false;
    int num = -1;
    std::size_t ordinal = 0;
  };

  void requestSnapshot();
  void sendMessage(std::uint32_t type, const std::string& payload);
  void readSocket();
  void parseMessages();
  void handleMessage(std::uint32_t type, const std::string& payload);
  void parseWorkspaceList(const std::string& payload);
  void parseTree(const std::string& payload);
  void refreshFromWorkspaceEvent();
  [[nodiscard]] static Workspace toWorkspace(const SwayWorkspace& workspace);
  [[nodiscard]] static std::string quoteCommandArg(const std::string& value);

  OutputNameResolver m_outputNameResolver;
  int m_socketFd = -1;
  std::vector<char> m_readBuffer;
  std::vector<SwayWorkspace> m_workspaces;
  std::unordered_map<std::string, std::size_t> m_workspaceOccupancy;
  ChangeCallback m_changeCallback;
};

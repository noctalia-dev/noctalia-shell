#pragma once

#include "compositors/workspace_backend.h"

#include <json.hpp>

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <poll.h>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class NiriWorkspaceMonitor {
public:
  using ChangeCallback = std::function<void()>;

  explicit NiriWorkspaceMonitor(std::string_view compositorHint);
  ~NiriWorkspaceMonitor();

  NiriWorkspaceMonitor(const NiriWorkspaceMonitor&) = delete;
  NiriWorkspaceMonitor& operator=(const NiriWorkspaceMonitor&) = delete;

  void setChangeCallback(ChangeCallback callback);
  [[nodiscard]] bool isEnabled() const noexcept { return m_enabled; }
  [[nodiscard]] int pollFd() const noexcept { return m_socketFd; }
  [[nodiscard]] short pollEvents() const noexcept { return POLLIN | POLLHUP | POLLERR; }
  [[nodiscard]] int pollTimeoutMs() const noexcept;
  void dispatchPoll(short revents);
  void apply(std::vector<Workspace>& workspaces, const std::string& outputName = {}) const;
  void cleanup();

private:
  struct WindowState {
    std::optional<std::uint64_t> workspaceId;

    bool operator==(const WindowState&) const = default;
  };

  struct WorkspaceState {
    std::uint64_t id = 0;
    std::uint8_t idx = 0;
    std::string name;
    std::string output;

    bool operator==(const WorkspaceState&) const = default;
  };

  void connectIfNeeded();
  void closeSocket(bool scheduleReconnect);
  void scheduleReconnect();
  void readSocket();
  void parseMessages();
  [[nodiscard]] bool handleMessage(std::string_view line);
  [[nodiscard]] bool handleWorkspacesChanged(const nlohmann::json& payload);
  [[nodiscard]] bool handleWindowsChanged(const nlohmann::json& payload);
  [[nodiscard]] bool handleWindowOpenedOrChanged(const nlohmann::json& payload);
  [[nodiscard]] bool handleWindowClosed(const nlohmann::json& payload);
  [[nodiscard]] static std::optional<WorkspaceState> parseWorkspace(const nlohmann::json& json);
  [[nodiscard]] static std::optional<std::pair<std::uint64_t, WindowState>>
  parseWindow(const nlohmann::json& json);
  [[nodiscard]] static std::optional<std::uint64_t> parseUnsigned(const std::string& value);
  [[nodiscard]] static std::optional<std::size_t> parseLeadingNumber(const std::string& value);
  void recomputeOccupancy();
  void notifyChanged() const;

  bool m_enabled = false;
  int m_socketFd = -1;
  std::optional<std::string> m_socketPath;
  std::vector<char> m_readBuffer;
  std::unordered_map<std::uint64_t, WindowState> m_windows;
  std::unordered_map<std::uint64_t, std::size_t> m_occupancy;
  std::unordered_map<std::uint64_t, WorkspaceState> m_workspaces;
  std::chrono::steady_clock::time_point m_nextReconnectAt{};
  ChangeCallback m_changeCallback;
};

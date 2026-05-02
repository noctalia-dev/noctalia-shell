#include "compositors/hyprland/hyprland_workspace_backend.h"

#include "core/log.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <charconv>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <format>
#include <string_view>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <unordered_set>

namespace {

  constexpr Logger kLog("workspace_hyprland");

  [[nodiscard]] std::optional<std::size_t> parseLeadingNumber(const std::string& value) {
    if (value.empty() || !std::isdigit(static_cast<unsigned char>(value.front()))) {
      return std::nullopt;
    }

    std::size_t parsed = 0;
    std::size_t index = 0;
    while (index < value.size() && std::isdigit(static_cast<unsigned char>(value[index]))) {
      parsed = (parsed * 10) + static_cast<std::size_t>(value[index] - '0');
      ++index;
    }
    return parsed > 0 ? std::optional<std::size_t>(parsed) : std::nullopt;
  }

} // namespace

HyprlandWorkspaceBackend::HyprlandWorkspaceBackend(OutputNameResolver outputNameResolver)
    : m_outputNameResolver(std::move(outputNameResolver)) {}

void HyprlandWorkspaceBackend::setOutputNameResolver(OutputNameResolver outputNameResolver) {
  m_outputNameResolver = std::move(outputNameResolver);
}

bool HyprlandWorkspaceBackend::ensureSocketPaths() {
  if (!m_requestSocketPath.empty() && !m_eventSocketPath.empty()) {
    return true;
  }

  const char* signature = std::getenv("HYPRLAND_INSTANCE_SIGNATURE");
  if (signature == nullptr || signature[0] == '\0') {
    return false;
  }

  std::string hyprDir;
  const char* runtimeDir = std::getenv("XDG_RUNTIME_DIR");
  if (runtimeDir != nullptr && runtimeDir[0] != '\0') {
    hyprDir = std::string(runtimeDir) + "/hypr/" + signature;
  }

  if (hyprDir.empty() || !std::filesystem::is_directory(hyprDir)) {
    hyprDir = std::string("/tmp/hypr/") + signature;
  }

  if (!std::filesystem::is_directory(hyprDir)) {
    return false;
  }

  m_requestSocketPath = hyprDir + "/.socket.sock";
  m_eventSocketPath = hyprDir + "/.socket2.sock";
  return true;
}

bool HyprlandWorkspaceBackend::connectSocket() {
  if (!ensureSocketPaths()) {
    return false;
  }

  cleanup();

  m_eventSocketFd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (m_eventSocketFd < 0) {
    kLog.warn("failed to create hyprland IPC socket: {}", std::strerror(errno));
    return false;
  }

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (m_eventSocketPath.size() >= sizeof(addr.sun_path)) {
    kLog.warn("hyprland IPC socket path too long");
    cleanup();
    return false;
  }
  std::memcpy(addr.sun_path, m_eventSocketPath.c_str(), m_eventSocketPath.size() + 1);

  if (::connect(m_eventSocketFd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    kLog.warn("failed to connect to hyprland IPC {}: {}", m_eventSocketPath, std::strerror(errno));
    cleanup();
    return false;
  }

  const int flags = ::fcntl(m_eventSocketFd, F_GETFL, 0);
  if (flags >= 0) {
    (void)::fcntl(m_eventSocketFd, F_SETFL, flags | O_NONBLOCK);
  }

  refreshSnapshot();
  kLog.info("connected to hyprland IPC at {}", m_eventSocketPath);
  return true;
}

void HyprlandWorkspaceBackend::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void HyprlandWorkspaceBackend::activate(const std::string& id) {
  if (id.empty() || !ensureSocketPaths()) {
    return;
  }

  std::string response;
  (void)sendRequest(std::format("dispatch workspace {}", id), response);
}

void HyprlandWorkspaceBackend::activateForOutput(wl_output* /*output*/, const std::string& id) { activate(id); }

void HyprlandWorkspaceBackend::activateForOutput(wl_output* /*output*/, const Workspace& workspace) {
  if (!workspace.name.empty()) {
    activate(workspace.name);
    return;
  }
  activate(workspace.id);
}

std::vector<Workspace> HyprlandWorkspaceBackend::all() const {
  std::vector<const WorkspaceState*> ordered;
  ordered.reserve(m_workspaces.size());
  for (const auto& workspace : m_workspaces) {
    ordered.push_back(&workspace);
  }

  std::sort(ordered.begin(), ordered.end(), [](const WorkspaceState* a, const WorkspaceState* b) {
    const bool aHasId = a->id >= 0;
    const bool bHasId = b->id >= 0;
    if (aHasId != bHasId) {
      return aHasId;
    }
    if (aHasId && bHasId && a->id != b->id) {
      return a->id < b->id;
    }
    const auto aNum = parseLeadingNumber(a->name);
    const auto bNum = parseLeadingNumber(b->name);
    if (aNum.has_value() && bNum.has_value() && aNum != bNum) {
      return aNum < bNum;
    }
    return a->ordinal < b->ordinal;
  });

  std::vector<Workspace> result;
  result.reserve(ordered.size());
  for (const auto* workspace : ordered) {
    result.push_back(toWorkspace(*workspace));
  }
  return result;
}

std::vector<Workspace> HyprlandWorkspaceBackend::forOutput(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (outputName.empty()) {
    return {};
  }

  std::vector<const WorkspaceState*> ordered;
  for (const auto& workspace : m_workspaces) {
    if (workspace.monitor == outputName) {
      ordered.push_back(&workspace);
    }
  }

  std::sort(ordered.begin(), ordered.end(), [](const WorkspaceState* a, const WorkspaceState* b) {
    const bool aHasId = a->id >= 0;
    const bool bHasId = b->id >= 0;
    if (aHasId != bHasId) {
      return aHasId;
    }
    if (aHasId && bHasId && a->id != b->id) {
      return a->id < b->id;
    }
    const auto aNum = parseLeadingNumber(a->name);
    const auto bNum = parseLeadingNumber(b->name);
    if (aNum.has_value() && bNum.has_value() && aNum != bNum) {
      return aNum < bNum;
    }
    return a->ordinal < b->ordinal;
  });

  std::vector<Workspace> result;
  result.reserve(ordered.size());
  for (const auto* workspace : ordered) {
    result.push_back(toWorkspace(*workspace));
  }
  return result;
}

std::unordered_map<std::string, std::vector<std::string>>
HyprlandWorkspaceBackend::appIdsByWorkspace(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (output != nullptr && outputName.empty()) {
    return {};
  }

  std::unordered_map<std::string, std::vector<std::string>> byWorkspace;
  std::unordered_map<std::string, std::unordered_set<std::string>> seenPerWorkspace;
  for (const auto& [address, toplevel] : m_toplevels) {
    if (toplevel.workspace.empty() || toplevel.appId.empty()) {
      continue;
    }
    if (!outputName.empty()) {
      bool workspaceOnOutput = false;
      for (const auto& workspace : m_workspaces) {
        if (workspace.name == toplevel.workspace && workspace.monitor == outputName) {
          workspaceOnOutput = true;
          break;
        }
      }
      if (!workspaceOnOutput) {
        continue;
      }
    }
    auto& seen = seenPerWorkspace[toplevel.workspace];
    if (!seen.insert(toplevel.appId).second) {
      continue;
    }
    byWorkspace[toplevel.workspace].push_back(toplevel.appId);
  }
  return byWorkspace;
}

std::vector<WorkspaceWindow> HyprlandWorkspaceBackend::workspaceWindows(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (output != nullptr && outputName.empty()) {
    return {};
  }

  std::unordered_map<std::string, std::string> keysByWorkspace;
  for (const auto& workspace : m_workspaces) {
    if (!outputName.empty() && workspace.monitor != outputName) {
      continue;
    }
    if (workspace.id > 0) {
      keysByWorkspace[workspace.name] = std::to_string(workspace.id);
    } else if (const auto parsed = parseLeadingNumber(workspace.name); parsed.has_value()) {
      keysByWorkspace[workspace.name] = std::to_string(*parsed);
    } else {
      keysByWorkspace[workspace.name] = workspace.name;
    }
  }

  std::vector<WorkspaceWindow> result;
  result.reserve(m_toplevels.size());
  for (const auto& [address, toplevel] : m_toplevels) {
    if (toplevel.workspace.empty() || toplevel.appId.empty()) {
      continue;
    }
    const auto keyIt = keysByWorkspace.find(toplevel.workspace);
    if (keyIt == keysByWorkspace.end()) {
      continue;
    }
    result.push_back(WorkspaceWindow{
        .windowId = std::to_string(address),
        .workspaceKey = keyIt->second,
        .appId = toplevel.appId,
        .title = toplevel.title,
    });
  }
  return result;
}

void HyprlandWorkspaceBackend::cleanup() {
  if (m_eventSocketFd >= 0) {
    ::close(m_eventSocketFd);
    m_eventSocketFd = -1;
  }
  m_readBuffer.clear();
  m_workspaces.clear();
  m_toplevels.clear();
  m_activeWorkspaceByMonitor.clear();
  m_focusedMonitor.clear();
  m_nextOrdinal = 0;
}

void HyprlandWorkspaceBackend::dispatchPoll(short revents) {
  if (m_eventSocketFd < 0) {
    return;
  }
  if ((revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
    kLog.warn("hyprland IPC disconnected");
    cleanup();
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }
  if ((revents & POLLIN) != 0) {
    readSocket();
  }
}

bool HyprlandWorkspaceBackend::sendRequest(const std::string& request, std::string& response) const {
  if (m_requestSocketPath.empty()) {
    return false;
  }

  const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return false;
  }

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (m_requestSocketPath.size() >= sizeof(addr.sun_path)) {
    ::close(fd);
    return false;
  }
  std::memcpy(addr.sun_path, m_requestSocketPath.c_str(), m_requestSocketPath.size() + 1);

  if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    ::close(fd);
    return false;
  }

  std::size_t offset = 0;
  while (offset < request.size()) {
    const ssize_t written = ::send(fd, request.data() + offset, request.size() - offset, MSG_NOSIGNAL);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      ::close(fd);
      return false;
    }
    offset += static_cast<std::size_t>(written);
  }

  ::shutdown(fd, SHUT_WR);

  std::string out;
  char buffer[4096];
  while (true) {
    const ssize_t n = ::recv(fd, buffer, sizeof(buffer), 0);
    if (n > 0) {
      out.append(buffer, buffer + n);
      continue;
    }
    if (n == 0) {
      break;
    }
    if (errno == EINTR) {
      continue;
    }
    ::close(fd);
    return false;
  }

  ::close(fd);
  response = std::move(out);
  return true;
}

std::optional<nlohmann::json> HyprlandWorkspaceBackend::requestJson(const std::string& request) const {
  std::string response;
  if (!sendRequest(request, response) || response.empty()) {
    return std::nullopt;
  }
  try {
    return nlohmann::json::parse(response);
  } catch (const nlohmann::json::exception& e) {
    kLog.warn("failed to parse hyprland response for {}: {}", request, e.what());
    return std::nullopt;
  }
}

void HyprlandWorkspaceBackend::refreshSnapshot() {
  refreshWorkspaces();
  refreshMonitors();
  refreshClients();
  recomputeWorkspaceFlags();
  notifyChanged();
}

void HyprlandWorkspaceBackend::refreshWorkspaces() {
  const auto json = requestJson("j/workspaces");
  if (!json || !json->is_array()) {
    return;
  }

  std::unordered_map<int, std::size_t> ordinalsById;
  std::unordered_map<std::string, std::size_t> ordinalsByName;
  for (const auto& workspace : m_workspaces) {
    if (workspace.id >= 0) {
      ordinalsById[workspace.id] = workspace.ordinal;
    } else if (!workspace.name.empty()) {
      ordinalsByName[workspace.name] = workspace.ordinal;
    }
  }

  std::vector<WorkspaceState> next;
  next.reserve(json->size());
  for (const auto& item : *json) {
    if (!item.is_object()) {
      continue;
    }
    WorkspaceState workspace;
    workspace.id = item.value("id", -1);
    workspace.name = item.value("name", "");
    workspace.monitor = item.value("monitor", "");
    if (workspace.name.empty()) {
      continue;
    }
    if (workspace.id >= 0) {
      if (const auto it = ordinalsById.find(workspace.id); it != ordinalsById.end()) {
        workspace.ordinal = it->second;
      } else {
        workspace.ordinal = m_nextOrdinal++;
      }
    } else if (const auto it = ordinalsByName.find(workspace.name); it != ordinalsByName.end()) {
      workspace.ordinal = it->second;
    } else {
      workspace.ordinal = m_nextOrdinal++;
    }
    next.push_back(std::move(workspace));
  }

  m_workspaces = std::move(next);
}

void HyprlandWorkspaceBackend::refreshMonitors() {
  const auto json = requestJson("j/monitors");
  if (!json || !json->is_array()) {
    return;
  }

  std::unordered_map<std::string, std::string> activeByMonitor;
  for (const auto& item : *json) {
    if (!item.is_object()) {
      continue;
    }
    const std::string monitorName = item.value("name", "");
    if (monitorName.empty()) {
      continue;
    }

    if (const auto it = item.find("focused"); it != item.end() && it->is_boolean() && it->get<bool>()) {
      m_focusedMonitor = monitorName;
    }

    std::string activeWorkspace;
    const auto activeIt = item.find("activeWorkspace");
    if (activeIt != item.end()) {
      if (activeIt->is_object()) {
        activeWorkspace = activeIt->value("name", "");
      } else if (activeIt->is_string()) {
        activeWorkspace = activeIt->get<std::string>();
      }
    }
    if (!activeWorkspace.empty()) {
      activeByMonitor[monitorName] = activeWorkspace;
    }
  }

  if (!activeByMonitor.empty()) {
    m_activeWorkspaceByMonitor = std::move(activeByMonitor);
  }
}

void HyprlandWorkspaceBackend::refreshClients() {
  const auto json = requestJson("j/clients");
  if (!json || !json->is_array()) {
    return;
  }

  std::unordered_map<std::uint64_t, ToplevelState> next;
  next.reserve(json->size());

  for (const auto& item : *json) {
    if (!item.is_object()) {
      continue;
    }

    std::string addressStr;
    if (const auto it = item.find("address"); it != item.end()) {
      if (it->is_string()) {
        addressStr = it->get<std::string>();
      } else if (it->is_number_unsigned()) {
        addressStr = std::format("{:x}", it->get<std::uint64_t>());
      }
    }

    const auto address = parseHexAddress(addressStr);
    if (!address.has_value()) {
      continue;
    }

    ToplevelState state;
    if (const auto wsIt = item.find("workspace"); wsIt != item.end() && wsIt->is_object()) {
      state.workspace = wsIt->value("name", "");
    } else {
      state.workspace = item.value("workspace", "");
    }
    state.appId = item.value("class", "");
    if (state.appId.empty()) {
      state.appId = item.value("initialClass", "");
    }
    state.title = item.value("title", "");

    bool urgent = false;
    bool urgentSet = false;
    if (const auto urgentIt = item.find("urgent"); urgentIt != item.end() && urgentIt->is_boolean()) {
      urgent = urgentIt->get<bool>();
      urgentSet = true;
    }

    if (!urgentSet) {
      if (const auto existing = m_toplevels.find(*address); existing != m_toplevels.end()) {
        urgent = existing->second.urgent;
      }
    }

    state.urgent = urgent;
    next.emplace(*address, std::move(state));
  }

  m_toplevels = std::move(next);
}

void HyprlandWorkspaceBackend::recomputeWorkspaceFlags() {
  std::unordered_map<std::string, std::size_t> occupiedCounts;
  std::unordered_map<std::string, bool> urgentByWorkspace;

  for (const auto& [_, toplevel] : m_toplevels) {
    if (toplevel.workspace.empty()) {
      continue;
    }
    ++occupiedCounts[toplevel.workspace];
    if (toplevel.urgent) {
      urgentByWorkspace[toplevel.workspace] = true;
    }
  }

  for (auto& workspace : m_workspaces) {
    auto occIt = occupiedCounts.find(workspace.name);
    workspace.occupied = occIt != occupiedCounts.end() && occIt->second > 0;
    workspace.urgent = urgentByWorkspace.contains(workspace.name);
    if (!workspace.monitor.empty()) {
      const auto activeIt = m_activeWorkspaceByMonitor.find(workspace.monitor);
      workspace.active = activeIt != m_activeWorkspaceByMonitor.end() && activeIt->second == workspace.name;
    } else {
      workspace.active = false;
    }
  }
}

void HyprlandWorkspaceBackend::notifyChanged() const {
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void HyprlandWorkspaceBackend::readSocket() {
  char buffer[4096];
  while (true) {
    const ssize_t n = ::recv(m_eventSocketFd, buffer, sizeof(buffer), MSG_DONTWAIT);
    if (n > 0) {
      m_readBuffer.insert(m_readBuffer.end(), buffer, buffer + n);
      continue;
    }
    if (n == 0) {
      cleanup();
      if (m_changeCallback) {
        m_changeCallback();
      }
      return;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      break;
    }
    if (errno == EINTR) {
      continue;
    }
    kLog.warn("failed to read from hyprland IPC: {}", std::strerror(errno));
    cleanup();
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }

  parseMessages();
}

void HyprlandWorkspaceBackend::parseMessages() {
  while (true) {
    auto it = std::find(m_readBuffer.begin(), m_readBuffer.end(), '\n');
    if (it == m_readBuffer.end()) {
      return;
    }
    std::string line(m_readBuffer.begin(), it);
    m_readBuffer.erase(m_readBuffer.begin(), it + 1);
    if (!line.empty()) {
      handleEvent(line);
    }
  }
}

void HyprlandWorkspaceBackend::handleEvent(std::string_view line) {
  const auto split = line.find(">>");
  if (split == std::string_view::npos) {
    return;
  }

  const std::string_view event = line.substr(0, split);
  const std::string_view data = line.substr(split + 2);

  if (event == "configreloaded") {
    refreshSnapshot();
    return;
  }

  if (event == "focusedmon") {
    const auto args = parseEventArgs(data, 2);
    handleFocusedMonitor(args[0], args[1]);
    return;
  }

  if (event == "workspacev2") {
    const auto args = parseEventArgs(data, 2);
    handleWorkspaceActivated(args[1]);
    return;
  }

  if (event == "createworkspacev2") {
    const auto args = parseEventArgs(data, 2);
    const auto id = parseInt(args[0]);
    const std::string name(args[1]);
    if (!id.has_value() || name.empty()) {
      return;
    }
    auto* workspace = findWorkspaceById(*id);
    if (workspace == nullptr) {
      WorkspaceState state;
      state.id = *id;
      state.name = name;
      state.ordinal = m_nextOrdinal++;
      m_workspaces.push_back(std::move(state));
    } else {
      workspace->name = name;
    }
    refreshWorkspaces();
    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "destroyworkspacev2") {
    const auto args = parseEventArgs(data, 2);
    const auto id = parseInt(args[0]);
    const std::string name(args[1]);
    if (!id.has_value() && name.empty()) {
      return;
    }
    m_workspaces.erase(std::remove_if(m_workspaces.begin(), m_workspaces.end(),
                                      [&](const WorkspaceState& ws) {
                                        return (id.has_value() && ws.id == *id) || (!name.empty() && ws.name == name);
                                      }),
                       m_workspaces.end());

    for (auto it = m_toplevels.begin(); it != m_toplevels.end();) {
      if (!name.empty() && it->second.workspace == name) {
        it = m_toplevels.erase(it);
      } else {
        ++it;
      }
    }

    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "renameworkspace") {
    const auto args = parseEventArgs(data, 2);
    const auto id = parseInt(args[0]);
    const std::string newName(args[1]);
    if (!id.has_value() || newName.empty()) {
      return;
    }
    auto* workspace = findWorkspaceById(*id);
    if (workspace == nullptr) {
      refreshWorkspaces();
      recomputeWorkspaceFlags();
      notifyChanged();
      return;
    }
    const std::string oldName = workspace->name;
    workspace->name = newName;

    for (auto& [_, toplevel] : m_toplevels) {
      if (toplevel.workspace == oldName) {
        toplevel.workspace = newName;
      }
    }

    for (auto& [monitorName, activeWorkspace] : m_activeWorkspaceByMonitor) {
      if (activeWorkspace == oldName) {
        activeWorkspace = newName;
      }
    }

    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "moveworkspacev2") {
    const auto args = parseEventArgs(data, 3);
    const auto id = parseInt(args[0]);
    const std::string name(args[1]);
    const std::string monitor(args[2]);
    if (!id.has_value()) {
      return;
    }
    auto* workspace = findWorkspaceById(*id);
    if (workspace == nullptr && !name.empty()) {
      workspace = findWorkspaceByName(name);
    }
    if (workspace != nullptr && !monitor.empty()) {
      workspace->monitor = monitor;
      recomputeWorkspaceFlags();
      notifyChanged();
    }
    return;
  }

  if (event == "openwindow") {
    const auto args = parseEventArgs(data, 4);
    const auto address = parseHexAddress(args[0]);
    if (!address.has_value()) {
      return;
    }
    moveToplevel(*address, args[1]);
    if (auto it = m_toplevels.find(*address); it != m_toplevels.end()) {
      it->second.appId = std::string(args[2]);
      it->second.title = std::string(args[3]);
    }
    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "closewindow") {
    const auto args = parseEventArgs(data, 1);
    const auto address = parseHexAddress(args[0]);
    if (!address.has_value()) {
      return;
    }
    m_toplevels.erase(*address);
    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "movewindowv2") {
    const auto args = parseEventArgs(data, 3);
    const auto address = parseHexAddress(args[0]);
    if (!address.has_value()) {
      return;
    }
    moveToplevel(*address, args[2]);
    recomputeWorkspaceFlags();
    notifyChanged();
    return;
  }

  if (event == "urgent") {
    const auto args = parseEventArgs(data, 1);
    const auto address = parseHexAddress(args[0]);
    if (!address.has_value()) {
      return;
    }
    auto it = m_toplevels.find(*address);
    if (it == m_toplevels.end()) {
      m_toplevels.emplace(*address, ToplevelState{.workspace = {}, .appId = {}, .title = {}, .urgent = true});
      refreshClients();
    } else {
      it->second.urgent = true;
    }
    recomputeWorkspaceFlags();
    notifyChanged();
  }
}

void HyprlandWorkspaceBackend::handleFocusedMonitor(std::string_view monitorName, std::string_view workspaceName) {
  if (monitorName.empty()) {
    return;
  }
  m_focusedMonitor = std::string(monitorName);
  if (!workspaceName.empty()) {
    m_activeWorkspaceByMonitor[m_focusedMonitor] = std::string(workspaceName);
    clearUrgentForWorkspace(workspaceName);
  }
  recomputeWorkspaceFlags();
  notifyChanged();
}

void HyprlandWorkspaceBackend::handleWorkspaceActivated(std::string_view workspaceName) {
  if (m_focusedMonitor.empty() || workspaceName.empty()) {
    return;
  }
  m_activeWorkspaceByMonitor[m_focusedMonitor] = std::string(workspaceName);
  clearUrgentForWorkspace(workspaceName);
  recomputeWorkspaceFlags();
  notifyChanged();
}

void HyprlandWorkspaceBackend::clearUrgentForWorkspace(std::string_view workspaceName) {
  if (workspaceName.empty()) {
    return;
  }
  for (auto& [_, toplevel] : m_toplevels) {
    if (toplevel.workspace == workspaceName) {
      toplevel.urgent = false;
    }
  }
}

void HyprlandWorkspaceBackend::moveToplevel(std::uint64_t address, std::string_view workspaceName) {
  auto& toplevel = m_toplevels[address];
  toplevel.workspace = std::string(workspaceName);
}

HyprlandWorkspaceBackend::WorkspaceState* HyprlandWorkspaceBackend::findWorkspaceById(int id) {
  for (auto& workspace : m_workspaces) {
    if (workspace.id == id) {
      return &workspace;
    }
  }
  return nullptr;
}

HyprlandWorkspaceBackend::WorkspaceState* HyprlandWorkspaceBackend::findWorkspaceByName(std::string_view name) {
  if (name.empty()) {
    return nullptr;
  }
  for (auto& workspace : m_workspaces) {
    if (workspace.name == name) {
      return &workspace;
    }
  }
  return nullptr;
}

std::optional<std::uint64_t> HyprlandWorkspaceBackend::parseHexAddress(std::string_view value) {
  if (value.empty()) {
    return std::nullopt;
  }
  if (value.starts_with("0x") || value.starts_with("0X")) {
    value = value.substr(2);
  }
  std::uint64_t address = 0;
  const auto* begin = value.data();
  const auto* end = value.data() + value.size();
  const auto [ptr, ec] = std::from_chars(begin, end, address, 16);
  if (ec != std::errc{} || ptr != end) {
    return std::nullopt;
  }
  return address;
}

std::optional<int> HyprlandWorkspaceBackend::parseInt(std::string_view value) {
  if (value.empty()) {
    return std::nullopt;
  }
  int parsed = 0;
  const auto* begin = value.data();
  const auto* end = value.data() + value.size();
  const auto [ptr, ec] = std::from_chars(begin, end, parsed);
  if (ec != std::errc{} || ptr != end) {
    return std::nullopt;
  }
  return parsed;
}

std::vector<std::string_view> HyprlandWorkspaceBackend::parseEventArgs(std::string_view data, std::size_t count) {
  std::vector<std::string_view> args;
  args.reserve(count);
  std::size_t start = 0;
  for (std::size_t i = 0; i + 1 < count; ++i) {
    const auto split = data.find(',', start);
    if (split == std::string_view::npos) {
      break;
    }
    args.push_back(data.substr(start, split - start));
    start = split + 1;
  }
  if (start <= data.size()) {
    args.push_back(data.substr(start));
  }
  while (args.size() < count) {
    args.push_back({});
  }
  return args;
}

std::string HyprlandWorkspaceBackend::quoteCommandArg(const std::string& value) {
  std::string escaped = "\"";
  for (const char c : value) {
    if (c == '\\' || c == '"') {
      escaped.push_back('\\');
    }
    escaped.push_back(c);
  }
  escaped.push_back('"');
  return escaped;
}

Workspace HyprlandWorkspaceBackend::toWorkspace(const WorkspaceState& state) {
  const std::uint32_t coord =
      state.id >= 0 ? static_cast<std::uint32_t>(state.id - 1) : static_cast<std::uint32_t>(state.ordinal);
  return Workspace{
      .id = !state.name.empty() ? state.name : std::to_string(state.id),
      .name = state.name,
      .coordinates = {coord},
      .active = state.active,
      .urgent = state.urgent,
      .occupied = state.occupied,
  };
}

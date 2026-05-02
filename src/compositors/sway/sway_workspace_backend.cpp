#include "compositors/sway/sway_workspace_backend.h"

#include "core/log.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <format>
#include <json.hpp>
#include <span>
#include <stdexcept>
#include <string_view>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <unordered_set>

namespace {

  constexpr Logger kLog("workspace_sway");
  constexpr std::string_view kIpcMagic = "i3-ipc";
  constexpr std::uint32_t kIpcRunCommand = 0;
  constexpr std::uint32_t kIpcGetWorkspaces = 1;
  constexpr std::uint32_t kIpcSubscribe = 2;
  constexpr std::uint32_t kIpcGetTree = 4;
  constexpr std::uint32_t kIpcWorkspaceEvent = 0x80000000u;
  constexpr std::uint32_t kIpcWindowEvent = 0x80000003u;

  void tallyWorkspaceWindows(const nlohmann::json& node, const std::string& currentWorkspace,
                             std::unordered_map<std::string, std::size_t>& counts) {
    if (!node.is_object()) {
      return;
    }

    std::string workspaceName = currentWorkspace;
    if (const auto typeIt = node.find("type"); typeIt != node.end() && typeIt->is_string()) {
      if (typeIt->get<std::string>() == "workspace") {
        if (const auto nameIt = node.find("name"); nameIt != node.end() && nameIt->is_string()) {
          workspaceName = nameIt->get<std::string>();
        }
      }
    }

    const auto nodesIt = node.find("nodes");
    const auto floatingIt = node.find("floating_nodes");

    const bool hasNodes = nodesIt != node.end() && nodesIt->is_array();
    const bool hasFloating = floatingIt != node.end() && floatingIt->is_array();
    const bool isLeaf = (!hasNodes || nodesIt->empty()) && (!hasFloating || floatingIt->empty());

    bool hasWindow = false;
    if (const auto windowIt = node.find("window"); windowIt != node.end() && !windowIt->is_null()) {
      hasWindow = true;
    } else if (const auto appIdIt = node.find("app_id"); appIdIt != node.end() && appIdIt->is_string()) {
      hasWindow = !appIdIt->get<std::string>().empty();
    }

    if (isLeaf && hasWindow && !workspaceName.empty()) {
      ++counts[workspaceName];
    }

    if (hasNodes) {
      for (const auto& child : *nodesIt) {
        tallyWorkspaceWindows(child, workspaceName, counts);
      }
    }
    if (hasFloating) {
      for (const auto& child : *floatingIt) {
        tallyWorkspaceWindows(child, workspaceName, counts);
      }
    }
  }

  void collectWorkspaceApps(const nlohmann::json& node, const std::string& currentWorkspace,
                            std::unordered_map<std::string, std::vector<std::string>>& appIdsByWorkspace,
                            std::unordered_map<std::string, std::unordered_set<std::string>>& seenPerWorkspace) {
    if (!node.is_object()) {
      return;
    }

    std::string workspaceName = currentWorkspace;
    if (const auto typeIt = node.find("type"); typeIt != node.end() && typeIt->is_string()) {
      if (typeIt->get<std::string>() == "workspace") {
        if (const auto nameIt = node.find("name"); nameIt != node.end() && nameIt->is_string()) {
          workspaceName = nameIt->get<std::string>();
        }
      }
    }

    std::string appId;
    if (const auto appIdIt = node.find("app_id"); appIdIt != node.end() && appIdIt->is_string()) {
      appId = appIdIt->get<std::string>();
    }
    if (appId.empty()) {
      if (const auto propsIt = node.find("window_properties"); propsIt != node.end() && propsIt->is_object()) {
        const auto classIt = propsIt->find("class");
        if (classIt != propsIt->end() && classIt->is_string()) {
          appId = classIt->get<std::string>();
        }
      }
    }
    if (!workspaceName.empty() && !appId.empty()) {
      auto& seen = seenPerWorkspace[workspaceName];
      if (seen.insert(appId).second) {
        appIdsByWorkspace[workspaceName].push_back(appId);
      }
    }

    const auto nodesIt = node.find("nodes");
    if (nodesIt != node.end() && nodesIt->is_array()) {
      for (const auto& child : *nodesIt) {
        collectWorkspaceApps(child, workspaceName, appIdsByWorkspace, seenPerWorkspace);
      }
    }
    const auto floatingIt = node.find("floating_nodes");
    if (floatingIt != node.end() && floatingIt->is_array()) {
      for (const auto& child : *floatingIt) {
        collectWorkspaceApps(child, workspaceName, appIdsByWorkspace, seenPerWorkspace);
      }
    }
  }

  void collectWorkspaceWindows(const nlohmann::json& node, const std::string& currentWorkspace,
                               const std::string& currentWorkspaceKey, std::vector<WorkspaceWindow>& windows) {
    if (!node.is_object()) {
      return;
    }

    std::string workspaceName = currentWorkspace;
    std::string workspaceKey = currentWorkspaceKey;
    if (const auto typeIt = node.find("type"); typeIt != node.end() && typeIt->is_string()) {
      if (typeIt->get<std::string>() == "workspace") {
        if (const auto nameIt = node.find("name"); nameIt != node.end() && nameIt->is_string()) {
          workspaceName = nameIt->get<std::string>();
        }
        if (const auto numIt = node.find("num"); numIt != node.end() && numIt->is_number_integer()) {
          const int num = numIt->get<int>();
          workspaceKey = num > 0 ? std::to_string(num) : workspaceName;
        } else {
          workspaceKey = workspaceName;
        }
      }
    }

    std::string appId;
    if (const auto appIdIt = node.find("app_id"); appIdIt != node.end() && appIdIt->is_string()) {
      appId = appIdIt->get<std::string>();
    }
    if (appId.empty()) {
      if (const auto propsIt = node.find("window_properties"); propsIt != node.end() && propsIt->is_object()) {
        const auto classIt = propsIt->find("class");
        if (classIt != propsIt->end() && classIt->is_string()) {
          appId = classIt->get<std::string>();
        }
      }
    }

    const auto nodesIt = node.find("nodes");
    const auto floatingIt = node.find("floating_nodes");
    const bool hasNodes = nodesIt != node.end() && nodesIt->is_array();
    const bool hasFloating = floatingIt != node.end() && floatingIt->is_array();
    const bool isLeaf = (!hasNodes || nodesIt->empty()) && (!hasFloating || floatingIt->empty());
    std::string windowId;
    if (const auto idIt = node.find("id"); idIt != node.end() && idIt->is_number_integer()) {
      windowId = std::to_string(idIt->get<std::int64_t>());
    }
    if (isLeaf && !workspaceName.empty() && !workspaceKey.empty() && !appId.empty()) {
      windows.push_back(WorkspaceWindow{
          .windowId = windowId,
          .workspaceKey = workspaceKey,
          .appId = appId,
          .title = node.value("name", ""),
      });
    }

    if (hasNodes) {
      for (const auto& child : *nodesIt) {
        collectWorkspaceWindows(child, workspaceName, workspaceKey, windows);
      }
    }
    if (hasFloating) {
      for (const auto& child : *floatingIt) {
        collectWorkspaceWindows(child, workspaceName, workspaceKey, windows);
      }
    }
  }

  std::string socketPathFromEnv() {
    if (const char* swaySock = std::getenv("SWAYSOCK"); swaySock != nullptr && swaySock[0] != '\0') {
      return swaySock;
    }
    if (const char* i3Sock = std::getenv("I3SOCK"); i3Sock != nullptr && i3Sock[0] != '\0') {
      return i3Sock;
    }
    return {};
  }

} // namespace

SwayWorkspaceBackend::SwayWorkspaceBackend(OutputNameResolver outputNameResolver)
    : m_outputNameResolver(std::move(outputNameResolver)) {}

void SwayWorkspaceBackend::setOutputNameResolver(OutputNameResolver outputNameResolver) {
  m_outputNameResolver = std::move(outputNameResolver);
}

bool SwayWorkspaceBackend::connectSocket() {
  const std::string path = socketPathFromEnv();
  if (path.empty()) {
    return false;
  }

  cleanup();

  m_socketFd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (m_socketFd < 0) {
    kLog.warn("failed to create sway IPC socket: {}", std::strerror(errno));
    return false;
  }

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    kLog.warn("sway IPC socket path too long");
    cleanup();
    return false;
  }
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);

  if (::connect(m_socketFd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    kLog.warn("failed to connect to sway IPC {}: {}", path, std::strerror(errno));
    cleanup();
    return false;
  }

  sendMessage(kIpcSubscribe, R"(["workspace","window"])");
  requestSnapshot();
  kLog.info("connected to sway IPC at {}", path);
  return true;
}

void SwayWorkspaceBackend::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void SwayWorkspaceBackend::activate(const std::string& id) {
  if (m_socketFd < 0 || id.empty()) {
    return;
  }

  sendMessage(kIpcRunCommand, "workspace " + quoteCommandArg(id));
}

void SwayWorkspaceBackend::activateForOutput(wl_output* /*output*/, const std::string& id) { activate(id); }

void SwayWorkspaceBackend::activateForOutput(wl_output* /*output*/, const Workspace& workspace) {
  activate(workspace.id.empty() ? workspace.name : workspace.id);
}

std::vector<Workspace> SwayWorkspaceBackend::all() const {
  std::vector<Workspace> result;
  result.reserve(m_workspaces.size());
  for (const auto& workspace : m_workspaces) {
    result.push_back(toWorkspace(workspace));
  }
  return result;
}

std::vector<Workspace> SwayWorkspaceBackend::forOutput(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (outputName.empty()) {
    return {};
  }

  std::vector<Workspace> result;
  for (const auto& workspace : m_workspaces) {
    if (workspace.output == outputName) {
      result.push_back(toWorkspace(workspace));
    }
  }
  return result;
}

std::unordered_map<std::string, std::vector<std::string>>
SwayWorkspaceBackend::appIdsByWorkspace(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (output != nullptr && outputName.empty()) {
    return {};
  }
  if (outputName.empty()) {
    return m_workspaceApps;
  }

  std::unordered_set<std::string> workspaceNames;
  for (const auto& workspace : m_workspaces) {
    if (workspace.output == outputName) {
      workspaceNames.insert(workspace.name);
    }
  }

  std::unordered_map<std::string, std::vector<std::string>> filtered;
  for (const auto& [workspace, apps] : m_workspaceApps) {
    if (workspaceNames.contains(workspace)) {
      filtered.emplace(workspace, apps);
    }
  }
  return filtered;
}

std::vector<WorkspaceWindow> SwayWorkspaceBackend::workspaceWindows(wl_output* output) const {
  const std::string outputName = m_outputNameResolver != nullptr ? m_outputNameResolver(output) : std::string{};
  if (output != nullptr && outputName.empty()) {
    return {};
  }
  if (outputName.empty()) {
    return m_workspaceWindows;
  }

  std::unordered_set<std::string> workspaceKeys;
  for (const auto& workspace : m_workspaces) {
    if (workspace.output != outputName) {
      continue;
    }
    if (workspace.num > 0) {
      workspaceKeys.insert(std::to_string(workspace.num));
    } else if (!workspace.name.empty()) {
      workspaceKeys.insert(workspace.name);
    }
  }

  std::vector<WorkspaceWindow> filtered;
  for (const auto& window : m_workspaceWindows) {
    if (workspaceKeys.contains(window.workspaceKey)) {
      filtered.push_back(window);
    }
  }
  return filtered;
}

void SwayWorkspaceBackend::cleanup() {
  if (m_socketFd >= 0) {
    ::close(m_socketFd);
    m_socketFd = -1;
  }
  m_readBuffer.clear();
  m_workspaces.clear();
  m_workspaceApps.clear();
  m_workspaceWindows.clear();
}

void SwayWorkspaceBackend::dispatchPoll(short revents) {
  if (m_socketFd < 0) {
    return;
  }
  if ((revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
    kLog.warn("sway IPC disconnected");
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

void SwayWorkspaceBackend::requestSnapshot() {
  sendMessage(kIpcGetWorkspaces, "");
  sendMessage(kIpcGetTree, "");
}

void SwayWorkspaceBackend::requestTree() { sendMessage(kIpcGetTree, ""); }

void SwayWorkspaceBackend::sendMessage(std::uint32_t type, const std::string& payload) {
  if (m_socketFd < 0) {
    return;
  }

  const std::uint32_t payloadLength = static_cast<std::uint32_t>(payload.size());
  std::vector<char> message;
  message.reserve(kIpcMagic.size() + sizeof(payloadLength) + sizeof(type) + payload.size());
  message.insert(message.end(), kIpcMagic.begin(), kIpcMagic.end());
  const auto* lenBytes = reinterpret_cast<const char*>(&payloadLength);
  const auto* typeBytes = reinterpret_cast<const char*>(&type);
  message.insert(message.end(), lenBytes, lenBytes + sizeof(payloadLength));
  message.insert(message.end(), typeBytes, typeBytes + sizeof(type));
  message.insert(message.end(), payload.begin(), payload.end());

  std::size_t offset = 0;
  while (offset < message.size()) {
    const ssize_t written = ::send(m_socketFd, message.data() + offset, message.size() - offset, MSG_NOSIGNAL);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      kLog.warn("failed to send sway IPC message: {}", std::strerror(errno));
      cleanup();
      return;
    }
    offset += static_cast<std::size_t>(written);
  }
}

void SwayWorkspaceBackend::readSocket() {
  char buffer[8192];
  while (true) {
    const ssize_t n = ::recv(m_socketFd, buffer, sizeof(buffer), MSG_DONTWAIT);
    if (n > 0) {
      m_readBuffer.insert(m_readBuffer.end(), buffer, buffer + n);
      continue;
    }
    if (n == 0) {
      kLog.warn("sway IPC closed the connection");
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
    kLog.warn("failed to read from sway IPC: {}", std::strerror(errno));
    cleanup();
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }

  parseMessages();
}

void SwayWorkspaceBackend::parseMessages() {
  constexpr std::size_t kHeaderSize = 14;
  while (m_readBuffer.size() >= kHeaderSize) {
    if (!std::equal(kIpcMagic.begin(), kIpcMagic.end(), m_readBuffer.begin())) {
      kLog.warn("invalid sway IPC frame header");
      cleanup();
      if (m_changeCallback) {
        m_changeCallback();
      }
      return;
    }

    std::uint32_t payloadLength = 0;
    std::uint32_t type = 0;
    std::memcpy(&payloadLength, m_readBuffer.data() + kIpcMagic.size(), sizeof(payloadLength));
    std::memcpy(&type, m_readBuffer.data() + kIpcMagic.size() + sizeof(payloadLength), sizeof(type));
    if (m_readBuffer.size() < kHeaderSize + payloadLength) {
      return;
    }

    const std::string payload(m_readBuffer.begin() + static_cast<std::ptrdiff_t>(kHeaderSize),
                              m_readBuffer.begin() + static_cast<std::ptrdiff_t>(kHeaderSize + payloadLength));
    m_readBuffer.erase(m_readBuffer.begin(),
                       m_readBuffer.begin() + static_cast<std::ptrdiff_t>(kHeaderSize + payloadLength));
    handleMessage(type, payload);
  }
}

void SwayWorkspaceBackend::handleMessage(std::uint32_t type, const std::string& payload) {
  if (type == kIpcGetWorkspaces) {
    parseWorkspaceList(payload);
    return;
  }
  if (type == kIpcGetTree) {
    parseTree(payload);
    return;
  }
  if (type == kIpcWorkspaceEvent) {
    refreshFromWorkspaceEvent();
    return;
  }
  if (type == kIpcWindowEvent) {
    requestTree();
  }
}

void SwayWorkspaceBackend::parseWorkspaceList(const std::string& payload) {
  try {
    const auto json = nlohmann::json::parse(payload);
    if (!json.is_array()) {
      return;
    }

    std::vector<SwayWorkspace> next;
    next.reserve(json.size());
    std::size_t ordinal = 0;
    for (const auto& item : json) {
      if (!item.is_object()) {
        continue;
      }
      SwayWorkspace workspace;
      workspace.name = item.value("name", "");
      workspace.output = item.value("output", "");
      workspace.visible = item.value("visible", false);
      workspace.urgent = item.value("urgent", false);
      workspace.num = item.value("num", -1);
      workspace.ordinal = ordinal++;
      auto occupancy = m_workspaceOccupancy.find(workspace.name);
      workspace.occupied = occupancy != m_workspaceOccupancy.end() && occupancy->second > 0;
      if (!workspace.name.empty()) {
        next.push_back(std::move(workspace));
      }
    }

    std::sort(next.begin(), next.end(), [](const auto& a, const auto& b) {
      if ((a.num >= 0) != (b.num >= 0)) {
        return a.num >= 0;
      }
      if (a.num >= 0 && b.num >= 0 && a.num != b.num) {
        return a.num < b.num;
      }
      return a.ordinal < b.ordinal;
    });

    m_workspaces = std::move(next);
    if (m_changeCallback) {
      m_changeCallback();
    }
  } catch (const nlohmann::json::exception& e) {
    kLog.warn("failed to parse sway workspaces: {}", e.what());
  }
}

void SwayWorkspaceBackend::parseTree(const std::string& payload) {
  try {
    const auto json = nlohmann::json::parse(payload);
    if (!json.is_object()) {
      return;
    }

    std::unordered_map<std::string, std::size_t> occupancy;
    tallyWorkspaceWindows(json, std::string{}, occupancy);
    m_workspaceOccupancy = std::move(occupancy);
    std::unordered_map<std::string, std::vector<std::string>> appIdsByWorkspace;
    std::unordered_map<std::string, std::unordered_set<std::string>> seenPerWorkspace;
    collectWorkspaceApps(json, std::string{}, appIdsByWorkspace, seenPerWorkspace);
    m_workspaceApps = std::move(appIdsByWorkspace);
    std::vector<WorkspaceWindow> workspaceWindows;
    collectWorkspaceWindows(json, std::string{}, std::string{}, workspaceWindows);
    m_workspaceWindows = std::move(workspaceWindows);

    if (!m_workspaces.empty()) {
      for (auto& workspace : m_workspaces) {
        auto it = m_workspaceOccupancy.find(workspace.name);
        workspace.occupied = it != m_workspaceOccupancy.end() && it->second > 0;
      }
      if (m_changeCallback) {
        m_changeCallback();
      }
    }
  } catch (const nlohmann::json::exception& e) {
    kLog.warn("failed to parse sway tree: {}", e.what());
  }
}

void SwayWorkspaceBackend::refreshFromWorkspaceEvent() { requestSnapshot(); }

Workspace SwayWorkspaceBackend::toWorkspace(const SwayWorkspace& workspace) {
  const std::uint32_t coord = workspace.num >= 0 ? static_cast<std::uint32_t>(workspace.num - 1)
                                                 : static_cast<std::uint32_t>(workspace.ordinal);
  return Workspace{
      .id = workspace.name,
      .name = workspace.name,
      .coordinates = {coord},
      .active = workspace.visible,
      .urgent = workspace.urgent,
      .occupied = workspace.occupied,
  };
}

std::string SwayWorkspaceBackend::quoteCommandArg(const std::string& value) {
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

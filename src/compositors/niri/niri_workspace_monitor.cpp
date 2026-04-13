#include "compositors/niri/niri_workspace_monitor.h"

#include "core/log.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <fcntl.h>
#include <json.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

constexpr Logger kLog("niri_workspace");
constexpr auto kReconnectDelay = std::chrono::seconds(2);
constexpr std::string_view kEventStreamRequest = "\"EventStream\"\n";

[[nodiscard]] bool containsToken(std::string_view haystack, std::string_view needle) {
  if (haystack.empty() || needle.empty()) {
    return false;
  }
  std::string lhs(haystack);
  std::string rhs(needle);
  std::ranges::transform(lhs, lhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  std::ranges::transform(rhs, rhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return lhs.find(rhs) != std::string::npos;
}

[[nodiscard]] std::optional<std::uint64_t> jsonUnsigned(const nlohmann::json& json) {
  if (json.is_number_unsigned()) {
    return json.get<std::uint64_t>();
  }
  if (json.is_number_integer()) {
    const auto value = json.get<std::int64_t>();
    if (value >= 0) {
      return static_cast<std::uint64_t>(value);
    }
  }
  return std::nullopt;
}

[[nodiscard]] std::optional<std::uint64_t> jsonOptionalUnsigned(const nlohmann::json& json, const char* key) {
  const auto it = json.find(key);
  if (it == json.end() || it->is_null()) {
    return std::nullopt;
  }
  return jsonUnsigned(*it);
}

[[nodiscard]] std::string jsonOptionalString(const nlohmann::json& json, const char* key) {
  const auto it = json.find(key);
  if (it == json.end() || !it->is_string()) {
    return {};
  }
  return it->get<std::string>();
}

[[nodiscard]] const nlohmann::json* arrayPayload(const nlohmann::json& payload, const char* key) {
  if (payload.is_array()) {
    return &payload;
  }
  const auto it = payload.find(key);
  if (payload.is_object() && it != payload.end() && it->is_array()) {
    return &(*it);
  }
  return nullptr;
}

[[nodiscard]] const nlohmann::json* objectPayload(const nlohmann::json& payload, const char* key) {
  if (payload.is_object()) {
    const auto it = payload.find(key);
    if (it != payload.end() && it->is_object()) {
      return &(*it);
    }
    if (payload.contains("id")) {
      return &payload;
    }
  }
  return nullptr;
}

} // namespace

NiriWorkspaceMonitor::NiriWorkspaceMonitor(std::string_view compositorHint) {
  const char* socketPath = std::getenv("NIRI_SOCKET");
  if (socketPath != nullptr && socketPath[0] != '\0') {
    m_socketPath = std::string(socketPath);
  }

  m_enabled = containsToken(compositorHint, "niri") || m_socketPath.has_value();
  if (m_enabled) {
    connectIfNeeded();
  }
}

NiriWorkspaceMonitor::~NiriWorkspaceMonitor() { cleanup(); }

void NiriWorkspaceMonitor::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

int NiriWorkspaceMonitor::pollTimeoutMs() const noexcept {
  if (!m_enabled || m_socketFd >= 0 || !m_socketPath.has_value()) {
    return -1;
  }

  if (m_nextReconnectAt.time_since_epoch().count() == 0) {
    return 0;
  }

  const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(m_nextReconnectAt -
                                                                                std::chrono::steady_clock::now())
                             .count();
  return static_cast<int>(std::max<std::int64_t>(0, remaining));
}

void NiriWorkspaceMonitor::dispatchPoll(short revents) {
  if (!m_enabled) {
    return;
  }

  if (m_socketFd < 0) {
    connectIfNeeded();
    return;
  }

  if ((revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
    closeSocket(true);
    return;
  }

  if ((revents & POLLIN) != 0) {
    readSocket();
  }
}

void NiriWorkspaceMonitor::apply(std::vector<Workspace>& workspaces, const std::string& outputName) const {
  if (!m_enabled || workspaces.empty() || m_workspaces.empty()) {
    return;
  }

  std::unordered_map<std::uint64_t, std::size_t> occupancy;
  for (const auto& [windowId, window] : m_windows) {
    (void)windowId;
    if (window.workspaceId.has_value()) {
      ++occupancy[*window.workspaceId];
    }
  }

  std::vector<const WorkspaceState*> candidates;
  candidates.reserve(m_workspaces.size());
  for (const auto& [workspaceId, workspace] : m_workspaces) {
    (void)workspaceId;
    if (!outputName.empty() && workspace.output != outputName) {
      continue;
    }
    candidates.push_back(&workspace);
  }

  std::sort(candidates.begin(), candidates.end(), [](const WorkspaceState* lhs, const WorkspaceState* rhs) {
    if (lhs->idx != rhs->idx) {
      return lhs->idx < rhs->idx;
    }
    return lhs->id < rhs->id;
  });

  std::vector<const WorkspaceState*> matches(workspaces.size(), nullptr);
  std::unordered_map<std::uint64_t, bool> used;

  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const auto parsedId = parseUnsigned(workspaces[i].id);
    std::optional<std::size_t> parsedIndex;
    if (!workspaces[i].coordinates.empty()) {
      parsedIndex = static_cast<std::size_t>(workspaces[i].coordinates.front() + 1u);
    } else {
      parsedIndex = parseLeadingNumber(workspaces[i].id);
      if (!parsedIndex.has_value()) {
        parsedIndex = parseLeadingNumber(workspaces[i].name);
      }
    }

    auto pickCandidate = [&](auto&& predicate) -> const WorkspaceState* {
      for (const auto* candidate : candidates) {
        if (used.contains(candidate->id) || !predicate(*candidate)) {
          continue;
        }
        used.emplace(candidate->id, true);
        return candidate;
      }
      return nullptr;
    };

    if (parsedId.has_value()) {
      matches[i] = pickCandidate([&](const WorkspaceState& candidate) { return candidate.id == *parsedId; });
    }
    if (matches[i] == nullptr && !workspaces[i].name.empty()) {
      matches[i] =
          pickCandidate([&](const WorkspaceState& candidate) { return candidate.name == workspaces[i].name; });
    }
    if (matches[i] == nullptr && parsedIndex.has_value()) {
      matches[i] = pickCandidate([&](const WorkspaceState& candidate) {
        return static_cast<std::size_t>(candidate.idx) == *parsedIndex;
      });
    }
  }

  if (!outputName.empty()) {
    std::size_t nextCandidate = 0;
    for (std::size_t i = 0; i < matches.size(); ++i) {
      if (matches[i] != nullptr) {
        continue;
      }
      while (nextCandidate < candidates.size() && used.contains(candidates[nextCandidate]->id)) {
        ++nextCandidate;
      }
      if (nextCandidate >= candidates.size()) {
        break;
      }
      matches[i] = candidates[nextCandidate];
      used.emplace(candidates[nextCandidate]->id, true);
      ++nextCandidate;
    }
  }

  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    workspaces[i].occupied = matches[i] != nullptr && occupancy.contains(matches[i]->id) && occupancy[matches[i]->id] > 0;
  }
}

void NiriWorkspaceMonitor::cleanup() {
  closeSocket(false);
  m_windows.clear();
  m_workspaces.clear();
  m_readBuffer.clear();
}

void NiriWorkspaceMonitor::connectIfNeeded() {
  if (!m_enabled || m_socketFd >= 0 || !m_socketPath.has_value()) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (m_nextReconnectAt.time_since_epoch().count() != 0 && now < m_nextReconnectAt) {
    return;
  }

  const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    scheduleReconnect();
    return;
  }

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (m_socketPath->size() >= sizeof(addr.sun_path)) {
    kLog.warn("niri socket path too long");
    ::close(fd);
    scheduleReconnect();
    return;
  }
  std::memcpy(addr.sun_path, m_socketPath->c_str(), m_socketPath->size() + 1);

  if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) {
    ::close(fd);
    scheduleReconnect();
    return;
  }

  const auto written = ::write(fd, kEventStreamRequest.data(), kEventStreamRequest.size());
  if (written < 0 || static_cast<std::size_t>(written) != kEventStreamRequest.size()) {
    ::close(fd);
    scheduleReconnect();
    return;
  }

  const int flags = ::fcntl(fd, F_GETFL, 0);
  if (flags >= 0) {
    (void)::fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  }

  m_socketFd = fd;
  m_nextReconnectAt = {};
  m_readBuffer.clear();
  kLog.debug("connected to niri event stream");
}

void NiriWorkspaceMonitor::closeSocket(bool scheduleReconnectFlag) {
  if (m_socketFd >= 0) {
    ::close(m_socketFd);
    m_socketFd = -1;
  }

  if (scheduleReconnectFlag) {
    scheduleReconnect();
  } else {
    m_nextReconnectAt = {};
  }
}

void NiriWorkspaceMonitor::scheduleReconnect() { m_nextReconnectAt = std::chrono::steady_clock::now() + kReconnectDelay; }

void NiriWorkspaceMonitor::readSocket() {
  std::array<char, 4096> buffer{};
  while (true) {
    const ssize_t readBytes = ::read(m_socketFd, buffer.data(), buffer.size());
    if (readBytes > 0) {
      m_readBuffer.insert(m_readBuffer.end(), buffer.begin(), buffer.begin() + readBytes);
      continue;
    }

    if (readBytes == 0) {
      closeSocket(true);
      return;
    }

    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      break;
    }

    closeSocket(true);
    return;
  }

  parseMessages();
}

void NiriWorkspaceMonitor::parseMessages() {
  auto lineStart = m_readBuffer.begin();
  for (auto it = m_readBuffer.begin(); it != m_readBuffer.end(); ++it) {
    if (*it != '\n') {
      continue;
    }

    std::string line(lineStart, it);
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }

    if (!line.empty() && !handleMessage(line)) {
      m_readBuffer.clear();
      return;
    }

    lineStart = std::next(it);
  }

  if (lineStart != m_readBuffer.begin()) {
    m_readBuffer.erase(m_readBuffer.begin(), lineStart);
  }
}

bool NiriWorkspaceMonitor::handleMessage(std::string_view line) {
  nlohmann::json json;
  try {
    json = nlohmann::json::parse(line);
  } catch (const nlohmann::json::exception& e) {
    kLog.warn("failed to parse niri event stream message: {}", e.what());
    return true;
  }

  if (!json.is_object()) {
    return true;
  }

  if (json.contains("Ok")) {
    return true;
  }
  if (json.contains("Err")) {
    kLog.warn("niri event stream returned an error, reconnecting");
    closeSocket(true);
    return false;
  }
  if (json.size() != 1) {
    return true;
  }

  const auto it = json.begin();
  bool changed = false;
  if (it.key() == "WorkspacesChanged") {
    changed = handleWorkspacesChanged(it.value());
  } else if (it.key() == "WindowsChanged") {
    changed = handleWindowsChanged(it.value());
  } else if (it.key() == "WindowOpenedOrChanged") {
    changed = handleWindowOpenedOrChanged(it.value());
  } else if (it.key() == "WindowClosed") {
    changed = handleWindowClosed(it.value());
  }

  if (changed) {
    notifyChanged();
  }
  return true;
}

bool NiriWorkspaceMonitor::handleWorkspacesChanged(const nlohmann::json& payload) {
  const auto* workspaces = arrayPayload(payload, "workspaces");
  if (workspaces == nullptr) {
    return false;
  }

  std::unordered_map<std::uint64_t, WorkspaceState> next;
  for (const auto& item : *workspaces) {
    if (const auto parsed = parseWorkspace(item); parsed.has_value()) {
      next.emplace(parsed->id, *parsed);
    }
  }

  if (next == m_workspaces) {
    return false;
  }

  m_workspaces = std::move(next);
  return true;
}

bool NiriWorkspaceMonitor::handleWindowsChanged(const nlohmann::json& payload) {
  const auto* windows = arrayPayload(payload, "windows");
  if (windows == nullptr) {
    return false;
  }

  std::unordered_map<std::uint64_t, WindowState> next;
  for (const auto& item : *windows) {
    if (const auto parsed = parseWindow(item); parsed.has_value()) {
      next.emplace(parsed->first, parsed->second);
    }
  }

  if (next == m_windows) {
    return false;
  }

  m_windows = std::move(next);
  return true;
}

bool NiriWorkspaceMonitor::handleWindowOpenedOrChanged(const nlohmann::json& payload) {
  const auto* window = objectPayload(payload, "window");
  if (window == nullptr) {
    return false;
  }

  const auto parsed = parseWindow(*window);
  if (!parsed.has_value()) {
    return false;
  }

  const auto [id, state] = *parsed;
  const auto existing = m_windows.find(id);
  if (existing != m_windows.end() && existing->second == state) {
    return false;
  }

  m_windows[id] = state;
  return true;
}

bool NiriWorkspaceMonitor::handleWindowClosed(const nlohmann::json& payload) {
  std::optional<std::uint64_t> windowId = jsonUnsigned(payload);
  if (!windowId.has_value() && payload.is_object()) {
    windowId = jsonOptionalUnsigned(payload, "id");
    if (!windowId.has_value()) {
      windowId = jsonOptionalUnsigned(payload, "window_id");
    }
  }
  if (!windowId.has_value()) {
    return false;
  }

  return m_windows.erase(*windowId) > 0;
}

std::optional<NiriWorkspaceMonitor::WorkspaceState> NiriWorkspaceMonitor::parseWorkspace(const nlohmann::json& json) {
  if (!json.is_object()) {
    return std::nullopt;
  }

  const auto id = jsonOptionalUnsigned(json, "id");
  const auto idx = jsonOptionalUnsigned(json, "idx");
  if (!id.has_value() || !idx.has_value()) {
    return std::nullopt;
  }

  return WorkspaceState{
      .id = *id,
      .idx = static_cast<std::uint8_t>(*idx),
      .name = jsonOptionalString(json, "name"),
      .output = jsonOptionalString(json, "output"),
  };
}

std::optional<std::pair<std::uint64_t, NiriWorkspaceMonitor::WindowState>>
NiriWorkspaceMonitor::parseWindow(const nlohmann::json& json) {
  if (!json.is_object()) {
    return std::nullopt;
  }

  const auto id = jsonOptionalUnsigned(json, "id");
  if (!id.has_value()) {
    return std::nullopt;
  }

  return std::pair<std::uint64_t, WindowState>{
      *id,
      WindowState{.workspaceId = jsonOptionalUnsigned(json, "workspace_id")},
  };
}

std::optional<std::uint64_t> NiriWorkspaceMonitor::parseUnsigned(const std::string& value) {
  if (value.empty()) {
    return std::nullopt;
  }

  std::uint64_t parsed = 0;
  const auto [ptr, ec] = std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (ec != std::errc{} || ptr != value.data() + value.size()) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<std::size_t> NiriWorkspaceMonitor::parseLeadingNumber(const std::string& value) {
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

void NiriWorkspaceMonitor::notifyChanged() const {
  if (m_changeCallback) {
    m_changeCallback();
  }
}

#include "dbus/polkit/polkit_agent.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <array>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <map>
#include <optional>
#include <poll.h>
#include <pwd.h>
#include <sdbus-c++/IConnection.h>
#include <sdbus-c++/IObject.h>
#include <sdbus-c++/MethodResult.h>
#include <sdbus-c++/Types.h>
#include <sdbus-c++/VTableItems.h>
#include <string_view>
#include <sstream>
#include <sys/types.h>
#include <sys/wait.h>
#include <tuple>
#include <unistd.h>
#include <utility>

namespace {

constexpr Logger kLog("polkit");

const sdbus::ServiceName k_authorityBusName{"org.freedesktop.PolicyKit1"};
const sdbus::ObjectPath k_authorityObjectPath{"/org/freedesktop/PolicyKit1/Authority"};
constexpr auto k_authorityInterface = "org.freedesktop.PolicyKit1.Authority";
const sdbus::ServiceName k_logindBusName{"org.freedesktop.login1"};
const sdbus::ObjectPath k_logindObjectPath{"/org/freedesktop/login1"};
constexpr auto k_logindManagerInterface = "org.freedesktop.login1.Manager";
constexpr auto k_logindSessionInterface = "org.freedesktop.login1.Session";

const sdbus::ObjectPath k_agentObjectPath{"/org/noctalia/PolkitAuthenticationAgent"};
constexpr auto k_agentInterface = "org.freedesktop.PolicyKit1.AuthenticationAgent";

using Subject = sdbus::Struct<std::string, std::map<std::string, sdbus::Variant>>;
using Identity = sdbus::Struct<std::string, std::map<std::string, sdbus::Variant>>;
using IdentityDetails = std::map<std::string, sdbus::Variant>;

std::string localeFromEnvironment() {
  if (const char* lang = std::getenv("LANG"); lang != nullptr && lang[0] != '\0') {
    return lang;
  }
  return "C";
}

std::optional<std::string> usernameFromUid(std::uint32_t uid) {
  passwd pwd{};
  passwd* result = nullptr;
  std::array<char, 4096> buffer{};
  const int rc = getpwuid_r(static_cast<uid_t>(uid), &pwd, buffer.data(), buffer.size(), &result);
  if (rc != 0 || result == nullptr || result->pw_name == nullptr || result->pw_name[0] == '\0') {
    return std::nullopt;
  }
  return std::string(result->pw_name);
}

std::optional<std::string> identityUsername(const Identity& identity) {
  const std::string& kind = std::get<0>(identity);
  const IdentityDetails& details = std::get<1>(identity);
  if (kind != "unix-user") {
    return std::nullopt;
  }
  const auto nameIt = details.find("name");
  if (nameIt != details.end()) {
    try {
      const std::string name = nameIt->second.get<std::string>();
      if (!name.empty()) {
        return name;
      }
    } catch (const sdbus::Error&) {
    }
  }
  const auto uidIt = details.find("uid");
  if (uidIt != details.end()) {
    try {
      return usernameFromUid(uidIt->second.get<std::uint32_t>());
    } catch (const sdbus::Error&) {
    }
  }
  return std::nullopt;
}

bool writeAll(int fd, std::string_view payload) {
  const char* cursor = payload.data();
  std::size_t remaining = payload.size();
  while (remaining > 0) {
    const ssize_t written = ::write(fd, cursor, remaining);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    cursor += static_cast<std::size_t>(written);
    remaining -= static_cast<std::size_t>(written);
  }
  return true;
}

std::optional<std::string> readLineNonBlocking(int fd, std::string& buffer) {
  char chunk[256];
  while (true) {
    const ssize_t n = ::read(fd, chunk, sizeof(chunk));
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        break;
      }
      return std::nullopt;
    }
    if (n == 0) {
      if (buffer.empty()) {
        return std::nullopt;
      }
      std::string out = std::move(buffer);
      buffer.clear();
      return out;
    }
    buffer.append(chunk, static_cast<std::size_t>(n));
    const std::size_t newlinePos = buffer.find('\n');
    if (newlinePos != std::string::npos) {
      std::string line = buffer.substr(0, newlinePos);
      buffer.erase(0, newlinePos + 1);
      return line;
    }
  }
  return std::string{};
}

bool setFdNonBlocking(int fd) {
  const int flags = ::fcntl(fd, F_GETFL, 0);
  if (flags < 0) {
    return false;
  }
  return ::fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

std::optional<std::string> helperPath() {
  constexpr std::array<const char*, 2> candidates = {
      "/usr/lib/polkit-1/polkit-agent-helper-1",
      "/usr/libexec/polkit-agent-helper-1",
  };
  for (const char* path : candidates) {
    if (::access(path, X_OK) == 0) {
      return std::string(path);
    }
  }
  return std::nullopt;
}

std::string extractPromptText(const std::string& line, const std::string& token) {
  if (line.size() <= token.size()) {
    return "Authentication required";
  }
  std::string prompt = line.substr(token.size());
  if (!prompt.empty() && prompt.front() == ' ') {
    prompt.erase(prompt.begin());
  }
  return prompt;
}

std::optional<std::string> sessionIdFromLogind(SystemBus& bus) {
  try {
    auto manager = sdbus::createProxy(bus.connection(), k_logindBusName, k_logindObjectPath);
    sdbus::ObjectPath sessionPath;
    manager->callMethod("GetSessionByPID")
        .onInterface(k_logindManagerInterface)
        .withArguments(static_cast<std::uint32_t>(::getpid()))
        .storeResultsTo(sessionPath);

    auto session = sdbus::createProxy(bus.connection(), k_logindBusName, sessionPath);
    const sdbus::Variant idVar = session->getProperty("Id").onInterface(k_logindSessionInterface);
    const std::string sessionId = idVar.get<std::string>();
    if (!sessionId.empty()) {
      return sessionId;
    }
  } catch (const sdbus::Error&) {
  }
  return std::nullopt;
}

Subject makeSessionSubject(SystemBus& bus) {
  if (const auto sessionId = sessionIdFromLogind(bus); sessionId.has_value()) {
    std::map<std::string, sdbus::Variant> sessionDetails;
    sessionDetails.emplace("session-id", sdbus::Variant{*sessionId});
    return Subject{"unix-session", std::move(sessionDetails)};
  }

  if (const char* sessionId = std::getenv("XDG_SESSION_ID"); sessionId != nullptr && sessionId[0] != '\0') {
    std::map<std::string, sdbus::Variant> sessionDetails;
    sessionDetails.emplace("session-id", sdbus::Variant{std::string(sessionId)});
    return Subject{"unix-session", std::move(sessionDetails)};
  }

  // Fallback when the session id is unavailable: register for this process.
  std::map<std::string, sdbus::Variant> details;
  const pid_t pid = ::getpid();
  std::ifstream statFile("/proc/self/stat");
  if (statFile.is_open()) {
    std::string line;
    std::getline(statFile, line);
    const std::size_t rightParen = line.rfind(')');
    if (rightParen != std::string::npos && rightParen + 2 < line.size()) {
      // /proc/<pid>/stat field 22 is process start time (clock ticks since boot).
      std::istringstream rest(line.substr(rightParen + 2));
      std::string field;
      std::uint64_t startTime = 0;
      for (int fieldIndex = 3; fieldIndex <= 22; ++fieldIndex) {
        if (!(rest >> field)) {
          break;
        }
        if (fieldIndex == 22) {
          try {
            startTime = static_cast<std::uint64_t>(std::stoull(field));
          } catch (const std::exception&) {
            startTime = 0;
          }
          break;
        }
      }
      details.emplace("pid", sdbus::Variant{static_cast<std::uint32_t>(pid)});
      details.emplace("start-time", sdbus::Variant{startTime});
      return Subject{"unix-process", std::move(details)};
    }
  }
  // Fallback when /proc parsing fails.
  details.emplace("pid", sdbus::Variant{static_cast<std::uint32_t>(pid)});
  details.emplace("start-time", sdbus::Variant{static_cast<std::uint64_t>(0)});
  return Subject{"unix-process", std::move(details)};
}

PolkitIdentity toPolkitIdentity(const Identity& wireIdentity) {
  PolkitIdentity identity;
  identity.kind = std::get<0>(wireIdentity);
  const auto& details = std::get<1>(wireIdentity);

  const auto uidIt = details.find("uid");
  if (uidIt != details.end()) {
    try {
      identity.uid = uidIt->second.get<std::uint32_t>();
    } catch (const sdbus::Error&) {
    }
  }
  const auto userNameIt = details.find("name");
  if (userNameIt != details.end()) {
    try {
      identity.userName = userNameIt->second.get<std::string>();
    } catch (const sdbus::Error&) {
    }
  }
  return identity;
}

std::optional<std::size_t> firstSupportedIdentityIndex(const std::vector<Identity>& identities, std::string& outUser) {
  for (std::size_t i = 0; i < identities.size(); ++i) {
    if (auto resolved = identityUsername(identities[i]); resolved.has_value()) {
      outUser = *resolved;
      return i;
    }
  }
  return std::nullopt;
}

} // namespace

struct PolkitAgent::Impl {
  SystemBus& bus;
  std::unique_ptr<sdbus::IObject> object;
  Subject subject;
  StateCallback stateCallback;
  std::optional<sdbus::Result<>> pendingBeginResult;

  std::optional<PolkitRequest> pending;
  std::vector<Identity> pendingIdentitiesWire;
  std::size_t activeIdentityIndex = 0;
  std::string activeUser;

  int helperInputFd = -1;
  int helperOutputFd = -1;
  pid_t helperPid = -1;
  std::string helperLineBuffer;

  bool responseRequired = false;
  bool responseVisible = false;
  std::string inputPrompt;
  std::string supplementaryMessage;
  bool supplementaryError = false;

  explicit Impl(SystemBus& systemBus) : bus(systemBus), subject(makeSessionSubject(systemBus)) {}
  ~Impl() { stopHelper(); }

  void emitStateChanged() {
    if (stateCallback) {
      stateCallback();
    }
  }

  void clearConversationState() {
    responseRequired = false;
    responseVisible = false;
    inputPrompt.clear();
    supplementaryMessage.clear();
    supplementaryError = false;
  }

  void finishBeginAuthenticationCall() {
    if (pendingBeginResult.has_value()) {
      pendingBeginResult->returnResults();
      pendingBeginResult.reset();
    }
  }

  void stopHelper() {
    if (helperInputFd >= 0) {
      ::close(helperInputFd);
      helperInputFd = -1;
    }
    if (helperOutputFd >= 0) {
      ::close(helperOutputFd);
      helperOutputFd = -1;
    }
    if (helperPid > 0) {
      int status = 0;
      (void)::waitpid(helperPid, &status, 0);
      helperPid = -1;
    }
    helperLineBuffer.clear();
  }

  void clearPending() {
    stopHelper();
    finishBeginAuthenticationCall();
    pending.reset();
    pendingIdentitiesWire.clear();
    activeIdentityIndex = 0;
    activeUser.clear();
    clearConversationState();
    emitStateChanged();
  }

  bool startHelperSession(bool preserveSupplementaryMessage = false) {
    if (!pending.has_value()) {
      return false;
    }
    stopHelper();

    auto helper = helperPath();
    if (!helper.has_value()) {
      kLog.warn("polkit-agent-helper-1 not found");
      return false;
    }

    int stdinPipe[2] = {-1, -1};
    int stdoutPipe[2] = {-1, -1};
    if (::pipe2(stdinPipe, O_CLOEXEC) != 0) {
      return false;
    }
    if (::pipe2(stdoutPipe, O_CLOEXEC) != 0) {
      ::close(stdinPipe[0]);
      ::close(stdinPipe[1]);
      return false;
    }

    const pid_t pid = ::fork();
    if (pid < 0) {
      ::close(stdinPipe[0]);
      ::close(stdinPipe[1]);
      ::close(stdoutPipe[0]);
      ::close(stdoutPipe[1]);
      return false;
    }

    if (pid == 0) {
      ::dup2(stdinPipe[0], STDIN_FILENO);
      ::dup2(stdoutPipe[1], STDOUT_FILENO);
      ::close(stdinPipe[0]);
      ::close(stdinPipe[1]);
      ::close(stdoutPipe[0]);
      ::close(stdoutPipe[1]);
      ::execl(helper->c_str(), helper->c_str(), activeUser.c_str(), static_cast<char*>(nullptr));
      _exit(127);
    }

    ::close(stdinPipe[0]);
    ::close(stdoutPipe[1]);
    helperInputFd = stdinPipe[1];
    helperOutputFd = stdoutPipe[0];
    helperPid = pid;
    if (!setFdNonBlocking(helperOutputFd)) {
      kLog.warn("failed to set helper output non-blocking");
    }
    // polkit-agent-helper-1 expects the cookie as the first stdin line.
    if (!writeAll(helperInputFd, pending->cookie + "\n")) {
      stopHelper();
      return false;
    }
    if (preserveSupplementaryMessage) {
      responseRequired = false;
      responseVisible = false;
      inputPrompt.clear();
    } else {
      clearConversationState();
    }
    emitStateChanged();
    return true;
  }

  void handleFailure() {
    // Keep the request active and start a fresh helper attempt.
    stopHelper();
    responseRequired = false;
    responseVisible = false;
    inputPrompt.clear();
    supplementaryMessage = "Invalid password";
    supplementaryError = true;
    emitStateChanged();

    if (!pending.has_value()) {
      return;
    }
    if (!startHelperSession(true)) {
      kLog.warn("polkit helper restart failed for action \"{}\"", pending->actionId);
      clearPending();
    }
  }

  void handleHelperLine(const std::string& line) {
    if (line.rfind("PAM_PROMPT_ECHO_OFF", 0) == 0) {
      inputPrompt = extractPromptText(line, "PAM_PROMPT_ECHO_OFF");
      responseVisible = false;
      responseRequired = true;
      emitStateChanged();
      return;
    }
    if (line.rfind("PAM_PROMPT_ECHO_ON", 0) == 0) {
      inputPrompt = extractPromptText(line, "PAM_PROMPT_ECHO_ON");
      responseVisible = true;
      responseRequired = true;
      emitStateChanged();
      return;
    }
    if (line.rfind("PAM_TEXT_INFO", 0) == 0) {
      supplementaryMessage = extractPromptText(line, "PAM_TEXT_INFO");
      supplementaryError = false;
      emitStateChanged();
      return;
    }
    if (line.rfind("PAM_ERROR_MSG", 0) == 0) {
      supplementaryMessage = extractPromptText(line, "PAM_ERROR_MSG");
      supplementaryError = true;
      emitStateChanged();
      return;
    }
    if (line.rfind("PAM_ERROR", 0) == 0) {
      supplementaryMessage = extractPromptText(line, "PAM_ERROR");
      supplementaryError = true;
      emitStateChanged();
      return;
    }
    if (line == "SUCCESS") {
      kLog.info("polkit action \"{}\" authorized as {}", pending->actionId, activeUser);
      supplementaryMessage = "Authorized";
      supplementaryError = false;
      emitStateChanged();
      clearPending();
      return;
    }
    if (line == "FAILURE") {
      handleFailure();
    }
  }
};

PolkitAgent::PolkitAgent(SystemBus& bus) : m_impl(std::make_unique<Impl>(bus)) {
  m_impl->object = sdbus::createObject(bus.connection(), k_agentObjectPath);

  m_impl->object
      ->addVTable(
          sdbus::registerMethod("BeginAuthentication")
              .withInputParamNames("action_id", "message", "icon_name", "details", "cookie", "identities")
              .implementedAs([this](sdbus::Result<>&& result, std::string actionId, std::string message,
                                    std::string iconName,
                                    std::map<std::string, std::string> /*details*/, std::string cookie,
                                    std::vector<Identity> identities) {
                if (m_impl == nullptr) {
                  result.returnResults();
                  return;
                }
                if (m_impl->pendingBeginResult.has_value()) {
                  // Defensive: finish any previous deferred call before replacing state.
                  m_impl->finishBeginAuthenticationCall();
                }
                if (m_impl->pending.has_value()) {
                  m_impl->stopHelper();
                  m_impl->clearConversationState();
                }
                m_impl->pendingBeginResult = std::move(result);
                PolkitRequest request;
                request.actionId = std::move(actionId);
                request.message = std::move(message);
                request.iconName = std::move(iconName);
                request.cookie = std::move(cookie);
                request.identities.reserve(identities.size());
                for (const auto& identity : identities) {
                  request.identities.push_back(toPolkitIdentity(identity));
                }
                m_impl->pending = request;
                m_impl->pendingIdentitiesWire = std::move(identities);

                std::string userName;
                const auto selectedIdentityIndex =
                    firstSupportedIdentityIndex(m_impl->pendingIdentitiesWire, userName);
                if (!selectedIdentityIndex.has_value()) {
                  kLog.warn("polkit request \"{}\" has no unix-user identity", request.actionId);
                  m_impl->clearPending();
                  return;
                }
                m_impl->activeIdentityIndex = *selectedIdentityIndex;
                m_impl->activeUser = userName;
                if (!m_impl->startHelperSession()) {
                  kLog.warn("polkit helper startup failed for action \"{}\"", request.actionId);
                  m_impl->clearPending();
                  return;
                }
              }),
          sdbus::registerMethod("CancelAuthentication").withInputParamNames("cookie").implementedAs(
              [this](const std::string& cookie) {
                if (m_impl == nullptr || !m_impl->pending.has_value()) {
                  return;
                }
                if (m_impl->pending->cookie == cookie) {
                  m_impl->clearPending();
                }
              }))
      .forInterface(k_agentInterface);

  try {
    auto authority = sdbus::createProxy(bus.connection(), k_authorityBusName, k_authorityObjectPath);
    authority->callMethod("RegisterAuthenticationAgent")
        .onInterface(k_authorityInterface)
        .withArguments(m_impl->subject, localeFromEnvironment(), std::string(k_agentObjectPath));
    kLog.info("registered Polkit authentication agent at {}", std::string(k_agentObjectPath));
  } catch (const sdbus::Error& e) {
    kLog.warn("polkit agent registration failed: {}", e.what());
    throw;
  }
}

PolkitAgent::~PolkitAgent() {
  if (m_impl == nullptr) {
    return;
  }
  m_impl->clearPending();

  try {
    auto authority = sdbus::createProxy(m_impl->bus.connection(), k_authorityBusName, k_authorityObjectPath);
    authority->callMethod("UnregisterAuthenticationAgent")
        .onInterface(k_authorityInterface)
        .withArguments(m_impl->subject, std::string(k_agentObjectPath));
  } catch (const sdbus::Error& e) {
    kLog.debug("polkit agent unregister failed: {}", e.what());
  }
}

void PolkitAgent::setStateCallback(StateCallback callback) {
  if (m_impl != nullptr) {
    m_impl->stateCallback = std::move(callback);
  }
}

void PolkitAgent::submitResponse(const std::string& response) {
  if (m_impl == nullptr || !m_impl->pending.has_value() || !m_impl->responseRequired || m_impl->helperInputFd < 0) {
    return;
  }
  if (!writeAll(m_impl->helperInputFd, response + "\n")) {
    m_impl->handleFailure();
    return;
  }
  m_impl->responseRequired = false;
  m_impl->inputPrompt.clear();
  m_impl->supplementaryMessage = "Authenticating...";
  m_impl->supplementaryError = false;
  m_impl->emitStateChanged();
}

void PolkitAgent::cancelRequest() {
  if (m_impl == nullptr || !m_impl->pending.has_value()) {
    return;
  }
  if (m_impl->helperInputFd >= 0) {
    (void)writeAll(m_impl->helperInputFd, "CANCEL\n");
  }
  m_impl->clearPending();
}

void PolkitAgent::addPollFds(std::vector<pollfd>& fds) const {
  if (m_impl != nullptr && m_impl->helperOutputFd >= 0) {
    fds.push_back({.fd = m_impl->helperOutputFd, .events = POLLIN | POLLHUP | POLLERR, .revents = 0});
  }
}

void PolkitAgent::dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) {
  if (m_impl == nullptr || m_impl->helperOutputFd < 0 || startIdx >= fds.size()) {
    return;
  }
  const auto revents = fds[startIdx].revents;
  if ((revents & (POLLIN | POLLHUP | POLLERR)) == 0) {
    return;
  }

  while (true) {
    const auto line = readLineNonBlocking(m_impl->helperOutputFd, m_impl->helperLineBuffer);
    if (!line.has_value()) {
      m_impl->handleFailure();
      break;
    }
    if (line->empty()) {
      break;
    }
    m_impl->handleHelperLine(*line);
    if (!m_impl->pending.has_value()) {
      break;
    }
  }
}

bool PolkitAgent::hasPendingRequest() const noexcept { return m_impl != nullptr && m_impl->pending.has_value(); }

PolkitRequest PolkitAgent::pendingRequest() const {
  if (m_impl == nullptr || !m_impl->pending.has_value()) {
    return {};
  }
  return *m_impl->pending;
}

bool PolkitAgent::isResponseRequired() const noexcept { return m_impl != nullptr && m_impl->responseRequired; }

bool PolkitAgent::responseVisible() const noexcept { return m_impl != nullptr && m_impl->responseVisible; }

std::string PolkitAgent::inputPrompt() const { return m_impl != nullptr ? m_impl->inputPrompt : std::string{}; }

std::string PolkitAgent::supplementaryMessage() const {
  return m_impl != nullptr ? m_impl->supplementaryMessage : std::string{};
}

bool PolkitAgent::supplementaryIsError() const noexcept {
  return m_impl != nullptr && m_impl->supplementaryError;
}

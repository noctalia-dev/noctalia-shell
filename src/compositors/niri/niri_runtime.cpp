#include "compositors/niri/niri_runtime.h"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace compositors::niri {

  struct NiriRuntime::IpcReply {
    enum class Status {
      Unavailable,
      WriteFailed,
      ReadFailed,
      NoResponse,
      InvalidJson,
      Replied,
    };

    Status status = Status::Unavailable;
    std::optional<nlohmann::json> json;
  };

  bool NiriRuntime::available() const {
    ensureResolved();
    return !m_socketPath.empty();
  }

  const std::string& NiriRuntime::socketPath() const {
    ensureResolved();
    return m_socketPath;
  }

  std::optional<nlohmann::json> NiriRuntime::requestJson(std::string_view request) const {
    return this->request(request).json;
  }

  bool NiriRuntime::requestOk(std::string_view request, bool acceptNoResponse) const {
    const auto reply = this->request(request);
    if (reply.status == IpcReply::Status::NoResponse) {
      return acceptNoResponse;
    }
    if (!reply.json.has_value() || !reply.json->is_object()) {
      return false;
    }
    return reply.json->contains("Ok");
  }

  bool NiriRuntime::requestAction(const nlohmann::json& action, bool acceptNoResponse) const {
    nlohmann::json request = nlohmann::json::object();
    request["Action"] = action;
    auto payload = request.dump();
    payload.push_back('\n');
    return requestOk(payload, acceptNoResponse);
  }

  NiriRuntime::IpcReply NiriRuntime::request(std::string_view request) const {
    ensureResolved();
    if (m_socketPath.empty() || request.empty()) {
      return {IpcReply::Status::Unavailable, std::nullopt};
    }

    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
      return {IpcReply::Status::Unavailable, std::nullopt};
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (m_socketPath.size() >= sizeof(addr.sun_path)) {
      ::close(fd);
      return {IpcReply::Status::Unavailable, std::nullopt};
    }
    std::memcpy(addr.sun_path, m_socketPath.c_str(), m_socketPath.size() + 1);

    if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) {
      ::close(fd);
      return {IpcReply::Status::Unavailable, std::nullopt};
    }

    std::size_t offset = 0;
    while (offset < request.size()) {
      const ssize_t written = ::write(fd, request.data() + offset, request.size() - offset);
      if (written <= 0) {
        if (written < 0 && errno == EINTR) {
          continue;
        }
        ::close(fd);
        return {IpcReply::Status::WriteFailed, std::nullopt};
      }
      offset += static_cast<std::size_t>(written);
    }

    std::string response;
    char buffer[4096];
    while (true) {
      const ssize_t count = ::read(fd, buffer, sizeof(buffer));
      if (count > 0) {
        response.append(buffer, static_cast<std::size_t>(count));
        if (response.find('\n') != std::string::npos) {
          break;
        }
        continue;
      }
      if (count == 0) {
        break;
      }
      if (errno == EINTR) {
        continue;
      }
      ::close(fd);
      return {IpcReply::Status::ReadFailed, std::nullopt};
    }

    ::close(fd);

    const std::size_t newline = response.find('\n');
    if (newline != std::string::npos) {
      response.resize(newline);
    }
    if (response.empty()) {
      return {IpcReply::Status::NoResponse, std::nullopt};
    }

    try {
      return {IpcReply::Status::Replied, nlohmann::json::parse(response)};
    } catch (const nlohmann::json::exception&) {
      return {IpcReply::Status::InvalidJson, std::nullopt};
    }
  }

  void NiriRuntime::refresh() {
    m_socketPath.clear();
    m_resolved = false;
    resolveSocketPath();
  }

  void NiriRuntime::ensureResolved() const {
    if (!m_resolved) {
      resolveSocketPath();
    }
  }

  void NiriRuntime::resolveSocketPath() const {
    m_resolved = true;
    const char* socketPath = std::getenv("NIRI_SOCKET");
    if (socketPath != nullptr && socketPath[0] != '\0') {
      m_socketPath = socketPath;
    }
  }

} // namespace compositors::niri

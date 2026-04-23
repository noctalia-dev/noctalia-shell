#include "compositors/niri/niri_keyboard_backend.h"

#include "core/process.h"
#include "util/string_utils.h"

#include <cstdlib>
#include <cstring>
#include <json.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

  [[nodiscard]] std::optional<nlohmann::json> makeRequest(const std::string& socketPath, std::string_view request) {
    if (socketPath.empty()) {
      return std::nullopt;
    }

    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
      return std::nullopt;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (socketPath.size() >= sizeof(addr.sun_path)) {
      ::close(fd);
      return std::nullopt;
    }
    std::memcpy(addr.sun_path, socketPath.c_str(), socketPath.size() + 1);

    if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) {
      ::close(fd);
      return std::nullopt;
    }

    const ssize_t written = ::write(fd, request.data(), request.size());
    if (written < 0 || static_cast<std::size_t>(written) != request.size()) {
      ::close(fd);
      return std::nullopt;
    }

    std::string response;
    char buffer[4096];
    while (true) {
      const ssize_t count = ::read(fd, buffer, sizeof(buffer));
      if (count <= 0) {
        break;
      }
      response.append(buffer, static_cast<std::size_t>(count));
      if (response.find('\n') != std::string::npos) {
        break;
      }
    }

    ::close(fd);

    const std::size_t newline = response.find('\n');
    if (newline != std::string::npos) {
      response.resize(newline);
    }
    if (response.empty()) {
      return std::nullopt;
    }

    try {
      return nlohmann::json::parse(response);
    } catch (const nlohmann::json::exception&) {
      return std::nullopt;
    }
  }

  std::optional<KeyboardLayoutState> parseLayoutState(const nlohmann::json& response) {
    if (!response.is_object()) {
      return std::nullopt;
    }

    const auto okIt = response.find("Ok");
    if (okIt == response.end() || !okIt->is_object()) {
      return std::nullopt;
    }

    const auto layoutsIt = okIt->find("KeyboardLayouts");
    if (layoutsIt == okIt->end() || !layoutsIt->is_object()) {
      return std::nullopt;
    }

    const auto namesIt = layoutsIt->find("names");
    const auto currentIt = layoutsIt->find("current_idx");
    if (namesIt == layoutsIt->end() || !namesIt->is_array() || currentIt == layoutsIt->end() ||
        !currentIt->is_number_integer()) {
      return std::nullopt;
    }

    KeyboardLayoutState state;
    state.currentIndex = currentIt->get<int>();
    state.names.reserve(namesIt->size());
    for (const auto& entry : *namesIt) {
      if (!entry.is_string()) {
        return std::nullopt;
      }
      state.names.push_back(entry.get<std::string>());
    }

    if (state.currentIndex < 0 || state.currentIndex >= static_cast<int>(state.names.size())) {
      return std::nullopt;
    }
    return state;
  }

} // namespace

NiriKeyboardBackend::NiriKeyboardBackend(std::string_view compositorHint) {
  const bool hinted = StringUtils::containsInsensitive(compositorHint, "niri");
  const char* niriSocket = std::getenv("NIRI_SOCKET");
  m_enabled = hinted || (niriSocket != nullptr && niriSocket[0] != '\0');
}

bool NiriKeyboardBackend::isAvailable() const noexcept { return m_enabled; }

bool NiriKeyboardBackend::cycleLayout() const {
  if (!m_enabled) {
    return false;
  }
  return process::runSync({"niri", "msg", "action", "switch-layout", "next"});
}

std::optional<KeyboardLayoutState> NiriKeyboardBackend::layoutState() const {
  if (!m_enabled) {
    return std::nullopt;
  }

  const char* niriSocket = std::getenv("NIRI_SOCKET");
  if (niriSocket == nullptr || niriSocket[0] == '\0') {
    return std::nullopt;
  }

  const auto response = makeRequest(niriSocket, "\"KeyboardLayouts\"\n");
  if (!response.has_value()) {
    return std::nullopt;
  }
  return parseLayoutState(*response);
}

std::optional<std::string> NiriKeyboardBackend::currentLayoutName() const {
  const auto state = layoutState();
  if (!state.has_value() || state->currentIndex < 0 || state->currentIndex >= static_cast<int>(state->names.size())) {
    return std::nullopt;
  }
  return state->names[static_cast<std::size_t>(state->currentIndex)];
}

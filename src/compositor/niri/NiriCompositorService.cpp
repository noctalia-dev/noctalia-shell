#include "compositor/niri/NiriCompositorService.hpp"

#include "core/Log.hpp"

#include <array>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <string_view>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

constexpr std::string_view k_event_stream_request = "\"EventStream\"\n";

} // namespace

NiriService::NiriService() {
    if (!connectSocket()) {
        return;
    }
    startReader();
}

NiriService::~NiriService() {
    stopReader();
}

bool NiriService::isRunning() const noexcept {
    return m_running.load();
}

bool NiriService::connectSocket() {
    const char* socket_path_env = std::getenv("NIRI_SOCKET");
    if (socket_path_env == nullptr || socket_path_env[0] == '\0') {
        logInfo("niri integration disabled: NIRI_SOCKET is not set");
        return false;
    }

    const std::string socket_path{socket_path_env};
    if (socket_path.size() >= sizeof(sockaddr_un::sun_path)) {
        logWarn("niri integration disabled: NIRI_SOCKET path is too long");
        return false;
    }

    const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        logWarn("niri integration disabled: failed to create unix socket: {}", std::strerror(errno));
        return false;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);

    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        logWarn("niri integration disabled: failed to connect to {}: {}", socket_path, std::strerror(errno));
        ::close(fd);
        return false;
    }

    const ssize_t wrote = ::send(fd,
                                 k_event_stream_request.data(),
                                 k_event_stream_request.size(),
                                 MSG_NOSIGNAL);
    if (wrote != static_cast<ssize_t>(k_event_stream_request.size())) {
        logWarn("niri integration disabled: failed to request event stream");
        ::close(fd);
        return false;
    }

    m_socket_fd = fd;
    logInfo("niri integration connected (event stream)");
    return true;
}

void NiriService::startReader() {
    if (m_socket_fd < 0 || m_running.load()) {
        return;
    }

    m_running = true;
    m_reader_thread = std::thread([this]() {
        readerLoop();
    });
}

void NiriService::stopReader() {
    m_running = false;

    if (m_socket_fd >= 0) {
        ::shutdown(m_socket_fd, SHUT_RDWR);
        ::close(m_socket_fd);
        m_socket_fd = -1;
    }

    if (m_reader_thread.joinable()) {
        m_reader_thread.join();
    }
}

void NiriService::readerLoop() {
    std::string line;
    while (m_running.load() && readLine(m_socket_fd, line)) {
        if (line.empty()) {
            continue;
        }
        handleEventLine(line);
    }

    if (m_running.load()) {
        logWarn("niri event stream closed");
    }
}

bool NiriService::readLine(int fd, std::string& out) {
    out.clear();

    const auto emit_from_buffer = [&]() -> bool {
        const std::size_t newline_pos = m_read_buffer.find('\n');
        if (newline_pos == std::string::npos) {
            return false;
        }

        out = m_read_buffer.substr(0, newline_pos);
        m_read_buffer.erase(0, newline_pos + 1);
        return true;
    };

    if (emit_from_buffer()) {
        return true;
    }

    std::array<char, 256> buffer{};
    while (true) {
        const ssize_t n = ::recv(fd, buffer.data(), buffer.size(), 0);
        if (n == 0) {
            if (!m_read_buffer.empty()) {
                out = std::move(m_read_buffer);
                m_read_buffer.clear();
                return true;
            }
            return false;
        }
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }

        m_read_buffer.append(buffer.data(), static_cast<std::size_t>(n));
        if (emit_from_buffer()) {
            return true;
        }
    }
}

void NiriService::handleEventLine(const std::string& line) {
    if (line.find("\"Err\"") != std::string::npos) {
        logWarn("niri event stream returned error: {}", line);
        return;
    }

    if (line.find("\"WorkspacesChanged\"") != std::string::npos) {
        handleWorkspacesChanged(line);
        return;
    }

    if (line.find("\"WorkspaceActivated\"") != std::string::npos) {
        handleWorkspaceActivated(line);
        return;
    }
}

void NiriService::handleWorkspacesChanged(const std::string& line) {
    const std::size_t key_pos = line.find("\"workspaces\"");
    if (key_pos == std::string::npos) {
        return;
    }

    const std::size_t array_open = line.find('[', key_pos);
    if (array_open == std::string::npos) {
        return;
    }

    const std::size_t array_close = findMatchingBracket(line, array_open);
    if (array_close == std::string::npos) {
        return;
    }

    m_workspace_labels.clear();

    std::optional<std::uint64_t> focused_id;
    std::size_t cursor = array_open + 1;
    while (cursor < array_close) {
        const std::size_t obj_open = line.find('{', cursor);
        if (obj_open == std::string::npos || obj_open >= array_close) {
            break;
        }
        const std::size_t obj_close = findMatchingBrace(line, obj_open);
        if (obj_close == std::string::npos || obj_close > array_close) {
            break;
        }

        const auto id = parseJsonUintField(line, obj_open, "\"id\"");
        const auto idx = parseJsonUintField(line, obj_open, "\"idx\"");
        const auto name = parseJsonStringField(line, obj_open, "\"name\"");
        const auto output = parseJsonStringField(line, obj_open, "\"output\"");

        if (id.has_value()) {
            std::string label;
            if (name.has_value() && !name->empty()) {
                label = *name;
            } else if (idx.has_value()) {
                label = std::format("{}", *idx);
            } else {
                label = std::format("id {}", *id);
            }

            if (output.has_value() && !output->empty()) {
                label = std::format("{}@{}", label, *output);
            }

            m_workspace_labels[*id] = std::move(label);
        }

        const std::size_t focused_pos = line.find("\"is_focused\"", obj_open);
        if (focused_pos != std::string::npos && focused_pos < obj_close) {
            const std::size_t true_pos = line.find("true", focused_pos);
            if (true_pos != std::string::npos && true_pos < obj_close && id.has_value()) {
                focused_id = *id;
            }
        }

        cursor = obj_close + 1;
    }

    if (focused_id.has_value()) {
        logFocusedWorkspace(*focused_id);
    }
}

void NiriService::handleWorkspaceActivated(const std::string& line) {
    const std::size_t focused_pos = line.find("\"focused\"");
    if (focused_pos == std::string::npos) {
        return;
    }

    const std::size_t true_pos = line.find("true", focused_pos);
    if (true_pos == std::string::npos) {
        return;
    }

    const auto id = parseJsonUintField(line, 0, "\"id\"");
    if (id.has_value()) {
        logFocusedWorkspace(*id);
    }
}

std::optional<std::string> NiriService::parseJsonStringField(const std::string& input,
                                                             std::size_t from,
                                                             const char* key) {
    const std::size_t key_pos = input.find(key, from);
    if (key_pos == std::string::npos) {
        return std::nullopt;
    }

    const std::size_t colon = input.find(':', key_pos);
    if (colon == std::string::npos) {
        return std::nullopt;
    }

    std::size_t first = input.find_first_not_of(" \t", colon + 1);
    if (first == std::string::npos) {
        return std::nullopt;
    }

    if (input.compare(first, 4, "null") == 0) {
        return std::string{};
    }

    if (input[first] != '"') {
        return std::nullopt;
    }

    ++first;
    const std::size_t end = input.find('"', first);
    if (end == std::string::npos) {
        return std::nullopt;
    }

    return input.substr(first, end - first);
}

std::optional<std::uint64_t> NiriService::parseJsonUintField(const std::string& input,
                                                             std::size_t from,
                                                             const char* key) {
    const std::size_t key_pos = input.find(key, from);
    if (key_pos == std::string::npos) {
        return std::nullopt;
    }

    const std::size_t colon = input.find(':', key_pos);
    if (colon == std::string::npos) {
        return std::nullopt;
    }

    std::size_t first = input.find_first_not_of(" \t", colon + 1);
    if (first == std::string::npos || first >= input.size() || !std::isdigit(static_cast<unsigned char>(input[first]))) {
        return std::nullopt;
    }

    std::size_t last = first;
    while (last < input.size() && std::isdigit(static_cast<unsigned char>(input[last]))) {
        ++last;
    }

    try {
        return static_cast<std::uint64_t>(std::stoull(input.substr(first, last - first)));
    } catch (...) {
        return std::nullopt;
    }
}

std::size_t NiriService::findMatchingBracket(const std::string& input, std::size_t open_pos) {
    int depth = 0;
    for (std::size_t i = open_pos; i < input.size(); ++i) {
        if (input[i] == '[') {
            ++depth;
        } else if (input[i] == ']') {
            --depth;
            if (depth == 0) {
                return i;
            }
        }
    }
    return std::string::npos;
}

std::size_t NiriService::findMatchingBrace(const std::string& input, std::size_t open_pos) {
    int depth = 0;
    for (std::size_t i = open_pos; i < input.size(); ++i) {
        if (input[i] == '{') {
            ++depth;
        } else if (input[i] == '}') {
            --depth;
            if (depth == 0) {
                return i;
            }
        }
    }
    return std::string::npos;
}

void NiriService::logFocusedWorkspace(std::uint64_t id) {
    if (m_last_focused_workspace.has_value() && *m_last_focused_workspace == id) {
        return;
    }

    m_last_focused_workspace = id;

    const auto it = m_workspace_labels.find(id);
    if (it != m_workspace_labels.end()) {
        logInfo("niri focused workspace {}", it->second);
        return;
    }

    logInfo("niri focused workspace id {}", id);
}

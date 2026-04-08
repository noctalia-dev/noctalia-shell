#include "ipc/ipc_client.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

  std::string resolveSocketPath() {
    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    if (runtime == nullptr || runtime[0] == '\0') {
      runtime = "/tmp";
    }
    const char* display = std::getenv("WAYLAND_DISPLAY");
    if (display == nullptr || display[0] == '\0') {
      display = "wayland-0";
    }
    return std::string(runtime) + "/noctalia-" + display + ".sock";
  }

} // namespace

bool IpcClient::isRunning() {
  const std::string path = resolveSocketPath();
  const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return false;
  }
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    ::close(fd);
    return false;
  }
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  const bool alive = ::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) == 0;
  ::close(fd);
  return alive;
}

int IpcClient::send(const std::string& command) {
  const std::string path = resolveSocketPath();

  const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    std::fprintf(stderr, "error: socket() failed: %s\n", std::strerror(errno));
    return 1;
  }

  // Set connect/send/recv timeout to 2 seconds
  timeval tv{};
  tv.tv_sec = 2;
  ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    std::fprintf(stderr, "error: socket path too long\n");
    ::close(fd);
    return 1;
  }
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);

  if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) {
    std::fprintf(stderr, "error: noctalia is not running\n");
    ::close(fd);
    return 1;
  }

  // Send the command with a trailing newline
  const std::string line = command + "\n";
  const auto written = ::write(fd, line.data(), line.size());
  if (written < 0) {
    std::fprintf(stderr, "error: write() failed: %s\n", std::strerror(errno));
    ::close(fd);
    return 1;
  }
  if (static_cast<std::size_t>(written) != line.size()) {
    std::fprintf(stderr, "error: short write to IPC socket\n");
    ::close(fd);
    return 1;
  }

  // Read response until EOF (server closes connection after writing)
  char buf[4096];
  int total = 0;
  while (total < static_cast<int>(sizeof(buf)) - 1) {
    const auto n = ::read(fd, buf + total, static_cast<std::size_t>(sizeof(buf) - 1 - total));
    if (n <= 0) {
      break;
    }
    total += static_cast<int>(n);
  }
  buf[total] = '\0';

  ::close(fd);

  std::fputs(buf, stdout);

  // Return 1 if the response indicates an error
  return (std::strncmp(buf, "error:", 6) == 0) ? 1 : 0;
}

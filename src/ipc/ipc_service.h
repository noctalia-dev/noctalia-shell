#pragma once

#include <functional>
#include <string>
#include <unordered_map>

class IpcService {
public:
  using Handler = std::function<std::string(const std::string& args)>;

  IpcService() = default;
  ~IpcService();

  IpcService(const IpcService&) = delete;
  IpcService& operator=(const IpcService&) = delete;

  // Creates and binds the Unix socket. Returns false if it fails (IPC disabled).
  bool start();

  // Returns the listening fd, or -1 if not started.
  [[nodiscard]] int listenFd() const noexcept { return m_listenFd; }

  // Returns the socket path used.
  [[nodiscard]] const std::string& socketPath() const noexcept { return m_socketPath; }

  // Called by IpcPollSource when POLLIN fires on the listening fd.
  void dispatch();

  // Register a handler for a command name. The handler receives everything after
  // the first space as `args`. Must return a string ending with '\n'.
  void registerHandler(const std::string& command, Handler handler);

private:
  void handleConnection(int connFd);
  [[nodiscard]] static std::string resolveSocketPath();

  int m_listenFd = -1;
  std::string m_socketPath;
  std::unordered_map<std::string, Handler> m_handlers;
};

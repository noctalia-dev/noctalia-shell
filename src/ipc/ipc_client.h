#pragma once

#include <string>

class IpcClient {
public:
  // Returns true if a noctalia instance is already running (socket is live).
  static bool isRunning();

  // Sends `command` to the running noctalia instance.
  // Prints the response to stdout. Returns 0 on success, 1 on error.
  static int send(const std::string& command);
};

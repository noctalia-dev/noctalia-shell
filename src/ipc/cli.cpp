#include "ipc/cli.h"

#include "ipc/ipc_client.h"

#include <cstdio>
#include <string>

namespace noctalia::ipc {

  int runCli(int argc, char* argv[]) {
    if (argc < 3) {
      std::fputs("error: msg requires a command (try: noctalia msg --help)\n", stderr);
      return 1;
    }
    std::string cmd = argv[2];
    for (int i = 3; i < argc; ++i) {
      cmd += ' ';
      cmd += argv[i];
    }
    return IpcClient::send(cmd);
  }

} // namespace noctalia::ipc

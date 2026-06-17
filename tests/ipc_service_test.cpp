#include "ipc/ipc_service.h"

#include <cassert>
#include <string>

int main() {
  IpcService ipc;
  ipc.registerHandler(
      "visible-command", [](const std::string& args) { return "visible:" + args + "\n"; }, "visible-command <value>",
      "Visible command"
  );
  ipc.registerHandler(
      "hidden-command", [](const std::string& args) { return "hidden:" + args + "\n"; }, "hidden-command <value>",
      "Hidden command", IpcService::HandlerVisibility::Hidden
  );

  assert(ipc.execute("visible-command ok") == "visible:ok\n");
  assert(ipc.execute("hidden-command ok") == "hidden:ok\n");

  const std::string help = ipc.execute("--help");
  assert(help.find("visible-command <value>") != std::string::npos);
  assert(help.find("Visible command") != std::string::npos);
  assert(help.find("hidden-command") == std::string::npos);
  assert(help.find("Hidden command") == std::string::npos);

  ipc.registerHandler(
      "visible-command", [](const std::string&) { return "hidden-now\n"; }, "visible-command", "Now hidden",
      IpcService::HandlerVisibility::Hidden
  );

  assert(ipc.execute("visible-command") == "hidden-now\n");
  const std::string updatedHelp = ipc.execute("--help");
  assert(updatedHelp.find("visible-command") == std::string::npos);
  assert(updatedHelp.find("Now hidden") == std::string::npos);

  return 0;
}

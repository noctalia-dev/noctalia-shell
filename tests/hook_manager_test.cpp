#include "hooks/hook_manager.h"

#include <cassert>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

std::string_view hookKindKey(HookKind kind) {
  if (kind == HookKind::WallpaperChanged) {
    return "wallpaper_changed";
  }
  return "unknown";
}

namespace {

  const char* envOrEmpty(const char* name) {
    if (const char* value = std::getenv(name)) {
      return value;
    }
    return "";
  }

} // namespace

int main() {
  constexpr const char* kPathName = "NOCTALIA_WALLPAPER_PATH";
  constexpr const char* kConnectorName = "NOCTALIA_WALLPAPER_CONNECTOR";

  ::unsetenv(kPathName);
  ::unsetenv(kConnectorName);

  HookManager hooks;
  HooksConfig config;
  config.commands[static_cast<std::size_t>(HookKind::WallpaperChanged)] = {"record-wallpaper-hook"};
  hooks.reload(config);

  std::vector<std::string> commands;
  std::string pathSeen;
  std::string connectorSeen;
  hooks.setCommandRunner([&](const std::string& command) {
    commands.push_back(command);
    pathSeen = envOrEmpty(kPathName);
    connectorSeen = envOrEmpty(kConnectorName);
    return true;
  });

  hooks.fire(HookKind::WallpaperChanged, {{kPathName, "/tmp/noctalia test/wallpaper.png"}, {kConnectorName, "DP-1"}});

  assert(commands.size() == 1);
  assert(commands[0] == "record-wallpaper-hook");
  assert(pathSeen == "/tmp/noctalia test/wallpaper.png");
  assert(connectorSeen == "DP-1");
  assert(std::getenv(kPathName) == nullptr);
  assert(std::getenv(kConnectorName) == nullptr);

  return 0;
}

#pragma once

#include <functional>
#include <string_view>

class ConfigService;
class IpcService;

namespace greeter {

  using SyncCompletion = std::function<void(bool success)>;

  // True when noctalia-greeter and the privileged apply helper are installed.
  [[nodiscard]] bool appearanceSyncAvailable();

  // Writes the current shell appearance to a staging directory, then runs
  // `pkexec noctalia-greeter-apply-appearance <staging>` so the greeter can read
  // `/var/lib/noctalia-greeter/appearance.json` on next login.
  // Returns true when the privileged helper was launched; completion is asynchronous.
  [[nodiscard]] bool syncAppearanceToGreeterAsync(
      const ConfigService& config, std::string_view resolvedThemeMode, SyncCompletion onComplete = {}
  );

  void registerIpc(IpcService& ipc, const ConfigService& config, std::function<std::string_view()> resolvedThemeMode);

} // namespace greeter

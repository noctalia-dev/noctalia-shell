#pragma once

#include <functional>
#include <string_view>

class CompositorPlatform;
class ConfigService;
class IpcService;

namespace greeter {

  using SyncCompletion = std::function<void(bool success)>;

  // True when noctalia-greeter and the privileged apply helper are installed.
  [[nodiscard]] bool appearanceSyncAvailable();

  // Writes the current shell appearance to a staging directory, then runs
  // `pkexec|run0 noctalia-greeter-apply-appearance <staging>` so the greeter can read
  // `/var/lib/noctalia-greeter/appearance.json` on next login. When multi-monitor
  // layout is available from xdg-output, also stages `output_layout` for greeter.conf.
  // Returns true when the privileged helper was launched; completion is asynchronous.
  [[nodiscard]] bool syncAppearanceToGreeterAsync(
      const ConfigService& config, std::string_view resolvedThemeMode, SyncCompletion onComplete = {},
      const CompositorPlatform* platform = nullptr
  );

  void registerIpc(
      IpcService& ipc, const ConfigService& config, std::function<std::string_view()> resolvedThemeMode,
      const CompositorPlatform* platform = nullptr
  );

} // namespace greeter

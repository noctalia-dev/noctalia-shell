#include "dbus/network/inetwork_service.h"

#include "ipc/ipc_service.h"
#include "util/string_utils.h"

#include <optional>
#include <string>
#include <string_view>

namespace {

  std::optional<std::string> rejectArgs(std::string_view command, const std::string& args) {
    if (StringUtils::trim(args).empty()) {
      return std::nullopt;
    }
    return "error: " + std::string(command) + " takes no arguments\n";
  }

} // namespace

void INetworkService::registerIpc(IpcService& ipc, WirelessFeedbackCallback wirelessFeedback) {
  auto setWifi = [this, wirelessFeedback](bool enabled) -> std::string {
    if (!hasStateSnapshot()) {
      return "error: network state unavailable\n";
    }
    if (state().wirelessEnabled == enabled) {
      return "ok\n";
    }
    setWirelessEnabled(enabled);
    if (wirelessFeedback) {
      wirelessFeedback(enabled);
    }
    return "ok\n";
  };

  ipc.registerHandler(
      "wifi-enable",
      [setWifi](const std::string& args) -> std::string {
        if (auto err = rejectArgs("wifi-enable", args); err.has_value()) {
          return *err;
        }
        return setWifi(true);
      },
      "wifi-enable", "Enable Wi-Fi"
  );

  ipc.registerHandler(
      "wifi-disable",
      [setWifi](const std::string& args) -> std::string {
        if (auto err = rejectArgs("wifi-disable", args); err.has_value()) {
          return *err;
        }
        return setWifi(false);
      },
      "wifi-disable", "Disable Wi-Fi"
  );

  ipc.registerHandler(
      "wifi-toggle",
      [this, setWifi](const std::string& args) -> std::string {
        if (auto err = rejectArgs("wifi-toggle", args); err.has_value()) {
          return *err;
        }
        if (!hasStateSnapshot()) {
          return "error: network state unavailable\n";
        }
        return setWifi(!state().wirelessEnabled);
      },
      "wifi-toggle", "Toggle Wi-Fi"
  );

  ipc.registerHandler(
      "wifi-status",
      [this](const std::string& args) -> std::string {
        if (auto err = rejectArgs("wifi-status", args); err.has_value()) {
          return *err;
        }
        if (!hasStateSnapshot()) {
          return "error: network state unavailable\n";
        }
        return state().wirelessEnabled ? "on\n" : "off\n";
      },
      "wifi-status", "Print Wi-Fi state"
  );
}

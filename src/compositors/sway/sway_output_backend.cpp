#include "compositors/sway/sway_output_backend.h"

#include "core/log.h"
#include "core/process.h"
#include "util/string_utils.h"

#include <cstdlib>
#include <json.hpp>

namespace {

  constexpr Logger kLog("sway_output");

  [[nodiscard]] std::optional<std::string> parseFocusedOutputName(std::string_view payload) {
    if (payload.empty()) {
      return std::nullopt;
    }

    try {
      const auto json = nlohmann::json::parse(payload);
      if (!json.is_array()) {
        return std::nullopt;
      }

      for (const auto& item : json) {
        if (!item.is_object() || !item.value("focused", false)) {
          continue;
        }
        if (auto it = item.find("name"); it != item.end() && it->is_string()) {
          const auto value = StringUtils::trim(it->get<std::string>());
          if (!value.empty()) {
            return value;
          }
        }
      }
    } catch (const nlohmann::json::exception&) {
      return std::nullopt;
    }

    return std::nullopt;
  }

} // namespace

SwayOutputBackend::SwayOutputBackend(std::string_view compositorHint) {
  const bool hinted = StringUtils::containsInsensitive(compositorHint, "sway");
  const char* swaySocket = std::getenv("SWAYSOCK");
  const char* i3Socket = std::getenv("I3SOCK");
  m_enabled = hinted || (swaySocket != nullptr && swaySocket[0] != '\0') || (i3Socket != nullptr && i3Socket[0] != '\0');
}

bool SwayOutputBackend::isAvailable() const noexcept { return m_enabled; }

std::optional<std::string> SwayOutputBackend::focusedOutputName() const {
  if (!m_enabled) {
    return std::nullopt;
  }

  const char* msgCommand = process::commandExists("scrollmsg") ? "scrollmsg" : "swaymsg";
  if (!process::commandExists(msgCommand)) {
    msgCommand = "i3-msg";
  }

  const auto result = process::runSync({msgCommand, "-t", "get_outputs", "-r"});
  if (!result) {
    kLog.debug("failed to resolve focused output via {}", msgCommand);
    return std::nullopt;
  }
  return parseFocusedOutputName(result.out);
}

namespace compositors::sway {

  bool setOutputPower(bool on) {
    const char* msgCommand = process::commandExists("scrollmsg") ? "scrollmsg" : "swaymsg";
    if (!process::commandExists(msgCommand)) {
      msgCommand = "i3-msg";
    }
    return process::runAsync({msgCommand, "output", "*", "dpms", on ? "on" : "off"});
  }

} // namespace compositors::sway

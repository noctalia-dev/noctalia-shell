#include "compositors/niri/niri_output_backend.h"

#include "core/log.h"
#include "util/string_utils.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <json.hpp>
#include <optional>
#include <string>
#include <string_view>

namespace {

  constexpr Logger kLog("niri_output");

  [[nodiscard]] std::string readCommand(const char* cmd) {
    FILE* pipe = ::popen(cmd, "r");
    if (pipe == nullptr) {
      return {};
    }

    std::array<char, 512> buffer{};
    std::string output;
    while (std::fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
      output += buffer.data();
    }
    ::pclose(pipe);
    return StringUtils::trim(output);
  }

  [[nodiscard]] std::optional<std::string> parseFocusedOutputName(std::string_view payload) {
    if (payload.empty()) {
      return std::nullopt;
    }

    try {
      const auto json = nlohmann::json::parse(payload);

      if (json.is_string()) {
        const auto value = StringUtils::trim(json.get<std::string>());
        return value.empty() ? std::nullopt : std::optional<std::string>{value};
      }

      if (json.is_object()) {
        if (auto it = json.find("name"); it != json.end() && it->is_string()) {
          const auto value = StringUtils::trim(it->get<std::string>());
          if (!value.empty()) {
            return value;
          }
        }
        if (auto it = json.find("output"); it != json.end()) {
          if (it->is_string()) {
            const auto value = StringUtils::trim(it->get<std::string>());
            if (!value.empty()) {
              return value;
            }
          }
          if (it->is_object()) {
            if (auto nameIt = it->find("name"); nameIt != it->end() && nameIt->is_string()) {
              const auto value = StringUtils::trim(nameIt->get<std::string>());
              if (!value.empty()) {
                return value;
              }
            }
          }
        }
      }

      if (json.is_array()) {
        for (const auto& item : json) {
          if (!item.is_object()) {
            continue;
          }
          if (auto it = item.find("name"); it != item.end() && it->is_string()) {
            const auto value = StringUtils::trim(it->get<std::string>());
            if (!value.empty()) {
              return value;
            }
          }
        }
      }
    } catch (const nlohmann::json::exception&) {
      const auto value = StringUtils::trim(std::string(payload));
      return value.empty() ? std::nullopt : std::optional<std::string>{value};
    }

    return std::nullopt;
  }

} // namespace

NiriOutputBackend::NiriOutputBackend(std::string_view compositorHint) {
  const bool hinted = StringUtils::containsInsensitive(compositorHint, "niri");
  const char* niriSocket = std::getenv("NIRI_SOCKET");
  m_enabled = hinted || (niriSocket != nullptr && niriSocket[0] != '\0');
}

bool NiriOutputBackend::isAvailable() const noexcept { return m_enabled; }

std::optional<std::string> NiriOutputBackend::focusedOutputName() const {
  if (!m_enabled) {
    return std::nullopt;
  }

  // niri changed flags over time; support both forms.
  if (auto parsed = parseFocusedOutputName(readCommand("niri msg --json focused-output 2>/dev/null"));
      parsed.has_value()) {
    return parsed;
  }
  if (auto parsed = parseFocusedOutputName(readCommand("niri msg -j focused-output 2>/dev/null")); parsed.has_value()) {
    return parsed;
  }

  kLog.debug("failed to resolve focused output from niri IPC");
  return std::nullopt;
}

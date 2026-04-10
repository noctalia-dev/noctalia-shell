#include "compositors/niri/niri_output_backend.h"

#include "core/log.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <json.hpp>
#include <optional>
#include <string>
#include <string_view>

namespace {

constexpr Logger kLog("niri_output");

[[nodiscard]] bool containsToken(std::string_view haystack, std::string_view needle) {
  if (haystack.empty() || needle.empty()) {
    return false;
  }
  std::string lhs(haystack);
  std::string rhs(needle);
  std::ranges::transform(lhs, lhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  std::ranges::transform(rhs, rhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return lhs.find(rhs) != std::string::npos;
}

[[nodiscard]] std::string trim(std::string value) {
  auto notSpace = [](unsigned char c) { return !std::isspace(c); };
  const auto begin = std::find_if(value.begin(), value.end(), notSpace);
  if (begin == value.end()) {
    return {};
  }
  const auto end = std::find_if(value.rbegin(), value.rend(), notSpace).base();
  return std::string(begin, end);
}

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
  return trim(output);
}

[[nodiscard]] std::optional<std::string> parseFocusedOutputName(std::string_view payload) {
  if (payload.empty()) {
    return std::nullopt;
  }

  try {
    const auto json = nlohmann::json::parse(payload);

    if (json.is_string()) {
      const auto value = trim(json.get<std::string>());
      return value.empty() ? std::nullopt : std::optional<std::string>{value};
    }

    if (json.is_object()) {
      if (auto it = json.find("name"); it != json.end() && it->is_string()) {
        const auto value = trim(it->get<std::string>());
        if (!value.empty()) {
          return value;
        }
      }
      if (auto it = json.find("output"); it != json.end()) {
        if (it->is_string()) {
          const auto value = trim(it->get<std::string>());
          if (!value.empty()) {
            return value;
          }
        }
        if (it->is_object()) {
          if (auto nameIt = it->find("name"); nameIt != it->end() && nameIt->is_string()) {
            const auto value = trim(nameIt->get<std::string>());
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
          const auto value = trim(it->get<std::string>());
          if (!value.empty()) {
            return value;
          }
        }
      }
    }
  } catch (const nlohmann::json::exception&) {
    const auto value = trim(std::string(payload));
    return value.empty() ? std::nullopt : std::optional<std::string>{value};
  }

  return std::nullopt;
}

} // namespace

NiriOutputBackend::NiriOutputBackend(std::string_view compositorHint) {
  const bool hinted = containsToken(compositorHint, "niri");
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

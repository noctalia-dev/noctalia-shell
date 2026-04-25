#include "system/telemetry_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "json.hpp"
#include "net/http_client.h"
#include "system/distro_info.h"
#include "system/hardware_info.h"
#include "wayland/wayland_connection.h"

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <format>
#include <fstream>
#include <string>

namespace {

  constexpr Logger kLog("telemetry");

  std::string instanceIdPath() {
    const char* xdg = std::getenv("XDG_STATE_HOME");
    std::string dir;
    if (xdg != nullptr && xdg[0] != '\0') {
      dir = std::string(xdg) + "/noctalia";
    } else {
      const char* home = std::getenv("HOME");
      if (home == nullptr || home[0] == '\0') {
        return {};
      }
      dir = std::string(home) + "/.local/state/noctalia";
    }
    return dir + "/instance.id";
  }

  std::string generateUuid() {
    std::uint8_t bytes[16]{};
    FILE* urandom = std::fopen("/dev/urandom", "rb");
    if (urandom == nullptr) {
      return {};
    }
    const std::size_t read = std::fread(bytes, 1, sizeof(bytes), urandom);
    std::fclose(urandom);
    if (read != sizeof(bytes)) {
      return {};
    }
    bytes[6] = (bytes[6] & 0x0Fu) | 0x40u;
    bytes[8] = (bytes[8] & 0x3Fu) | 0x80u;
    return std::format("{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-"
                       "{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
                       bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
                       bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
  }

  std::string loadOrCreateInstanceId() {
    const std::string path = instanceIdPath();
    if (path.empty()) {
      return {};
    }

    {
      std::ifstream in(path);
      if (in.is_open()) {
        std::string id;
        std::getline(in, id);
        if (!id.empty()) {
          return id;
        }
      }
    }

    const std::string id = generateUuid();
    if (id.empty()) {
      return {};
    }

    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
    std::ofstream out(path);
    if (out.is_open()) {
      out << id;
    }
    return id;
  }

  int memoryTotalGb() {
    std::ifstream file("/proc/meminfo");
    if (!file.is_open()) {
      return 0;
    }
    std::string line;
    while (std::getline(file, line)) {
      if (!line.starts_with("MemTotal:")) {
        continue;
      }
      const std::size_t start = line.find_first_of("0123456789");
      if (start == std::string::npos) {
        return 0;
      }
      const std::size_t end = line.find_first_not_of("0123456789", start);
      try {
        const auto kb = std::stoull(line.substr(start, end - start));
        return static_cast<int>((kb + 524288) / 1048576);
      } catch (...) {
        return 0;
      }
    }
    return 0;
  }

} // namespace

void TelemetryService::maybeSend(const ConfigService& config, HttpClient& httpClient,
                                 const WaylandConnection& wayland) {
  if (m_sent) {
    return;
  }
  m_sent = true;

  const auto& cfg = config.config().shell;
  if (!cfg.telemetryEnabled) {
    kLog.info("telemetry disabled");
    return;
  }

  const std::string instanceId = loadOrCreateInstanceId();
  if (instanceId.empty()) {
    kLog.warn("failed to load or create instance ID");
    return;
  }

  nlohmann::json monitors = nlohmann::json::array();
  for (const auto& output : wayland.outputs()) {
    if (!output.done) {
      continue;
    }
    monitors.push_back({{"width", output.width}, {"height", output.height}, {"scale", output.scale}});
  }

  nlohmann::json payload = {
      {"instanceId", instanceId},
      {"version", std::string("v") + NOCTALIA_VERSION},
      {"compositor", compositorLabel()},
      {"os", distroLabel()},
      {"ramGb", memoryTotalGb()},
      {"monitors", monitors},
      {"ui", {{"scaleRatio", cfg.uiScale}}},
  };

  kLog.info("sending anonymous ping");
  httpClient.post("https://api.noctalia.dev/ping", payload.dump(), "application/json", [](bool success) {
    if (success) {
      kLog.debug("ping sent");
    } else {
      kLog.debug("ping failed");
    }
  });
}

#include "system/hardware_info.h"

#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>

namespace {

  std::string trimWhitespace(std::string s) {
    while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\n' || s.back() == '\r')) {
      s.pop_back();
    }
    const auto start = s.find_first_not_of(" \t");
    return start == std::string::npos ? "" : s.substr(start);
  }

  std::string readCpuModel() {
    std::ifstream file{"/proc/cpuinfo"};
    if (!file.is_open()) {
      return "Unknown CPU";
    }

    std::string line;
    while (std::getline(file, line)) {
      if (line.starts_with("model name")) {
        const auto colonPos = line.find(':');
        if (colonPos != std::string::npos) {
          return trimWhitespace(line.substr(colonPos + 1));
        }
      }
    }
    return "Unknown CPU";
  }

  std::string lookupPciIds(const std::string& vendorId, const std::string& deviceId) {
    std::ifstream file{"/usr/share/hwdata/pci.ids"};
    if (!file.is_open()) {
      return {};
    }

    std::string line;
    bool inVendor = false;
    std::string vendorName;

    while (std::getline(file, line)) {
      if (line.empty() || line[0] == '#') {
        continue;
      }

      if (line[0] != '\t') {
        if (inVendor) {
          break;
        }
        if (line.starts_with(vendorId)) {
          const auto nameStart = line.find("  ");
          if (nameStart != std::string::npos) {
            vendorName = trimWhitespace(line.substr(nameStart));
            inVendor = true;
          }
        }
        continue;
      }

      if (!inVendor) {
        continue;
      }

      if (line[0] == '\t' && (line.size() < 2 || line[1] != '\t')) {
        auto stripped = trimWhitespace(line);
        if (stripped.starts_with(deviceId)) {
          const auto nameStart = stripped.find("  ");
          if (nameStart != std::string::npos) {
            auto deviceName = trimWhitespace(stripped.substr(nameStart));
            if (!deviceName.empty()) {
              return deviceName;
            }
          }
        }
      }
    }

    if (!vendorName.empty()) {
      return vendorName;
    }
    return {};
  }

  std::string readSysfsLine(const std::filesystem::path& path) {
    std::ifstream file{path};
    if (!file.is_open()) {
      return {};
    }
    std::string line;
    std::getline(file, line);
    return trimWhitespace(line);
  }

  std::string detectGpu() {
    namespace fs = std::filesystem;

    const fs::path drmRoot{"/sys/class/drm"};
    if (!fs::exists(drmRoot) || !fs::is_directory(drmRoot)) {
      return "Unknown GPU";
    }

    for (const auto& entry : fs::directory_iterator{drmRoot}) {
      const auto name = entry.path().filename().string();
      if (!name.starts_with("card") || name.find('-') != std::string::npos) {
        continue;
      }

      const auto deviceDir = entry.path() / "device";
      if (!fs::exists(deviceDir)) {
        continue;
      }

      auto driverLine = readSysfsLine(deviceDir / "uevent");
      // uevent has multiple lines; re-read and search for DRIVER=
      std::string driver;
      {
        std::ifstream uevent{deviceDir / "uevent"};
        std::string line;
        while (std::getline(uevent, line)) {
          if (line.starts_with("DRIVER=")) {
            driver = line.substr(7);
            break;
          }
        }
      }

      if (driver == "simpledrm") {
        continue;
      }

      auto vendorHex = readSysfsLine(deviceDir / "vendor");
      auto deviceHex = readSysfsLine(deviceDir / "device");

      // Strip 0x prefix
      if (vendorHex.starts_with("0x") || vendorHex.starts_with("0X")) {
        vendorHex = vendorHex.substr(2);
      }
      if (deviceHex.starts_with("0x") || deviceHex.starts_with("0X")) {
        deviceHex = deviceHex.substr(2);
      }

      if (!vendorHex.empty() && !deviceHex.empty()) {
        auto pciName = lookupPciIds(vendorHex, deviceHex);
        if (!pciName.empty()) {
          return pciName;
        }
      }

      if (!driver.empty()) {
        if (driver == "i915" || driver == "xe") {
          return "Intel GPU (" + driver + ")";
        }
        if (driver == "amdgpu" || driver == "radeon") {
          return "AMD GPU (" + driver + ")";
        }
        if (driver == "nvidia" || driver == "nouveau") {
          return "NVIDIA GPU (" + driver + ")";
        }
        return driver + " GPU";
      }
    }

    return "Unknown GPU";
  }

} // namespace

std::string cpuModelName() {
  static std::once_flag flag;
  static std::string cached;
  std::call_once(flag, [&]() { cached = readCpuModel(); });
  return cached;
}

std::string gpuLabel() {
  static std::once_flag flag;
  static std::string cached;
  std::call_once(flag, [&]() { cached = detectGpu(); });
  return cached;
}

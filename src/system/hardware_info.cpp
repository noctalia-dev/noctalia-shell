#include "system/hardware_info.h"

#include "compositors/compositor_detect.h"

#include <cstdlib>
#include <filesystem>
#include <format>
#include <fstream>
#include <mutex>
#include <string>
#include <sys/statvfs.h>

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

  std::string readDmiField(const char* path) { return readSysfsLine(path); }

  std::string detectMotherboard() {
    const std::string boardVendor = readDmiField("/sys/class/dmi/id/board_vendor");
    const std::string boardName = readDmiField("/sys/class/dmi/id/board_name");
    const std::string productName = readDmiField("/sys/class/dmi/id/product_name");

    if (!boardVendor.empty() && !boardName.empty()) {
      return boardVendor + " " + boardName;
    }
    if (!boardName.empty()) {
      return boardName;
    }
    if (!productName.empty()) {
      return productName;
    }
    return "Unknown";
  }

  std::string detectMemoryTotal() {
    std::ifstream file{"/proc/meminfo"};
    if (!file.is_open()) {
      return "Unknown";
    }
    std::string line;
    while (std::getline(file, line)) {
      if (!line.starts_with("MemTotal:")) {
        continue;
      }
      const std::size_t valueStart = line.find_first_of("0123456789");
      if (valueStart == std::string::npos) {
        break;
      }
      const std::size_t valueEnd = line.find_first_not_of("0123456789", valueStart);
      const std::string kbText = line.substr(valueStart, valueEnd - valueStart);
      std::uint64_t totalKb = 0;
      try {
        totalKb = static_cast<std::uint64_t>(std::stoull(kbText));
      } catch (...) {
        return "Unknown";
      }
      const double totalGb = static_cast<double>(totalKb) / (1024.0 * 1024.0);
      return std::format("{:.1f} GB", totalGb);
    }
    return "Unknown";
  }

  std::string detectDiskRootUsage() {
    struct statvfs sv{};
    if (::statvfs("/", &sv) != 0 || sv.f_blocks == 0 || sv.f_frsize == 0) {
      return "Unknown";
    }
    const double total = static_cast<double>(sv.f_blocks) * static_cast<double>(sv.f_frsize);
    const double avail = static_cast<double>(sv.f_bavail) * static_cast<double>(sv.f_frsize);
    const double used = std::max(0.0, total - avail);
    const double usedGb = used / (1024.0 * 1024.0 * 1024.0);
    const double totalGb = total / (1024.0 * 1024.0 * 1024.0);
    const double percent = total > 0.0 ? (used / total) * 100.0 : 0.0;
    return std::format("{:.1f} / {:.1f} GB ({:.0f}%)", usedGb, totalGb, percent);
  }

  std::string detectCompositor() {
    const auto kind = compositors::detect();
    if (kind != compositors::CompositorKind::Unknown) {
      return std::string(compositors::name(kind));
    }
    // Fall back to whatever the desktop env vars say, which is friendlier than "Unknown"
    // for compositors we don't have a backend for (KDE, GNOME, etc.).
    if (const char* desktop = std::getenv("XDG_CURRENT_DESKTOP"); desktop != nullptr && desktop[0] != '\0') {
      return desktop;
    }
    if (const char* sessionDesktop = std::getenv("XDG_SESSION_DESKTOP");
        sessionDesktop != nullptr && sessionDesktop[0] != '\0') {
      return sessionDesktop;
    }
    return "Unknown";
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

std::string motherboardLabel() {
  static std::once_flag flag;
  static std::string cached;
  std::call_once(flag, [&]() { cached = detectMotherboard(); });
  return cached;
}

std::string memoryTotalLabel() {
  static std::once_flag flag;
  static std::string cached;
  std::call_once(flag, [&]() { cached = detectMemoryTotal(); });
  return cached;
}

std::string diskRootUsageLabel() { return detectDiskRootUsage(); }

std::string compositorLabel() { return detectCompositor(); }

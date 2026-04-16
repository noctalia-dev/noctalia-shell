#include "system/brightness_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <dirent.h>
#include <filesystem>
#include <fstream>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <sys/inotify.h>
#include <unistd.h>

namespace {

  constexpr Logger kLog("brightness");

  namespace fs = std::filesystem;

  // ── Backend enum (private) ──────────────────────────────────────────────────

  enum class BrightnessBackend : std::uint8_t {
    Backlight,
    // DdcCi,
    // Wayland,
  };

  // ── Per-display internal state ──────────────────────────────────────────────

  struct DisplayInternal {
    BrightnessDisplay pub;
    BrightnessBackend backend = BrightnessBackend::Backlight;
    int maxRaw = 0;
    std::string sysfsPath;     // e.g. "/sys/class/backlight/intel_backlight"
    std::string connectorName; // matched wayland connector, or empty
    int inotifyWd = -1;
  };

  // ── logind D-Bus constants ──────────────────────────────────────────────────

  static const sdbus::ServiceName k_logindBusName{"org.freedesktop.login1"};
  static constexpr auto k_logindManagerInterface = "org.freedesktop.login1.Manager";
  static constexpr auto k_logindSessionInterface = "org.freedesktop.login1.Session";
  // ── sysfs helpers ───────────────────────────────────────────────────────────

  int readSysfsInt(const std::string& path) {
    std::ifstream f(path);
    int value = -1;
    if (f.is_open()) {
      f >> value;
    }
    return value;
  }

  float readBrightness(const std::string& sysfsPath, int maxRaw) {
    if (maxRaw <= 0) {
      return 0.0f;
    }
    const int actual = readSysfsInt(sysfsPath + "/actual_brightness");
    if (actual < 0) {
      return 0.0f;
    }
    return std::clamp(static_cast<float>(actual) / static_cast<float>(maxRaw), 0.0f, 1.0f);
  }

  // Try to resolve which wayland connector a backlight belongs to by following the
  // sysfs device tree. Returns empty string if no match found.
  std::string resolveConnector(const std::string& sysfsPath, const WaylandConnection& wayland) {
    // Follow /sys/class/backlight/<name>/device to find parent PCI/platform device,
    // then look for DRM connector directories in its children.
    std::error_code ec;
    const auto deviceLink = fs::read_symlink(sysfsPath + "/device", ec);
    if (ec) {
      // No device symlink — try heuristic: if there's exactly one eDP output, assume it.
      for (const auto& output : wayland.outputs()) {
        if (output.connectorName.starts_with("eDP")) {
          return output.connectorName;
        }
      }
      return {};
    }

    const auto devicePath = fs::canonical(sysfsPath + "/device", ec);
    if (ec) {
      return {};
    }

    // Walk /sys/class/drm/ looking for connectors whose device resolves to our parent.
    const std::string drmClassPath = "/sys/class/drm";
    DIR* dir = ::opendir(drmClassPath.c_str());
    if (dir == nullptr) {
      return {};
    }

    std::string match;
    while (auto* entry = ::readdir(dir)) {
      const std::string name = entry->d_name;
      // DRM connector dirs look like "card0-eDP-1", "card1-HDMI-A-1", etc.
      if (name.find('-') == std::string::npos) {
        continue;
      }

      const auto drmDevicePath = fs::canonical(drmClassPath + "/" + name + "/device", ec);
      if (ec) {
        continue;
      }

      if (drmDevicePath == devicePath) {
        // Extract connector name: strip "cardN-" prefix
        const auto dashPos = name.find('-');
        if (dashPos != std::string::npos) {
          const std::string connector = name.substr(dashPos + 1);
          // Verify this connector exists in wayland outputs
          for (const auto& output : wayland.outputs()) {
            if (output.connectorName == connector) {
              match = connector;
              break;
            }
          }
          if (!match.empty()) {
            break;
          }
        }
      }
    }
    ::closedir(dir);

    // Fallback: if still no match and single eDP, assume it
    if (match.empty()) {
      for (const auto& output : wayland.outputs()) {
        if (output.connectorName.starts_with("eDP")) {
          match = output.connectorName;
          break;
        }
      }
    }

    return match;
  }

  // ── logind session path resolution ──────────────────────────────────────────

  sdbus::ObjectPath resolveSessionPath(sdbus::IConnection& connection) {
    try {
      auto managerProxy = sdbus::createProxy(connection, k_logindBusName, sdbus::ObjectPath{"/org/freedesktop/login1"});

      // GetSessionByPID(0) returns the session of the calling process.
      sdbus::ObjectPath sessionPath;
      managerProxy->callMethod("GetSessionByPID")
          .onInterface(k_logindManagerInterface)
          .withArguments(static_cast<std::uint32_t>(0))
          .storeResultsTo(sessionPath);
      return sessionPath;
    } catch (const sdbus::Error& e) {
      kLog.warn("failed to resolve logind session: {}", e.what());
      return sdbus::ObjectPath{"/org/freedesktop/login1/session/auto"};
    }
  }

} // namespace

// ── Impl ────────────────────────────────────────────────────────────────────

struct BrightnessService::Impl {
  SystemBus& bus;
  WaylandConnection& wayland;
  ChangeCallback changeCallback;
  std::vector<BrightnessDisplay> publicDisplays;
  std::vector<DisplayInternal> internals;
  std::unique_ptr<sdbus::IProxy> sessionProxy;
  sdbus::ObjectPath sessionPath;
  int inotifyFd = -1;

  Impl(SystemBus& b, WaylandConnection& w) : bus(b), wayland(w) {}

  ~Impl() {
    if (inotifyFd >= 0) {
      for (auto& d : internals) {
        if (d.inotifyWd >= 0) {
          inotify_rm_watch(inotifyFd, d.inotifyWd);
        }
      }
      ::close(inotifyFd);
    }
  }

  void enumerate() {
    internals.clear();

    // Set up inotify
    if (inotifyFd < 0) {
      inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
      if (inotifyFd < 0) {
        kLog.warn("inotify_init1 failed, external brightness changes won't be tracked");
      }
    }

    // Resolve logind session
    sessionPath = resolveSessionPath(bus.connection());
    sessionProxy = sdbus::createProxy(bus.connection(), k_logindBusName, sessionPath);

    // Scan /sys/class/backlight/
    const std::string backlightDir = "/sys/class/backlight";
    DIR* dir = ::opendir(backlightDir.c_str());
    if (dir == nullptr) {
      kLog.debug("no /sys/class/backlight directory");
      rebuildPublic();
      return;
    }

    while (auto* entry = ::readdir(dir)) {
      const std::string name = entry->d_name;
      if (name == "." || name == "..") {
        continue;
      }

      const std::string path = backlightDir + "/" + name;
      const int maxBrightness = readSysfsInt(path + "/max_brightness");
      if (maxBrightness <= 0) {
        kLog.debug("skipping {} (max_brightness={})", name, maxBrightness);
        continue;
      }

      DisplayInternal d;
      d.backend = BrightnessBackend::Backlight;
      d.maxRaw = maxBrightness;
      d.sysfsPath = path;
      d.connectorName = resolveConnector(path, wayland);
      d.pub.id = name;
      d.pub.brightness = readBrightness(path, maxBrightness);

      // Use connector name as label if resolved, otherwise the sysfs name
      if (!d.connectorName.empty()) {
        // Find the wayland output description for a friendlier label
        for (const auto& output : wayland.outputs()) {
          if (output.connectorName == d.connectorName) {
            d.pub.label = output.description.empty() ? d.connectorName : output.description;
            break;
          }
        }
      }
      if (d.pub.label.empty()) {
        d.pub.label = name;
      }

      // Watch actual_brightness for external changes
      if (inotifyFd >= 0) {
        const std::string watchPath = path + "/actual_brightness";
        d.inotifyWd = inotify_add_watch(inotifyFd, watchPath.c_str(), IN_MODIFY);
        if (d.inotifyWd < 0) {
          kLog.debug("inotify_add_watch failed for {}", watchPath);
        }
      }

      kLog.info("found backlight '{}' max={} current={:.0f}% connector={}", name, maxBrightness,
                d.pub.brightness * 100.0f, d.connectorName.empty() ? "(none)" : d.connectorName);

      internals.push_back(std::move(d));
    }
    ::closedir(dir);

    rebuildPublic();
  }

  void rebuildPublic() {
    publicDisplays.clear();
    publicDisplays.reserve(internals.size());
    for (const auto& d : internals) {
      publicDisplays.push_back(d.pub);
    }
  }

  DisplayInternal* findInternal(const std::string& id) {
    for (auto& d : internals) {
      if (d.pub.id == id) {
        return &d;
      }
    }
    return nullptr;
  }

  void setBrightness(const std::string& displayId, float value) {
    auto* d = findInternal(displayId);
    if (d == nullptr) {
      return;
    }

    value = std::clamp(value, 0.0f, 1.0f);

    switch (d->backend) {
    case BrightnessBackend::Backlight:
      setBrightnessBacklight(*d, value);
      break;
    }
  }

  void setBrightnessBacklight(DisplayInternal& d, float value) {
    const auto rawValue = static_cast<std::uint32_t>(std::round(value * static_cast<float>(d.maxRaw)));

    try {
      sessionProxy->callMethod("SetBrightness")
          .onInterface(k_logindSessionInterface)
          .withArguments(std::string("backlight"), d.pub.id, rawValue);
    } catch (const sdbus::Error& e) {
      kLog.warn("SetBrightness failed for '{}': {}", d.pub.id, e.what());
      return;
    }

    d.pub.brightness = value;
    syncPublicDisplay(d);
  }

  void syncPublicDisplay(const DisplayInternal& d) {
    for (auto& pub : publicDisplays) {
      if (pub.id == d.pub.id) {
        pub.brightness = d.pub.brightness;
        break;
      }
    }
  }

  void handleInotify() {
    if (inotifyFd < 0) {
      return;
    }

    alignas(inotify_event) char buf[4096];
    bool changed = false;

    while (true) {
      const auto n = ::read(inotifyFd, buf, sizeof(buf));
      if (n <= 0) {
        break;
      }

      std::size_t offset = 0;
      while (offset < static_cast<std::size_t>(n)) {
        // Consume the event — we just need to know something changed
        auto* event = reinterpret_cast<inotify_event*>(buf + offset);
        offset += sizeof(inotify_event) + event->len;

        // Find which display this wd belongs to and refresh its brightness
        for (auto& d : internals) {
          if (d.inotifyWd == event->wd) {
            const float newBrightness = readBrightness(d.sysfsPath, d.maxRaw);
            if (std::abs(newBrightness - d.pub.brightness) > 0.001f) {
              d.pub.brightness = newBrightness;
              syncPublicDisplay(d);
              changed = true;
            }
            break;
          }
        }
      }
    }

    if (changed && changeCallback) {
      changeCallback();
    }
  }

  const BrightnessDisplay* findByOutput(wl_output* output) const {
    if (output == nullptr) {
      return nullptr;
    }
    auto* wlOutput = wayland.findOutputByWl(output);
    if (wlOutput == nullptr) {
      return nullptr;
    }

    for (const auto& d : internals) {
      if (d.connectorName == wlOutput->connectorName) {
        // Return from the public vector for stable pointers
        for (const auto& pub : publicDisplays) {
          if (pub.id == d.pub.id) {
            return &pub;
          }
        }
      }
    }

    // Fallback: if only one display, return it
    if (publicDisplays.size() == 1) {
      return &publicDisplays[0];
    }

    return nullptr;
  }
};

// ── BrightnessService public methods ────────────────────────────────────────

BrightnessService::BrightnessService(SystemBus& bus, WaylandConnection& wayland) : m_impl(new Impl(bus, wayland)) {
  m_impl->enumerate();
}

BrightnessService::~BrightnessService() { delete m_impl; }

const std::vector<BrightnessDisplay>& BrightnessService::displays() const noexcept { return m_impl->publicDisplays; }

const BrightnessDisplay* BrightnessService::findDisplay(const std::string& id) const {
  for (const auto& d : m_impl->publicDisplays) {
    if (d.id == id) {
      return &d;
    }
  }
  return nullptr;
}

const BrightnessDisplay* BrightnessService::findByOutput(wl_output* output) const {
  return m_impl->findByOutput(output);
}

bool BrightnessService::available() const noexcept { return !m_impl->publicDisplays.empty(); }

void BrightnessService::setBrightness(const std::string& displayId, float value) {
  m_impl->setBrightness(displayId, value);
}

void BrightnessService::setChangeCallback(ChangeCallback callback) { m_impl->changeCallback = std::move(callback); }

int BrightnessService::watchFd() const noexcept { return m_impl->inotifyFd; }

void BrightnessService::dispatchWatch() { m_impl->handleInotify(); }

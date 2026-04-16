#pragma once

#include <functional>
#include <string>
#include <vector>

class SystemBus;
class WaylandConnection;
struct wl_output;

struct BrightnessDisplay {
  std::string id;       // opaque unique key
  std::string label;    // human-readable (connector name or description)
  float brightness = 0; // 0.0–1.0 normalized
};

class BrightnessService {
public:
  using ChangeCallback = std::function<void()>;

  BrightnessService(SystemBus& bus, WaylandConnection& wayland);
  ~BrightnessService();

  BrightnessService(const BrightnessService&) = delete;
  BrightnessService& operator=(const BrightnessService&) = delete;

  [[nodiscard]] const std::vector<BrightnessDisplay>& displays() const noexcept;
  [[nodiscard]] const BrightnessDisplay* findDisplay(const std::string& id) const;
  [[nodiscard]] const BrightnessDisplay* findByOutput(wl_output* output) const;
  [[nodiscard]] bool available() const noexcept;

  void setBrightness(const std::string& displayId, float value);

  void setChangeCallback(ChangeCallback callback);

  // Poll integration — inotify fd for external brightness changes.
  [[nodiscard]] int watchFd() const noexcept;
  void dispatchWatch();

private:
  struct Impl;
  Impl* m_impl;
};

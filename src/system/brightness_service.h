#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

class IpcService;
class SystemBus;
class WaylandConnection;
struct BrightnessConfig;
struct wl_output;

struct BrightnessDisplay {
  std::string id;       // stable display id (usually connector name)
  std::string label;    // human-readable (connector name or description)
  float brightness = 0; // 0.0–1.0 normalized
  std::int32_t physicalWidth = 0;
  std::int32_t physicalHeight = 0;
  std::int32_t logicalWidth = 0;
  std::int32_t logicalHeight = 0;
  std::int32_t scale = 1;

  bool operator==(const BrightnessDisplay&) const = default;
};

class BrightnessService {
public:
  using ChangeCallback = std::function<void()>;

  BrightnessService(SystemBus* bus, WaylandConnection& wayland, const BrightnessConfig& config);
  ~BrightnessService();

  BrightnessService(const BrightnessService&) = delete;
  BrightnessService& operator=(const BrightnessService&) = delete;

  [[nodiscard]] const std::vector<BrightnessDisplay>& displays() const noexcept;
  [[nodiscard]] const BrightnessDisplay* findDisplay(const std::string& id) const;
  [[nodiscard]] const BrightnessDisplay* findByOutput(wl_output* output) const;
  [[nodiscard]] bool available() const noexcept;

  void setBrightness(const std::string& displayId, float value);
  void reload(const BrightnessConfig& config);
  void onOutputsChanged();
  void registerIpc(IpcService& ipc, std::function<void()> onBatchChange = {});

  void setChangeCallback(ChangeCallback callback);

  // Poll integration — inotify fd for external brightness changes.
  [[nodiscard]] int watchFd() const noexcept;
  void dispatchWatch();

private:
  struct Impl;
  Impl* m_impl;
};

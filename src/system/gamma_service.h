#pragma once

#include "config/config_service.h"
#include "core/timer_manager.h"

#include <chrono>
#include <cstdint>
#include <functional>
#include <list>
#include <optional>
#include <string>
#include <string_view>

class IpcService;
class WaylandConnection;
struct wl_output;
struct zwlr_gamma_control_v1;

class GammaService {
public:
  using ChangeCallback = std::function<void()>;

  explicit GammaService(WaylandConnection& wayland);
  ~GammaService();

  GammaService(const GammaService&) = delete;
  GammaService& operator=(const GammaService&) = delete;

  void reload(const NightLightConfig& config);
  void setWeatherLocationConfigured(bool configured);
  void setWeatherCoordinates(std::optional<double> latitude, std::optional<double> longitude);
  void setEnabled(bool enabled);
  void toggleEnabled();
  void setForceEnabled(bool enabled);
  void toggleForceEnabled();
  void clearForceOverride();
  void setChangeCallback(ChangeCallback callback);
  void onOutputsChanged();
  void reevaluateSchedule();

  [[nodiscard]] bool enabled() const;
  [[nodiscard]] bool forceEnabled() const;
  [[nodiscard]] bool active() const;

  void registerIpc(IpcService& ipc);

  static void onGammaSize(void* data, zwlr_gamma_control_v1* ctrl, std::uint32_t size);
  static void onGammaFailed(void* data, zwlr_gamma_control_v1* ctrl);

private:
  [[nodiscard]] bool effectiveConfiguredEnabled() const;
  [[nodiscard]] bool effectiveEnabled() const;
  [[nodiscard]] bool effectiveForce() const;

  struct GeoCoordinates {
    std::optional<double> latitude;
    std::optional<double> longitude;
  };
  [[nodiscard]] bool hasWeatherCoordinates() const;
  [[nodiscard]] GeoCoordinates scheduleCoordinates() const;

  [[nodiscard]] bool isManualMode() const;
  [[nodiscard]] bool isManualNightPhase() const;
  [[nodiscard]] std::chrono::milliseconds msUntilNextManualBoundary() const;
  [[nodiscard]] std::optional<std::string> normalizedClock(std::string_view value) const;
  void scheduleManualTimer();

  struct SolarTimes {
    int sunriseMinutes = 0;
    int sunsetMinutes = 0;
  };
  [[nodiscard]] SolarTimes computeSolarTimes(double latitude, double longitude) const;
  [[nodiscard]] bool isGeoNightPhase() const;
  [[nodiscard]] std::chrono::milliseconds msUntilNextGeoBoundary() const;
  void scheduleGeoTimer();

  void apply();
  [[nodiscard]] int targetTemperature() const;
  [[nodiscard]] bool isNightPhase() const;

  struct OutputGamma {
    wl_output* wlOutput = nullptr;
    zwlr_gamma_control_v1* control = nullptr;
    std::uint32_t gammaSize = 0;
    bool ready = false;
    GammaService* owner = nullptr;
  };

  void syncOutputs();
  void destroyOutputGamma(OutputGamma& og);
  void applyGammaToOutput(OutputGamma& og, int kelvin);
  void applyGammaToAll(int kelvin);
  void restoreAll();

  void startTransition(int fromKelvin, int toKelvin);
  void stopTransition();
  void tickTransition();

  struct RgbMultipliers {
    double r = 1.0;
    double g = 1.0;
    double b = 1.0;
  };
  [[nodiscard]] static RgbMultipliers kelvinToRgb(int kelvin);
  static void fillGammaRamp(std::uint16_t* ramp, std::uint32_t size, const RgbMultipliers& mul);

  WaylandConnection& m_wayland;
  NightLightConfig m_config;
  std::optional<bool> m_enabledOverride;
  std::optional<bool> m_forceOverride;
  bool m_weatherLocationConfigured = false;
  std::optional<double> m_weatherLatitude;
  std::optional<double> m_weatherLongitude;
  ChangeCallback m_changeCallback;

  std::list<OutputGamma> m_outputs;

  int m_currentKelvin = -1;
  int m_targetKelvin = -1;
  int m_transitionFromKelvin = -1;
  float m_transitionProgress = 0.0f;
  std::chrono::steady_clock::time_point m_transitionStart{};
  Timer m_transitionTimer;

  bool m_restoreAfterTransition = false;
  Timer m_scheduleTimer;
  bool m_gammaUnavailableLogged = false;
};

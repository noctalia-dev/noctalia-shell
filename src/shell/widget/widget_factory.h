#pragma once

#include "shell/widget/widget.h"

#include <memory>
#include <string>

struct Config;
class NotificationManager;
class HttpClient;
class IdleInhibitor;
class MprisService;
class NetworkService;
class PipeWireService;
class PipeWireSpectrum;
class PowerProfilesService;
class TrayService;
class SystemMonitorService;
class UPowerService;
class WeatherService;
struct wl_output;
class NightLightManager;
class TimeService;
class WaylandConnection;
namespace noctalia::theme {
  class ThemeService;
}

class WidgetFactory {
public:
  WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config, NotificationManager* notifications,
                TrayService* tray, PipeWireService* audio, UPowerService* upower, SystemMonitorService* sysmon,
                PowerProfilesService* powerProfiles, NetworkService* network, IdleInhibitor* idleInhibitor,
                MprisService* mpris, PipeWireSpectrum* audioSpectrum, HttpClient* httpClient, WeatherService* weather,
                NightLightManager* nightLight, noctalia::theme::ThemeService* themeService);

  [[nodiscard]] std::unique_ptr<Widget> create(const std::string& name, wl_output* output,
                                               float contentScale = 1.0f) const;

private:
  WaylandConnection& m_wayland;
  TimeService* m_time;
  const Config& m_config;
  NotificationManager* m_notifications;
  TrayService* m_tray;
  PipeWireService* m_audio;
  UPowerService* m_upower;
  SystemMonitorService* m_sysmon;
  PowerProfilesService* m_powerProfiles;
  NetworkService* m_network;
  IdleInhibitor* m_idleInhibitor;
  MprisService* m_mpris;
  PipeWireSpectrum* m_audioSpectrum;
  HttpClient* m_httpClient;
  WeatherService* m_weather;
  NightLightManager* m_nightLight;
  noctalia::theme::ThemeService* m_themeService;
};

#pragma once

class BluetoothService;
class ConfigService;
class DependencyService;
class IdleInhibitor;
class MprisService;
class NetworkService;
class NightLightManager;
class NotificationManager;
class PipeWireService;
class PowerProfilesService;
class WeatherService;
class WaylandConnection;

namespace noctalia::theme {
  class ThemeService;
}

struct ShortcutServices {
  NetworkService* network = nullptr;
  BluetoothService* bluetooth = nullptr;
  NightLightManager* nightLight = nullptr;
  noctalia::theme::ThemeService* theme = nullptr;
  NotificationManager* notifications = nullptr;
  IdleInhibitor* idleInhibitor = nullptr;
  PipeWireService* audio = nullptr;
  PowerProfilesService* powerProfiles = nullptr;
  MprisService* mpris = nullptr;
  WeatherService* weather = nullptr;
  ConfigService* config = nullptr;
  DependencyService* dependencies = nullptr;
  WaylandConnection* wayland = nullptr;
};

#pragma once

class ConfigService;
class HttpClient;
class WaylandConnection;

class TelemetryService {
public:
  void maybeSend(const ConfigService& config, HttpClient& httpClient, const WaylandConnection& wayland);

private:
  bool m_sent = false;
};

#pragma once

#include <chrono>
#include <cstdint>

class OsdOverlay;
class PipeWireService;

class AudioOsd {
public:
  void bindOverlay(OsdOverlay& overlay);
  void primeFromService(const PipeWireService& service);
  void suppressFor(std::chrono::milliseconds duration);
  void showOutput(std::uint32_t sinkId, float volume, bool muted);
  void showInput(std::uint32_t sourceId, float volume, bool muted);
  void onAudioStateChanged(const PipeWireService& service);

private:
  OsdOverlay* m_overlay = nullptr;
  std::uint32_t m_lastSinkId = 0;
  int m_lastSinkPercent = -1;
  bool m_lastSinkMuted = false;
  std::uint32_t m_lastSourceId = 0;
  int m_lastSourcePercent = -1;
  bool m_lastSourceMuted = false;
  std::chrono::steady_clock::time_point m_suppressUntil{};
};

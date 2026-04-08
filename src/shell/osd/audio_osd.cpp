#include "shell/osd/audio_osd.h"

#include "pipewire/pipewire_service.h"
#include "shell/osd/osd_overlay.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace {

const char* volumeIconName(float volume, bool muted) {
  if (muted || volume <= 0.0f) {
    return "volume-mute";
  }
  if (volume < 0.4f) {
    return "volume-low";
  }
  return "volume-high";
}

OsdContent makeOutputContent(float volume, bool muted) {
  const int percent = static_cast<int>(std::round(std::max(0.0f, volume) * 100.0f));
  return OsdContent{
      .icon = volumeIconName(volume, muted),
      .value = std::to_string(percent) + "%",
      .progress = std::clamp(volume, 0.0f, 1.0f),
  };
}

OsdContent makeInputContent(float volume, bool muted) {
  const int percent = static_cast<int>(std::round(std::max(0.0f, volume) * 100.0f));
  return OsdContent{
      .icon = muted ? "microphone-mute" : "microphone",
      .value = std::to_string(percent) + "%",
      .progress = std::clamp(volume, 0.0f, 1.0f),
  };
}

} // namespace

void AudioOsd::bindOverlay(OsdOverlay& overlay) { m_overlay = &overlay; }

void AudioOsd::primeFromService(const PipeWireService& service) {
  if (const auto* sink = service.defaultSink(); sink != nullptr) {
    m_lastSinkId = sink->id;
    m_lastSinkPercent = static_cast<int>(std::round(std::max(0.0f, sink->volume) * 100.0f));
    m_lastSinkMuted = sink->muted;
  }

  if (const auto* source = service.defaultSource(); source != nullptr) {
    m_lastSourceId = source->id;
    m_lastSourcePercent = static_cast<int>(std::round(std::max(0.0f, source->volume) * 100.0f));
    m_lastSourceMuted = source->muted;
  }
}

void AudioOsd::suppressFor(std::chrono::milliseconds duration) {
  m_suppressUntil = std::chrono::steady_clock::now() + duration;
}

void AudioOsd::showOutput(std::uint32_t sinkId, float volume, bool muted) {
  if (std::chrono::steady_clock::now() < m_suppressUntil) {
    return;
  }
  if (m_overlay != nullptr) {
    m_overlay->show(makeOutputContent(volume, muted));
  }
  m_lastSinkId = sinkId;
  m_lastSinkPercent = static_cast<int>(std::round(std::max(0.0f, volume) * 100.0f));
  m_lastSinkMuted = muted;
}

void AudioOsd::showInput(std::uint32_t sourceId, float volume, bool muted) {
  if (std::chrono::steady_clock::now() < m_suppressUntil) {
    return;
  }
  if (m_overlay != nullptr) {
    m_overlay->show(makeInputContent(volume, muted));
  }
  m_lastSourceId = sourceId;
  m_lastSourcePercent = static_cast<int>(std::round(std::max(0.0f, volume) * 100.0f));
  m_lastSourceMuted = muted;
}

void AudioOsd::onAudioStateChanged(const PipeWireService& service) {
  const auto* sink = service.defaultSink();
  const auto* source = service.defaultSource();

  const std::uint32_t sinkId = sink != nullptr ? sink->id : 0;
  const int sinkPercent =
      sink != nullptr ? static_cast<int>(std::round(std::max(0.0f, sink->volume) * 100.0f)) : 0;
  const bool sinkMuted = sink != nullptr ? sink->muted : false;

  const std::uint32_t sourceId = source != nullptr ? source->id : 0;
  const int sourcePercent =
      source != nullptr ? static_cast<int>(std::round(std::max(0.0f, source->volume) * 100.0f)) : 0;
  const bool sourceMuted = source != nullptr ? source->muted : false;

  if (std::chrono::steady_clock::now() < m_suppressUntil) {
    m_lastSinkId = sinkId;
    m_lastSinkPercent = sinkPercent;
    m_lastSinkMuted = sinkMuted;
    m_lastSourceId = sourceId;
    m_lastSourcePercent = sourcePercent;
    m_lastSourceMuted = sourceMuted;
    return;
  }

  if (m_overlay != nullptr) {
    if (sink != nullptr &&
        (sinkId != m_lastSinkId || sinkPercent != m_lastSinkPercent || sinkMuted != m_lastSinkMuted)) {
      m_overlay->show(makeOutputContent(sink->volume, sinkMuted));
    } else if (source != nullptr && (sourceId != m_lastSourceId || sourcePercent != m_lastSourcePercent ||
                                     sourceMuted != m_lastSourceMuted)) {
      m_overlay->show(makeInputContent(source->volume, sourceMuted));
    }
  }

  m_lastSinkId = sinkId;
  m_lastSinkPercent = sinkPercent;
  m_lastSinkMuted = sinkMuted;
  m_lastSourceId = sourceId;
  m_lastSourcePercent = sourcePercent;
  m_lastSourceMuted = sourceMuted;
}

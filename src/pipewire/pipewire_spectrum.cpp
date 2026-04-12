#include "pipewire/pipewire_spectrum.h"

#include "core/log.h"
#include "pipewire/pipewire_service.h"

#include <pipewire/core.h>
#include <pipewire/keys.h>
#include <pipewire/properties.h>
#include <pipewire/stream.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/audio/raw.h>
#include <spa/param/format-utils.h>
#include <spa/pod/pod.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>
#include <utility>

namespace {

  constexpr Logger kLog{"pipewire_spectrum"};

  class BufferRequeueGuard {
  public:
    BufferRequeueGuard(pw_stream* stream, pw_buffer* buffer) : m_stream(stream), m_buffer(buffer) {}
    ~BufferRequeueGuard() {
      if (m_stream != nullptr && m_buffer != nullptr) {
        pw_stream_queue_buffer(m_stream, m_buffer);
      }
    }

  private:
    pw_stream* m_stream = nullptr;
    pw_buffer* m_buffer = nullptr;
  };

  void fft(std::complex<float>* data, int n) {
    for (int i = 1, j = 0; i < n; ++i) {
      int bit = n >> 1;
      for (; j & bit; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        std::swap(data[i], data[j]);
      }
    }

    for (int len = 2; len <= n; len <<= 1) {
      const auto angle = -2.0f * std::numbers::pi_v<float> / static_cast<float>(len);
      const std::complex<float> wn(std::cos(angle), std::sin(angle));
      for (int i = 0; i < n; i += len) {
        std::complex<float> w(1.0f, 0.0f);
        const int half = len / 2;
        for (int j = 0; j < half; ++j) {
          const auto u = data[i + j];
          const auto v = data[i + j + half] * w;
          data[i + j] = u + v;
          data[i + j + half] = u - v;
          w *= wn;
        }
      }
    }
  }

} // namespace

PipeWireSpectrum::ListenerId PipeWireSpectrum::addChangeListener(ChangeCallback callback) {
  if (!callback) {
    return 0;
  }
  const bool wasEmpty = m_changeListeners.empty();
  const ListenerId id = m_nextListenerId++;
  m_changeListeners.emplace(id, std::move(callback));
  if (wasEmpty) {
    rebuildStream();
  }
  return id;
}

void PipeWireSpectrum::removeChangeListener(ListenerId id) {
  if (id == 0) {
    return;
  }
  const bool removed = m_changeListeners.erase(id) > 0;
  if (removed && m_changeListeners.empty()) {
    rebuildStream();
  }
}

class PipeWireSpectrum::Stream {
public:
  Stream(PipeWireSpectrum& spectrum, std::uint32_t nodeId) : m_spectrum(spectrum), m_nodeId(nodeId) {}
  ~Stream() { destroy(); }

  Stream(const Stream&) = delete;
  Stream& operator=(const Stream&) = delete;

  bool start();
  void destroy();

private:
  static const pw_stream_events kEvents;

  static void onProcess(void* data);
  static void onParamChanged(void* data, std::uint32_t id, const spa_pod* param);
  static void onStateChanged(void* data, pw_stream_state oldState, pw_stream_state state, const char* error);
  static void onDestroy(void* data);

  void handleProcess();
  void handleParamChanged(std::uint32_t id, const spa_pod* param);

  PipeWireSpectrum& m_spectrum;
  std::uint32_t m_nodeId = 0;
  pw_stream* m_stream = nullptr;
  spa_hook m_listener{};
  spa_audio_info_raw m_format = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_UNKNOWN);
  bool m_formatReady = false;
};

const pw_stream_events PipeWireSpectrum::Stream::kEvents = [] {
  pw_stream_events events{};
  events.version = PW_VERSION_STREAM_EVENTS;
  events.destroy = &PipeWireSpectrum::Stream::onDestroy;
  events.state_changed = &PipeWireSpectrum::Stream::onStateChanged;
  events.param_changed = &PipeWireSpectrum::Stream::onParamChanged;
  events.process = &PipeWireSpectrum::Stream::onProcess;
  return events;
}();

bool PipeWireSpectrum::Stream::start() {
  pw_core* core = m_spectrum.m_service.coreHandle();
  if (core == nullptr || m_nodeId == 0) {
    return false;
  }

  const auto target = std::to_string(m_nodeId);
  auto* props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Monitor", PW_KEY_MEDIA_NAME,
                                  "Noctalia Spectrum", PW_KEY_APP_NAME, "Noctalia Spectrum", PW_KEY_STREAM_MONITOR,
                                  "true", PW_KEY_STREAM_CAPTURE_SINK, "true", PW_KEY_TARGET_OBJECT, target.c_str(),
                                  PW_KEY_NODE_PASSIVE, "true", nullptr);
  if (props == nullptr) {
    kLog.warn("failed to create spectrum stream properties");
    return false;
  }

  m_stream = pw_stream_new(core, "noctalia-spectrum", props);
  if (m_stream == nullptr) {
    pw_properties_free(props);
    kLog.warn("failed to create spectrum stream");
    return false;
  }

  spa_zero(m_listener);
  pw_stream_add_listener(m_stream, &m_listener, &kEvents, this);

  auto buffer = std::array<std::uint8_t, 512>{};
  auto builder = SPA_POD_BUILDER_INIT(buffer.data(), buffer.size());
  auto params = std::array<const spa_pod*, 1>{};
  auto raw = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32);
  params[0] = spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat, &raw);

  const auto flags = static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS);
  const int rc = pw_stream_connect(m_stream, PW_DIRECTION_INPUT, PW_ID_ANY, flags, params.data(), params.size());
  if (rc < 0) {
    kLog.warn("failed to connect spectrum stream: {}", rc);
    destroy();
    return false;
  }

  return true;
}

void PipeWireSpectrum::Stream::destroy() {
  if (m_stream == nullptr) {
    return;
  }
  spa_hook_remove(&m_listener);
  pw_stream_destroy(m_stream);
  m_stream = nullptr;
  m_formatReady = false;
}

void PipeWireSpectrum::Stream::onProcess(void* data) { static_cast<Stream*>(data)->handleProcess(); }

void PipeWireSpectrum::Stream::onParamChanged(void* data, std::uint32_t id, const spa_pod* param) {
  static_cast<Stream*>(data)->handleParamChanged(id, param);
}

void PipeWireSpectrum::Stream::onStateChanged(void* /*data*/, pw_stream_state /*oldState*/, pw_stream_state state,
                                              const char* error) {
  if (state == PW_STREAM_STATE_ERROR) {
    kLog.warn("spectrum stream error: {}", error != nullptr ? error : "unknown");
  }
}

void PipeWireSpectrum::Stream::onDestroy(void* data) {
  auto* self = static_cast<Stream*>(data);
  self->m_stream = nullptr;
  spa_hook_remove(&self->m_listener);
  self->m_formatReady = false;
}

void PipeWireSpectrum::Stream::handleParamChanged(std::uint32_t id, const spa_pod* param) {
  if (param == nullptr || id != SPA_PARAM_Format) {
    return;
  }

  spa_audio_info info{};
  if (spa_format_parse(param, &info.media_type, &info.media_subtype) < 0) {
    return;
  }
  if (info.media_type != SPA_MEDIA_TYPE_audio || info.media_subtype != SPA_MEDIA_SUBTYPE_raw) {
    return;
  }

  auto raw = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_UNKNOWN);
  if (spa_format_audio_raw_parse(param, &raw) < 0) {
    return;
  }
  if (raw.format != SPA_AUDIO_FORMAT_F32) {
    kLog.warn("unsupported spectrum stream format {}", static_cast<int>(raw.format));
    m_formatReady = false;
    return;
  }

  m_format = raw;
  m_formatReady = raw.channels > 0;
  if (m_formatReady) {
    m_spectrum.m_sampleRate = static_cast<int>(raw.rate);
    m_spectrum.computeBandBins();
  }
}

void PipeWireSpectrum::Stream::handleProcess() {
  if (!m_formatReady || m_stream == nullptr) {
    return;
  }

  auto* buffer = pw_stream_dequeue_buffer(m_stream);
  if (buffer == nullptr) {
    return;
  }
  BufferRequeueGuard requeue(m_stream, buffer);

  auto* spaBuffer = buffer->buffer;
  if (spaBuffer == nullptr || spaBuffer->n_datas < 1) {
    return;
  }

  auto* data = &spaBuffer->datas[0];
  if (data->data == nullptr || data->chunk == nullptr) {
    return;
  }

  const int channelCount = static_cast<int>(m_format.channels);
  if (channelCount <= 0) {
    return;
  }

  const auto* base = static_cast<const std::uint8_t*>(data->data) + data->chunk->offset;
  const auto* samples = reinterpret_cast<const float*>(base);
  const int totalSamples = static_cast<int>(data->chunk->size / sizeof(float));
  const int frameCount = totalSamples / channelCount;
  if (frameCount <= 0) {
    return;
  }

  static thread_local std::vector<float> mono;
  mono.resize(frameCount);

  if (channelCount == 1) {
    std::copy(samples, samples + frameCount, mono.begin());
  } else {
    const float invChannels = 1.0f / static_cast<float>(channelCount);
    for (int i = 0; i < frameCount; ++i) {
      float sum = 0.0f;
      for (int c = 0; c < channelCount; ++c) {
        sum += samples[i * channelCount + c];
      }
      mono[i] = sum * invChannels;
    }
  }

  m_spectrum.feedSamples(mono.data(), frameCount);
  m_spectrum.m_samplesReceived = true;
}

PipeWireSpectrum::PipeWireSpectrum(PipeWireService& service) : m_service(service) { initProcessing(); }

PipeWireSpectrum::~PipeWireSpectrum() = default;

void PipeWireSpectrum::setTargetNodeId(std::uint32_t id) {
  if (id == m_targetNodeId) {
    return;
  }
  m_targetNodeId = id;
  rebuildStream();
}

void PipeWireSpectrum::setBandCount(int count) {
  count = std::clamp(count, 1, kFftSize / 2);
  if (count == m_bandCount) {
    return;
  }
  m_bandCount = count;
  initProcessing();
  emitChanged();
}

void PipeWireSpectrum::setLowerCutoff(int freq) {
  freq = std::max(1, freq);
  if (freq == m_lowerCutoff) {
    return;
  }
  m_lowerCutoff = freq;
  computeBandBins();
}

void PipeWireSpectrum::setUpperCutoff(int freq) {
  freq = std::max(m_lowerCutoff + 1, freq);
  if (freq == m_upperCutoff) {
    return;
  }
  m_upperCutoff = freq;
  computeBandBins();
}

void PipeWireSpectrum::setNoiseReduction(float amount) {
  amount = std::clamp(amount, 0.0f, 1.0f);
  if (std::abs(amount - m_noiseReduction) <= 0.0001f) {
    return;
  }
  m_noiseReduction = amount;
}

void PipeWireSpectrum::setSmoothing(bool enabled) {
  if (enabled == m_smoothing) {
    return;
  }
  m_smoothing = enabled;
}

int PipeWireSpectrum::pollTimeoutMs() const {
  if (!hasListeners() || m_stream == nullptr) {
    return -1;
  }
  const auto now = std::chrono::steady_clock::now();
  if (m_nextFrameAt <= now) {
    return 0;
  }
  return static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(m_nextFrameAt - now).count());
}

void PipeWireSpectrum::tick() {
  if (!hasListeners() || m_stream == nullptr) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (m_nextFrameAt.time_since_epoch().count() == 0 || now >= m_nextFrameAt) {
    processFrame();
    m_nextFrameAt = now + std::chrono::milliseconds(1000 / kFrameRate);
  }
}

void PipeWireSpectrum::handleAudioStateChanged() {
  const std::uint32_t target = resolvedTargetNodeId();
  if (target != m_boundNodeId || (target == 0 && m_stream != nullptr) || (target != 0 && !hasResolvedTargetNode())) {
    rebuildStream();
  }
}

void PipeWireSpectrum::rebuildStream() {
  m_stream.reset();
  m_boundNodeId = 0;

  const std::uint32_t target = resolvedTargetNodeId();
  if (!hasListeners() || target == 0 || !hasResolvedTargetNode()) {
    clearValues(true);
    return;
  }

  m_stream = std::make_unique<Stream>(*this, target);
  if (!m_stream->start()) {
    m_stream.reset();
    clearValues(true);
    return;
  }

  m_boundNodeId = target;
  m_ringPos = 0;
  m_ringFull = false;
  m_idleFrames = 0;
  m_samplesReceived = false;
  m_sensitivity = 0.01f;
  m_sensInit = true;
  std::fill(m_prevBands.begin(), m_prevBands.end(), 0.0f);
  std::fill(m_peak.begin(), m_peak.end(), 0.0f);
  std::fill(m_fall.begin(), m_fall.end(), 0.0f);
  std::fill(m_mem.begin(), m_mem.end(), 0.0f);
  m_nextFrameAt = std::chrono::steady_clock::now();
  if (m_idle) {
    emitChanged();
  }
}

std::uint32_t PipeWireSpectrum::resolvedTargetNodeId() const noexcept {
  if (m_targetNodeId != 0) {
    return m_targetNodeId;
  }
  return m_service.state().defaultSinkId;
}

bool PipeWireSpectrum::hasResolvedTargetNode() const noexcept {
  const std::uint32_t id = resolvedTargetNodeId();
  if (id == 0) {
    return false;
  }

  const auto& state = m_service.state();
  return std::ranges::any_of(state.sinks, [id](const AudioNode& node) { return node.id == id; }) ||
         std::ranges::any_of(state.sources, [id](const AudioNode& node) { return node.id == id; });
}

void PipeWireSpectrum::clearValues(bool notify) {
  const bool hadNonZero = std::ranges::any_of(m_values, [](float value) { return value > 0.0f; });
  std::fill(m_values.begin(), m_values.end(), 0.0f);
  m_idleFrames = 0;
  m_idle = true;
  m_samplesReceived = false;
  m_ringFull = false;
  if (notify && (hadNonZero || !m_values.empty())) {
    emitChanged();
  }
}

void PipeWireSpectrum::emitChanged() {
  for (const auto& [id, callback] : m_changeListeners) {
    (void)id;
    if (callback) {
      callback();
    }
  }
}

void PipeWireSpectrum::initProcessing() {
  m_ringBuffer.assign(kFftSize, 0.0f);
  m_ringPos = 0;
  m_ringFull = false;
  m_fftBuf.resize(kFftSize);

  m_window.resize(kFftSize);
  for (int i = 0; i < kFftSize; ++i) {
    m_window[i] =
        0.5f *
        (1.0f - std::cos(2.0f * std::numbers::pi_v<float> * static_cast<float>(i) / static_cast<float>(kFftSize - 1)));
  }

  m_prevBands.assign(m_bandCount, 0.0f);
  m_peak.assign(m_bandCount, 0.0f);
  m_fall.assign(m_bandCount, 0.0f);
  m_mem.assign(m_bandCount, 0.0f);
  m_bands.assign(m_bandCount, 0.0f);
  m_values.assign(m_bandCount, 0.0f);
  computeBandBins();
}

void PipeWireSpectrum::computeBandBins() {
  m_bandBinLow.resize(m_bandCount);
  m_bandBinHigh.resize(m_bandCount);

  const float fLow = static_cast<float>(m_lowerCutoff);
  const float fHigh = static_cast<float>(std::min(m_upperCutoff, m_sampleRate / 2));
  const float ratio = fHigh / fLow;
  const int fftBins = kFftSize / 2;

  for (int i = 0; i < m_bandCount; ++i) {
    const float bandFreqLow = fLow * std::pow(ratio, static_cast<float>(i) / static_cast<float>(m_bandCount));
    const float bandFreqHigh = fLow * std::pow(ratio, static_cast<float>(i + 1) / static_cast<float>(m_bandCount));

    int binLow =
        static_cast<int>(std::ceil(bandFreqLow * static_cast<float>(kFftSize) / static_cast<float>(m_sampleRate)));
    int binHigh =
        static_cast<int>(std::floor(bandFreqHigh * static_cast<float>(kFftSize) / static_cast<float>(m_sampleRate)));

    binLow = std::clamp(binLow, 1, fftBins);
    binHigh = std::clamp(binHigh, binLow, fftBins);

    if (i > 0 && binLow <= m_bandBinHigh[i - 1]) {
      binLow = m_bandBinHigh[i - 1] + 1;
      if (binLow > fftBins) {
        binLow = fftBins;
      }
      if (binHigh < binLow) {
        binHigh = binLow;
      }
    }

    m_bandBinLow[i] = binLow;
    m_bandBinHigh[i] = binHigh;
  }
}

void PipeWireSpectrum::feedSamples(const float* monoSamples, int count) {
  const bool wasFull = m_ringFull;
  for (int i = 0; i < count; ++i) {
    m_ringBuffer[m_ringPos] = monoSamples[i];
    m_ringPos = (m_ringPos + 1) % kFftSize;
    if (m_ringPos == 0) {
      m_ringFull = true;
    }
  }
  if (!wasFull && m_ringFull) {
    kLog.debug("spectrum ring buffer primed");
  }
}

void PipeWireSpectrum::processFrame() {
  if (!m_ringFull) {
    return;
  }
  if (m_idle && !m_samplesReceived) {
    return;
  }

  if (!m_samplesReceived) {
    for (auto& sample : m_ringBuffer) {
      sample *= 0.85f;
    }
  }
  m_samplesReceived = false;

  for (int i = 0; i < kFftSize; ++i) {
    const int idx = (m_ringPos + i) % kFftSize;
    m_fftBuf[i] = {m_ringBuffer[idx] * m_window[i], 0.0f};
  }

  fft(m_fftBuf.data(), kFftSize);

  auto& bands = m_bands;
  for (int i = 0; i < m_bandCount; ++i) {
    float maxMagSq = 0.0f;
    for (int bin = m_bandBinLow[i]; bin <= m_bandBinHigh[i]; ++bin) {
      maxMagSq = std::max(maxMagSq, std::norm(m_fftBuf[bin]));
    }
    bands[i] = std::sqrt(maxMagSq);
  }

  const float invBandCount = 1.0f / static_cast<float>(m_bandCount);
  for (int i = 0; i < m_bandCount; ++i) {
    const float weight = 1.0f + 0.5f * static_cast<float>(m_bandCount - i) * invBandCount;
    bands[i] *= weight;
  }

  const float nrFactor = m_noiseReduction;
  const float noiseGate = nrFactor * static_cast<float>(kFftSize) * 0.00005f;
  for (auto& band : bands) {
    band = std::max(0.0f, band - noiseGate);
    band *= m_sensitivity;
  }

  const double gravityMod = std::max(1.0, 1.54 / std::max(static_cast<double>(m_noiseReduction), 0.01));

  bool overshoot = false;
  bool silence = true;

  for (int i = 0; i < m_bandCount; ++i) {
    if (bands[i] < m_prevBands[i] && m_noiseReduction > 0.1f) {
      bands[i] =
          static_cast<float>(static_cast<double>(m_peak[i]) *
                             (1.0 - static_cast<double>(m_fall[i]) * static_cast<double>(m_fall[i]) * gravityMod));
      if (bands[i] < 0.0f) {
        bands[i] = 0.0f;
      }
      m_fall[i] += 0.028f;
    } else {
      m_peak[i] = bands[i];
      m_fall[i] = 0.0f;
    }
    m_prevBands[i] = bands[i];

    bands[i] = m_mem[i] * nrFactor + bands[i];
    m_mem[i] = bands[i];

    if (bands[i] > 1.0f) {
      overshoot = true;
      bands[i] = 1.0f;
    }
    if (bands[i] > 0.01f) {
      silence = false;
    }
  }

  if (overshoot) {
    m_sensitivity *= 0.98f;
    m_sensInit = false;
  } else if (!silence) {
    m_sensitivity *= 1.001f;
    if (m_sensInit) {
      m_sensitivity *= 1.1f;
    }
  }
  m_sensitivity = std::clamp(m_sensitivity, 0.001f, 50.0f);

  if (m_smoothing) {
    constexpr float kMonstercatFactor = 1.5f;
    constexpr float kMinSpread = 0.001f;
    for (int z = 0; z < m_bandCount; ++z) {
      float spread = bands[z] / kMonstercatFactor;
      for (int m = z - 1; m >= 0 && spread > kMinSpread; --m) {
        bands[m] = std::max(bands[m], spread);
        spread /= kMonstercatFactor;
      }
      spread = bands[z] / kMonstercatFactor;
      for (int m = z + 1; m < m_bandCount && spread > kMinSpread; ++m) {
        bands[m] = std::max(bands[m], spread);
        spread /= kMonstercatFactor;
      }
    }
  }

  for (auto& band : bands) {
    band = std::clamp(band, 0.0f, 1.0f);
  }

  if (silence) {
    ++m_idleFrames;
    if (m_idleFrames >= kIdleThreshold) {
      if (!m_idle) {
        m_idle = true;
        std::fill(m_values.begin(), m_values.end(), 0.0f);
        emitChanged();
      }
      return;
    }
  } else {
    m_idleFrames = 0;
    m_idle = false;
  }

  bool changed = false;
  for (int i = 0; i < m_bandCount; ++i) {
    if (m_values[i] != bands[i]) {
      m_values[i] = bands[i];
      changed = true;
    }
  }

  if (changed) {
    emitChanged();
  }
}

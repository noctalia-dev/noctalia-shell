#include "pipewire/pipewire_pcm_tap.h"

#include "core/log.h"
#include "pipewire/pipewire_service.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <pipewire/core.h>
#include <pipewire/keys.h>
#include <pipewire/properties.h>
#include <pipewire/stream.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/audio/raw.h>
#include <spa/param/format-utils.h>
#include <spa/pod/pod.h>
#include <utility>

namespace {

  constexpr Logger kLog{"pipewire_pcm_tap"};

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

} // namespace

class PipeWirePcmTap::Stream {
public:
  Stream(PipeWirePcmTap& tap, std::uint32_t nodeId, std::string targetObject)
      : m_tap(tap), m_nodeId(nodeId), m_targetObject(std::move(targetObject)) {}
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

  PipeWirePcmTap& m_tap;
  std::uint32_t m_nodeId = 0;
  std::string m_targetObject;
  pw_stream* m_stream = nullptr;
  spa_hook m_listener{};
  spa_audio_info_raw m_format = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_UNKNOWN);
  bool m_formatReady = false;
};

const pw_stream_events PipeWirePcmTap::Stream::kEvents = [] {
  pw_stream_events events{};
  events.version = PW_VERSION_STREAM_EVENTS;
  events.destroy = &PipeWirePcmTap::Stream::onDestroy;
  events.state_changed = &PipeWirePcmTap::Stream::onStateChanged;
  events.param_changed = &PipeWirePcmTap::Stream::onParamChanged;
  events.process = &PipeWirePcmTap::Stream::onProcess;
  return events;
}();

bool PipeWirePcmTap::Stream::start() {
  pw_core* core = m_tap.m_service.coreHandle();
  if (core == nullptr || m_nodeId == 0 || m_targetObject.empty()) {
    return false;
  }

  auto* props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Monitor", PW_KEY_MEDIA_NAME,
                                  "Noctalia LivePaper", PW_KEY_APP_NAME, "Noctalia LivePaper", PW_KEY_STREAM_MONITOR,
                                  "true", PW_KEY_STREAM_CAPTURE_SINK, "true", PW_KEY_TARGET_OBJECT,
                                  m_targetObject.c_str(), PW_KEY_NODE_PASSIVE, "true", nullptr);
  if (props == nullptr) {
    kLog.warn("failed to create pcm-tap stream properties");
    return false;
  }

  m_stream = pw_stream_new(core, "noctalia-livepaper-pcm", props);
  if (m_stream == nullptr) {
    pw_properties_free(props);
    kLog.warn("failed to create pcm-tap stream");
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
    kLog.warn("failed to connect pcm-tap stream: {}", rc);
    destroy();
    return false;
  }
  return true;
}

void PipeWirePcmTap::Stream::destroy() {
  if (m_stream == nullptr) {
    return;
  }
  spa_hook_remove(&m_listener);
  pw_stream_destroy(m_stream);
  m_stream = nullptr;
  m_formatReady = false;
}

void PipeWirePcmTap::Stream::onProcess(void* data) { static_cast<Stream*>(data)->handleProcess(); }

void PipeWirePcmTap::Stream::onParamChanged(void* data, std::uint32_t id, const spa_pod* param) {
  static_cast<Stream*>(data)->handleParamChanged(id, param);
}

void PipeWirePcmTap::Stream::onStateChanged(void* data, pw_stream_state /*oldState*/, pw_stream_state state,
                                            const char* error) {
  auto* self = static_cast<Stream*>(data);
  if (state == PW_STREAM_STATE_ERROR) {
    kLog.warn("pcm-tap stream error: {}", error != nullptr ? error : "unknown");
  }
  self->m_tap.m_streamRunning.store(state == PW_STREAM_STATE_STREAMING, std::memory_order_release);
}

void PipeWirePcmTap::Stream::onDestroy(void* data) {
  auto* self = static_cast<Stream*>(data);
  self->m_stream = nullptr;
  spa_hook_remove(&self->m_listener);
  self->m_formatReady = false;
}

void PipeWirePcmTap::Stream::handleParamChanged(std::uint32_t id, const spa_pod* param) {
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
    kLog.warn("unsupported pcm-tap stream format {}", static_cast<int>(raw.format));
    m_formatReady = false;
    return;
  }
  m_format = raw;
  m_formatReady = raw.channels > 0;
  if (m_formatReady) {
    m_tap.resetRing(static_cast<int>(raw.channels), static_cast<int>(raw.rate));
  }
}

void PipeWirePcmTap::Stream::handleProcess() {
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
  m_tap.feedSamples(samples, frameCount, channelCount);
}

// ───────────────────────────────────────────────────────────────────────────

PipeWirePcmTap::PipeWirePcmTap(PipeWireService& service) : m_service(service) {
  m_ring.assign(kRingFrames * kMaxChannels, 0.0f);
}

PipeWirePcmTap::~PipeWirePcmTap() = default;

bool PipeWirePcmTap::isRunning() const noexcept { return m_streamRunning.load(std::memory_order_acquire); }

void PipeWirePcmTap::start(std::string targetNodeName) {
  m_explicitTarget = std::move(targetNodeName);
  rebuildStream();
}

void PipeWirePcmTap::stop() {
  m_explicitTarget.clear();
  m_stream.reset();
  m_boundNodeId = 0;
  m_boundTarget.clear();
  m_streamRunning.store(false, std::memory_order_release);
  resetRing(0, 0);
}

void PipeWirePcmTap::handleAudioStateChanged() {
  // Only rebind if we're following the default sink (explicitTarget empty)
  // and the resolved default sink has changed.
  if (m_stream == nullptr && m_explicitTarget.empty() && m_boundNodeId == 0) {
    // Stream was never started — nothing to rebind.
    return;
  }
  const auto* node = resolvedTargetNode();
  const std::uint32_t resolvedId = node != nullptr ? node->id : 0;
  const std::string resolvedName = node != nullptr ? node->name : std::string{};
  if (resolvedId != m_boundNodeId || resolvedName != m_boundTarget) {
    rebuildStream();
  }
}

const AudioNode* PipeWirePcmTap::resolvedTargetNode() const noexcept {
  const auto& state = m_service.state();
  if (!m_explicitTarget.empty()) {
    // Match against PipeWire node name.
    auto match = [this](const AudioNode& n) { return n.name == m_explicitTarget; };
    auto sink = std::ranges::find_if(state.sinks, match);
    if (sink != state.sinks.end()) {
      return &*sink;
    }
    auto source = std::ranges::find_if(state.sources, match);
    if (source != state.sources.end()) {
      return &*source;
    }
    return nullptr;
  }
  // Follow default sink.
  const std::uint32_t id = state.defaultSinkId;
  if (id == 0) {
    return nullptr;
  }
  auto sink = std::ranges::find_if(state.sinks, [id](const AudioNode& n) { return n.id == id; });
  return sink != state.sinks.end() ? &*sink : nullptr;
}

void PipeWirePcmTap::rebuildStream() {
  m_stream.reset();
  m_boundNodeId = 0;
  m_boundTarget.clear();
  m_streamRunning.store(false, std::memory_order_release);

  const auto* node = resolvedTargetNode();
  if (node == nullptr || node->name.empty()) {
    resetRing(0, 0);
    return;
  }
  m_stream = std::make_unique<Stream>(*this, node->id, node->name);
  if (!m_stream->start()) {
    m_stream.reset();
    resetRing(0, 0);
    return;
  }
  m_boundNodeId = node->id;
  m_boundTarget = node->name;
}

void PipeWirePcmTap::resetRing(int channels, int sampleRate) {
  // Invalidate before publishing new format — any consumer observing
  // channels()==0 will skip its read until the new format is published.
  m_channels.store(0, std::memory_order_release);
  m_writeFrames.store(0, std::memory_order_release);
  m_readFrames.store(0, std::memory_order_release);
  m_sampleRate.store(sampleRate, std::memory_order_release);
  m_channels.store(std::min(channels, kMaxChannels), std::memory_order_release);
}

void PipeWirePcmTap::feedSamples(const float* interleaved, int frameCount, int channels) {
  if (frameCount <= 0 || channels <= 0 || channels > kMaxChannels) {
    return;
  }
  const auto write = m_writeFrames.load(std::memory_order_relaxed);
  const std::size_t channelStride = static_cast<std::size_t>(kMaxChannels);
  for (int i = 0; i < frameCount; ++i) {
    const std::size_t slot = (write + static_cast<std::size_t>(i)) % kRingFrames;
    float* dst = m_ring.data() + slot * channelStride;
    // Copy real channels; remaining slots in the stride are left untouched
    // (consumer only reads up to current channels()).
    for (int c = 0; c < channels; ++c) {
      dst[c] = interleaved[i * channels + c];
    }
  }
  m_writeFrames.store(write + static_cast<std::size_t>(frameCount), std::memory_order_release);
}

int PipeWirePcmTap::consume(float* out, int maxFrames) {
  if (out == nullptr || maxFrames <= 0) {
    return 0;
  }
  const int chans = m_channels.load(std::memory_order_acquire);
  if (chans <= 0) {
    return 0;
  }
  const auto write = m_writeFrames.load(std::memory_order_acquire);
  auto read = m_readFrames.load(std::memory_order_relaxed);

  // Frames available since last read; cap at the buffer capacity to handle
  // overruns (writer outran reader by >= kRingFrames) by silently dropping
  // the stale tail rather than serving wrapped garbage.
  std::size_t available = write - read;
  if (available > kRingFrames) {
    // Overrun: snap reader forward to the oldest still-valid frame.
    read = write - kRingFrames;
    available = kRingFrames;
  }
  const std::size_t take = std::min<std::size_t>(available, static_cast<std::size_t>(maxFrames));
  if (take == 0) {
    return 0;
  }
  const std::size_t channelStride = static_cast<std::size_t>(kMaxChannels);
  for (std::size_t i = 0; i < take; ++i) {
    const std::size_t slot = (read + i) % kRingFrames;
    const float* src = m_ring.data() + slot * channelStride;
    float* dst = out + i * static_cast<std::size_t>(chans);
    std::memcpy(dst, src, sizeof(float) * static_cast<std::size_t>(chans));
  }
  m_readFrames.store(read + take, std::memory_order_release);
  return static_cast<int>(take);
}

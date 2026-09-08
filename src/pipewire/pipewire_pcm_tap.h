#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class PipeWireService;
class PipeWireSpectrum;
struct AudioNode;

// Single-producer / single-consumer raw PCM capture from a PipeWire monitor
// node. Used by the live-paper (projectM) renderer to feed audio into the
// visualizer at its own cadence.
//
// Lifecycle:
//   - start("")    → follows the bar's audio-visualizer widget: taps the sink
//                    the spectrum analyses while it reports audio, then the
//                    default source (mic) once the spectrum goes idle
//   - start(name)  → opens a capture stream against a specific PipeWire node
//                    regardless of allow-mic-fallback (the user named it)
//   - stop()       → tears the stream down (so an idle session uses no CPU)
//   - handleAudioStateChanged() → rebinds when the active monitor changes
//
// Threading:
//   PipeWireService uses a non-threaded pw_loop, so on_process, the spectrum
//   listener, rebuildStream(), and consume() (called from the main loop's
//   visualizer tick) all dispatch on the SAME thread via pw_loop_iterate. The
//   atomics on m_ring and the no-locks-on-hot-path discipline are kept for
//   forward-compatibility with a future pw_thread_loop split; they are
//   trivially correct under the current single-threaded model.
class PipeWirePcmTap {
public:
  // `spectrum` supplies the same idle/source signal that drives the bar's
  // audio-visualizer widget; the tap follows it in start("") mode. May be
  // null (the tap then always falls back to the mic in follow mode).
  PipeWirePcmTap(PipeWireService& service, PipeWireSpectrum* spectrum);
  ~PipeWirePcmTap();

  PipeWirePcmTap(const PipeWirePcmTap&) = delete;
  PipeWirePcmTap& operator=(const PipeWirePcmTap&) = delete;

  void start(std::string targetNodeName);
  void stop();
  void handleAudioStateChanged();

  void setMicFallbackAllowed(bool allowed);

  // Pop up to maxFrames interleaved float frames into out. The number of
  // floats actually written is `frames * channels()`. Returns frames.
  // If no data is available (or the stream isn't bound yet) returns 0.
  int consume(float* out, int maxFrames);

  [[nodiscard]] int channels() const noexcept { return m_channels.load(std::memory_order_acquire); }
  [[nodiscard]] int sampleRate() const noexcept { return m_sampleRate.load(std::memory_order_acquire); }
  [[nodiscard]] bool isRunning() const noexcept;

  static constexpr int kMaxChannels = 8;

private:
  class Stream;
  friend class Stream;

  void rebuildStream();
  void updateSpectrumSubscription();
  [[nodiscard]] const AudioNode* resolvedTargetNode() const noexcept;
  void resetRing(int channels, int sampleRate);
  void feedSamples(const float* interleaved, int frameCount, int channels);

  static constexpr std::size_t kRingFrames = 1u << 15; // 32 768 frames

  PipeWireService& m_service;
  PipeWireSpectrum* m_spectrum = nullptr; // shared idle/source signal with the visualizer widget
  std::uint64_t m_spectrumListener = 0;   // PipeWireSpectrum::ListenerId; 0 = not subscribed
  std::unique_ptr<Stream> m_stream;
  std::string m_explicitTarget; // "" → follow the spectrum / widget
  std::string m_boundTarget;
  std::uint32_t m_boundNodeId = 0;
  bool m_started = false;            // start() called and not since stop()ped
  bool m_micFallbackAllowed = false; // privacy gate; see setMicFallbackAllowed

  // Automatic gain control. Set true on (re)bind (main thread, while no RT
  // callback runs); m_agcEnvelope is RT-thread-only state advanced inside
  // feedSamples(). Applied to both mic captures and sink monitors so projectM
  // sees a consistent signal level regardless of source volume.
  bool m_agcActive = false;
  float m_agcEnvelope = 0.0f;

  std::vector<float> m_ring;
  std::atomic<std::size_t> m_writeFrames{0}; // monotonically increasing
  std::atomic<std::size_t> m_readFrames{0};
  std::atomic<int> m_channels{0};
  std::atomic<int> m_sampleRate{0};
  std::atomic<bool> m_streamRunning{false};
};

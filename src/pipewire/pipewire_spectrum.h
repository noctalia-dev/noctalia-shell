#pragma once

#include <chrono>
#include <complex>
#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

class PipeWireService;

class PipeWireSpectrum {
public:
  using ChangeCallback = std::function<void()>;

  explicit PipeWireSpectrum(PipeWireService& service);
  ~PipeWireSpectrum();

  PipeWireSpectrum(const PipeWireSpectrum&) = delete;
  PipeWireSpectrum& operator=(const PipeWireSpectrum&) = delete;

  void setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  void setEnabled(bool enabled);
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }

  void setTargetNodeId(std::uint32_t id);
  [[nodiscard]] std::uint32_t targetNodeId() const noexcept { return m_targetNodeId; }

  void setBandCount(int count);
  [[nodiscard]] int bandCount() const noexcept { return m_bandCount; }

  void setFrameRate(int rate);
  [[nodiscard]] int frameRate() const noexcept { return m_frameRate; }

  void setLowerCutoff(int freq);
  [[nodiscard]] int lowerCutoff() const noexcept { return m_lowerCutoff; }

  void setUpperCutoff(int freq);
  [[nodiscard]] int upperCutoff() const noexcept { return m_upperCutoff; }

  void setNoiseReduction(float amount);
  [[nodiscard]] float noiseReduction() const noexcept { return m_noiseReduction; }

  void setSmoothing(bool enabled);
  [[nodiscard]] bool smoothing() const noexcept { return m_smoothing; }

  [[nodiscard]] const std::vector<float>& values() const noexcept { return m_values; }
  [[nodiscard]] bool idle() const noexcept { return m_idle; }

  [[nodiscard]] int pollTimeoutMs() const;
  void tick();
  void handleAudioStateChanged();

private:
  class Stream;
  friend class Stream;

  void rebuildStream();
  [[nodiscard]] std::uint32_t resolvedTargetNodeId() const noexcept;
  [[nodiscard]] bool hasResolvedTargetNode() const noexcept;
  void clearValues(bool notify);
  void emitChanged();

  void initProcessing();
  void computeBandBins();
  void feedSamples(const float* monoSamples, int count);
  void processFrame();

  PipeWireService& m_service;
  ChangeCallback m_changeCallback;

  bool m_enabled = false;
  std::uint32_t m_targetNodeId = 0;
  std::uint32_t m_boundNodeId = 0;
  int m_bandCount = 32;
  int m_frameRate = 30;
  int m_lowerCutoff = 50;
  int m_upperCutoff = 12000;
  float m_noiseReduction = 0.77f;
  bool m_smoothing = true;
  std::vector<float> m_values;
  bool m_idle = true;

  std::unique_ptr<Stream> m_stream;
  std::chrono::steady_clock::time_point m_nextFrameAt{};

  static constexpr int kFftSize = 4096;
  static constexpr int kIdleThreshold = 30;

  std::vector<float> m_ringBuffer;
  int m_ringPos = 0;
  bool m_ringFull = false;
  int m_sampleRate = 48000;
  int m_idleFrames = 0;
  bool m_samplesReceived = false;

  std::vector<float> m_window;
  std::vector<int> m_bandBinLow;
  std::vector<int> m_bandBinHigh;
  std::vector<float> m_prevBands;
  std::vector<float> m_peak;
  std::vector<float> m_fall;
  std::vector<float> m_mem;
  std::vector<float> m_bands;
  float m_sensitivity = 1.0f;
  bool m_sensInit = true;
  double m_cachedGravityMod = 1.0;
  int m_cachedGravityFrameRate = 0;
  std::vector<std::complex<float>> m_fftBuf;
};

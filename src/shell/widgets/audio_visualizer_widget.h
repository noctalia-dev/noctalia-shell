#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class AudioSpectrum;
class PipeWireSpectrum;
class Renderer;

class AudioVisualizerWidget : public Widget {
public:
  AudioVisualizerWidget(PipeWireSpectrum* spectrum, float width, float height, int bands);
  ~AudioVisualizerWidget() override;

  void create() override;
  void onFrameTick(float deltaMs) override;
  [[nodiscard]] bool needsFrameTick() const override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncSpectrum();

  PipeWireSpectrum* m_spectrum = nullptr;
  float m_width = 56.0f;
  float m_height = 16.0f;
  int m_bands = 16;
  std::uint64_t m_listenerId = 0;
  Renderer* m_renderer = nullptr;
  AudioSpectrum* m_visualizer = nullptr;
  bool m_pendingSpectrumUpdate = false;
  bool m_isVertical = false;
};

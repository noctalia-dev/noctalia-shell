#pragma once

#include "shell/desktop/desktop_widget.h"

#include <cstdint>

class AudioSpectrum;
class PipeWireSpectrum;
class Renderer;

class DesktopAudioVisualizerWidget : public DesktopWidget {
public:
  DesktopAudioVisualizerWidget(PipeWireSpectrum* spectrum, float aspectRatio, int bands);
  ~DesktopAudioVisualizerWidget() override;

  void create() override;
  [[nodiscard]] bool needsFrameTick() const override;
  void onFrameTick(float deltaMs, Renderer& renderer) override;

private:
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;
  void syncSpectrum(Renderer* renderer);

  PipeWireSpectrum* m_spectrum = nullptr;
  float m_aspectRatio = 2.5f;
  int m_bands = 32;
  std::uint64_t m_listenerId = 0;
  AudioSpectrum* m_visualizer = nullptr;
  bool m_pendingSpectrumUpdate = false;
};

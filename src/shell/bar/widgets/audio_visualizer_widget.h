#pragma once

#include "shell/bar/widget.h"
#include "ui/palette.h"

#include <cstdint>

class AudioVisualizer;
class PipeWireSpectrum;
class Renderer;

class AudioVisualizerWidget : public Widget {
public:
  AudioVisualizerWidget(
      PipeWireSpectrum* spectrum, float width, int bands, bool mirrored, ColorSpec color1, ColorSpec color2,
      bool centered, bool showWhenIdle
  );
  ~AudioVisualizerWidget() override;

  void create() override;
  void onFrameTick(float deltaMs) override;
  [[nodiscard]] bool needsFrameTick() const override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncSpectrum();
  [[nodiscard]] bool shouldBeVisible() const;
  bool applyVisibility();
  void cancelVisibilityAnimation();
  void setVisibilityCollapsed(bool collapsed);
  void startOpacityAnimation(float targetOpacity, bool collapseOnComplete);

  PipeWireSpectrum* m_spectrum = nullptr;
  float m_width = 56.0f;
  int m_bands = 16;
  bool m_mirrored = false;
  bool m_centered = true;
  bool m_showWhenIdle = false;
  ColorSpec m_color1 = colorSpecFromRole(ColorRole::Primary);
  ColorSpec m_color2 = colorSpecFromRole(ColorRole::Primary);
  std::uint64_t m_listenerId = 0;
  AudioVisualizer* m_visualizer = nullptr;
  bool m_pendingSpectrumUpdate = false;
  bool m_visible = true;
  bool m_visibilityInitialized = false;
  bool m_fadingOut = false;
  std::uint32_t m_visibilityAnimId = 0;
};

#pragma once

#include "render/scene/audio_spectrum_node.h"
#include "ui/palette.h"

#include <algorithm>
#include <vector>

class Renderer;

class AudioSpectrum : public AudioSpectrumNode {
public:
  AudioSpectrum();

  bool setValues(const std::vector<float>& values);
  void setGradient(const ColorSpec& lowColor, const ColorSpec& highColor);
  void setGradient(const Color& lowColor, const Color& highColor);
  void setOrientation(AudioSpectrumOrientation orientation);
  void setMirrored(bool mirrored);
  void setCentered(bool centered);
  void setSmoothingTimeMs(float tauMs) noexcept { m_smoothingTauMs = std::max(0.0f, tauMs); }

  void tick(float deltaMs);
  [[nodiscard]] bool converged() const noexcept { return m_converged; }

private:
  void syncPalette();
  void doLayout(Renderer& renderer) override;

  std::vector<float> m_targetValues;
  std::vector<float> m_displayValues;
  float m_smoothingTauMs = 60.0f;
  bool m_converged = true;
  ColorSpec m_lowColor = colorSpecFromRole(ColorRole::Primary);
  ColorSpec m_highColor = colorSpecFromRole(ColorRole::Primary);
  Signal<>::ScopedConnection m_paletteConn;
};

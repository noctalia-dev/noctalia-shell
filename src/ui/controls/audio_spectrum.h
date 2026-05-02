#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"

#include <algorithm>
#include <cstdint>
#include <vector>

class Box;
class Renderer;

enum class AudioSpectrumOrientation : std::uint8_t {
  Horizontal,
  Vertical,
};

enum class AudioSpectrumLayoutMode : std::uint8_t {
  QuantizedCentered,
  Fill,
};

class AudioSpectrum : public Node {
public:
  AudioSpectrum();

  void setValues(const std::vector<float>& values);
  void setGradient(const ColorSpec& lowColor, const ColorSpec& highColor);
  void setGradient(const Color& lowColor, const Color& highColor);
  void setSpacingRatio(float ratio);
  void setOrientation(AudioSpectrumOrientation orientation);
  void setLayoutMode(AudioSpectrumLayoutMode mode);
  void setMirrored(bool mirrored);
  void setCentered(bool centered);
  void setSmoothingTimeMs(float tauMs) noexcept { m_smoothingTauMs = std::max(0.0f, tauMs); }

  void tick(float deltaMs);
  [[nodiscard]] bool converged() const noexcept { return m_converged; }

  void setSize(float width, float height) override;

private:
  void ensureBarCount(std::size_t count);
  void recolorBars();
  void updateBarsGeometry();
  void doLayout(Renderer& renderer) override;

  std::vector<float> m_targetValues;
  std::vector<float> m_displayValues;
  std::vector<Box*> m_bars;
  float m_smoothingTauMs = 60.0f;
  bool m_converged = true;
  ColorSpec m_lowColor = colorSpecFromRole(ColorRole::Primary);
  ColorSpec m_highColor = colorSpecFromRole(ColorRole::Primary);
  float m_spacingRatio = 0.5f;
  AudioSpectrumOrientation m_orientation = AudioSpectrumOrientation::Horizontal;
  AudioSpectrumLayoutMode m_layoutMode = AudioSpectrumLayoutMode::QuantizedCentered;
  bool m_mirrored = false;
  bool m_centered = false;
  Signal<>::ScopedConnection m_paletteConn;
};

#include "ui/controls/audio_spectrum.h"

#include "ui/palette.h"

#include <algorithm>
#include <cmath>

AudioSpectrum::AudioSpectrum() {
  syncPalette();
  m_paletteConn = paletteChanged().connect([this] { syncPalette(); });
}

bool AudioSpectrum::setValues(const std::vector<float>& values) {
  if (m_targetValues.size() == values.size() && std::equal(values.begin(), values.end(), m_targetValues.begin())) {
    return false;
  }

  m_targetValues = values;
  if (m_displayValues.size() != m_targetValues.size()) {
    m_displayValues.resize(m_targetValues.size(), 0.0f);
  }
  m_converged = false;
  setSpectrumValues(m_displayValues);
  return true;
}

void AudioSpectrum::tick(float deltaMs) {
  if (m_targetValues.empty()) {
    m_converged = true;
    return;
  }
  if (m_displayValues.size() != m_targetValues.size()) {
    m_displayValues.resize(m_targetValues.size(), 0.0f);
  }

  const float alpha = m_smoothingTauMs > 0.0f ? 1.0f - std::exp(-std::max(0.0f, deltaMs) / m_smoothingTauMs) : 1.0f;

  constexpr float kEpsilon = 1.0f / 512.0f;
  bool changed = false;
  bool converged = true;
  for (std::size_t i = 0; i < m_targetValues.size(); ++i) {
    const float target = m_targetValues[i];
    float& display = m_displayValues[i];
    const float delta = target - display;
    if (std::fabs(delta) < kEpsilon) {
      if (display != target) {
        display = target;
        changed = true;
      }
      continue;
    }
    display += delta * alpha;
    converged = false;
    changed = true;
  }

  m_converged = converged;
  if (changed) {
    setSpectrumValues(m_displayValues);
  }
}

void AudioSpectrum::setGradient(const ColorSpec& lowColor, const ColorSpec& highColor) {
  m_lowColor = lowColor;
  m_highColor = highColor;
  syncPalette();
}

void AudioSpectrum::setGradient(const Color& lowColor, const Color& highColor) {
  setGradient(fixedColorSpec(lowColor), fixedColorSpec(highColor));
}

void AudioSpectrum::setOrientation(AudioSpectrumOrientation orientation) {
  auto next = style();
  next.orientation = orientation;
  setStyle(next);
}

void AudioSpectrum::setMirrored(bool mirrored) {
  auto next = style();
  next.mirrored = mirrored;
  setStyle(next);
}

void AudioSpectrum::setCentered(bool centered) {
  auto next = style();
  next.centered = centered;
  setStyle(next);
}

void AudioSpectrum::syncPalette() {
  auto next = style();
  next.lowColor = resolveColorSpec(m_lowColor);
  next.highColor = resolveColorSpec(m_highColor);
  setStyle(next);
}

void AudioSpectrum::doLayout(Renderer& /*renderer*/) {}

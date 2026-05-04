#include "ui/controls/audio_spectrum.h"

#include "ui/controls/box.h"
#include "ui/palette.h"

#include <algorithm>
#include <cmath>
#include <memory>

AudioSpectrum::AudioSpectrum() {
  m_paletteConn = paletteChanged().connect([this] { recolorBars(); });
}

void AudioSpectrum::setValues(const std::vector<float>& values) {
  m_targetValues = values;
  if (m_displayValues.size() != m_targetValues.size()) {
    m_displayValues.resize(m_targetValues.size(), 0.0f);
  }
  ensureBarCount(m_mirrored ? m_targetValues.size() * 2 : m_targetValues.size());
  m_converged = false;
  updateBarsGeometry();
  markPaintDirty();
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
    updateBarsGeometry();
    markPaintDirty();
  }
}

void AudioSpectrum::setGradient(const ColorSpec& lowColor, const ColorSpec& highColor) {
  m_lowColor = lowColor;
  m_highColor = highColor;
  recolorBars();
}

void AudioSpectrum::setGradient(const Color& lowColor, const Color& highColor) {
  setGradient(fixedColorSpec(lowColor), fixedColorSpec(highColor));
}

void AudioSpectrum::setOrientation(AudioSpectrumOrientation orientation) {
  if (m_orientation == orientation) {
    return;
  }
  m_orientation = orientation;
  updateBarsGeometry();
  markLayoutDirty();
}

void AudioSpectrum::setMirrored(bool mirrored) {
  if (m_mirrored == mirrored) {
    return;
  }
  m_mirrored = mirrored;
  ensureBarCount(m_mirrored ? m_targetValues.size() * 2 : m_targetValues.size());
  updateBarsGeometry();
  markLayoutDirty();
}

void AudioSpectrum::setCentered(bool centered) {
  if (m_centered == centered) {
    return;
  }
  m_centered = centered;
  updateBarsGeometry();
  markLayoutDirty();
}

void AudioSpectrum::setSize(float width, float height) {
  if (this->width() == width && this->height() == height) {
    return;
  }
  Node::setSize(width, height);
  updateBarsGeometry();
}

void AudioSpectrum::doLayout(Renderer& /*renderer*/) { updateBarsGeometry(); }

void AudioSpectrum::updateBarsGeometry() {
  const int barCount = static_cast<int>(m_bars.size());
  if (barCount <= 0 || width() <= 0.0f || height() <= 0.0f) {
    return;
  }

  // Sharp grid: integer-pixel unit shared by bars and gaps. Total slots along the
  // main axis = barCount bars + (barCount - 1) gaps. Any leftover from the floor
  // is split evenly at both ends so the strip stays centered.
  const bool horizontal = m_orientation == AudioSpectrumOrientation::Horizontal;
  const float mainAxisLen = horizontal ? width() : height();
  const float crossAxisLen = horizontal ? height() : width();
  const int slots = std::max(1, 2 * barCount - 1);
  const float unit = std::max(1.0f, std::floor(mainAxisLen / static_cast<float>(slots)));
  const float used = unit * static_cast<float>(slots);
  const float startOffset = std::floor(std::max(0.0f, (mainAxisLen - used) * 0.5f));
  const float stride = unit * 2.0f; // bar + gap

  for (int i = 0; i < barCount; ++i) {
    const int valueIndex =
        m_mirrored ? (i < static_cast<int>(m_displayValues.size()) ? static_cast<int>(m_displayValues.size()) - 1 - i
                                                                   : i - static_cast<int>(m_displayValues.size()))
                   : i;
    const float rawValue = valueIndex >= 0 && valueIndex < static_cast<int>(m_displayValues.size())
                               ? std::clamp(m_displayValues[static_cast<std::size_t>(valueIndex)], 0.0f, 1.0f)
                               : 0.0f;
    const float value = std::max(rawValue, m_minDisplayValue);
    float crossSize = std::max(1.0f, std::floor(value * crossAxisLen + 0.5f));
    // When centered, force an even cross size so the bar lands on integer columns
    // on both sides — odd sizes would leave a 1-px right-edge wobble between bars.
    if (m_centered) {
      crossSize = std::max(2.0f, std::round(crossSize * 0.5f) * 2.0f);
    }
    const float mainPos = startOffset + static_cast<float>(i) * stride;
    const float crossPos =
        m_centered ? std::floor((crossAxisLen - crossSize) * 0.5f) : std::floor(crossAxisLen - crossSize);
    if (auto* bar = m_bars[static_cast<std::size_t>(i)]; bar != nullptr) {
      if (horizontal) {
        bar->setPosition(mainPos, crossPos);
        bar->setFrameSize(unit, crossSize);
      } else {
        bar->setPosition(crossPos, mainPos);
        bar->setFrameSize(crossSize, unit);
      }
    }
  }
}

void AudioSpectrum::ensureBarCount(std::size_t count) {
  while (m_bars.size() < count) {
    auto bar = std::make_unique<Box>();
    bar->clearBorder();
    bar->setRadius(0.0f);
    bar->setSoftness(0.0f);
    m_bars.push_back(static_cast<Box*>(addChild(std::move(bar))));
  }

  while (m_bars.size() > count) {
    removeChild(m_bars.back());
    m_bars.pop_back();
  }

  recolorBars();
}

void AudioSpectrum::recolorBars() {
  const Color lowColor = resolveColorSpec(m_lowColor);
  const Color highColor = resolveColorSpec(m_highColor);
  const std::size_t lastIndex = m_bars.empty() ? 0 : m_bars.size() - 1;
  for (std::size_t i = 0; i < m_bars.size(); ++i) {
    const float t = lastIndex == 0 ? 0.0f : static_cast<float>(i) / static_cast<float>(lastIndex);
    if (auto* bar = m_bars[i]; bar != nullptr) {
      bar->setFill(lerpColor(lowColor, highColor, t));
    }
  }
}

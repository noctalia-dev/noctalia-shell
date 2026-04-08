#include "ui/controls/audio_spectrum.h"

#include "render/core/color.h"
#include "ui/controls/box.h"

#include <algorithm>
#include <cmath>
#include <memory>

AudioSpectrum::AudioSpectrum() {
  m_lowColor = hex("#ebbcba");
  m_highColor = hex("#9ccfd8");
}

void AudioSpectrum::setValues(const std::vector<float>& values) {
  m_values = values;
  ensureBarCount(m_mirrored ? m_values.size() * 2 : m_values.size());
  markDirty();
}

void AudioSpectrum::setGradient(const Color& lowColor, const Color& highColor) {
  m_lowColor = lowColor;
  m_highColor = highColor;
  recolorBars();
}

void AudioSpectrum::setSpacingRatio(float ratio) {
  const float clamped = std::max(0.0f, ratio);
  if (m_spacingRatio == clamped) {
    return;
  }
  m_spacingRatio = clamped;
  markDirty();
}

void AudioSpectrum::setOrientation(AudioSpectrumOrientation orientation) {
  if (m_orientation == orientation) {
    return;
  }
  m_orientation = orientation;
  markDirty();
}

void AudioSpectrum::setMirrored(bool mirrored) {
  if (m_mirrored == mirrored) {
    return;
  }
  m_mirrored = mirrored;
  ensureBarCount(m_mirrored ? m_values.size() * 2 : m_values.size());
  markDirty();
}

void AudioSpectrum::setCentered(bool centered) {
  if (m_centered == centered) {
    return;
  }
  m_centered = centered;
  markDirty();
}

void AudioSpectrum::layout(Renderer& /*renderer*/) {
  const int barCount = static_cast<int>(m_bars.size());
  if (barCount <= 0 || width() <= 0.0f || height() <= 0.0f) {
    return;
  }

  const float slotUnits = static_cast<float>(barCount) + m_spacingRatio * static_cast<float>(std::max(0, barCount - 1));
  if (m_orientation == AudioSpectrumOrientation::Horizontal) {
    const float barWidth = std::max(1.0f, std::floor(width() / std::max(1.0f, slotUnits)));
    const float gap = std::floor(barWidth * m_spacingRatio);
    const float usedWidth =
        barWidth * static_cast<float>(barCount) + gap * static_cast<float>(std::max(0, barCount - 1));
    float x = std::floor(std::max(0.0f, (width() - usedWidth) * 0.5f));

    for (int i = 0; i < barCount; ++i) {
      const int valueIndex =
          m_mirrored ? (i < static_cast<int>(m_values.size()) ? static_cast<int>(m_values.size()) - 1 - i
                                                              : i - static_cast<int>(m_values.size()))
                     : i;
      const float value =
          valueIndex >= 0 && valueIndex < static_cast<int>(m_values.size())
              ? std::clamp(m_values[static_cast<std::size_t>(valueIndex)], 0.0f, 1.0f)
              : 0.0f;
      const float barHeight = std::floor(value * height() + 0.5f);
      const float y = m_centered ? std::floor((height() - barHeight) * 0.5f) : std::floor(height() - barHeight);
      if (auto* bar = m_bars[static_cast<std::size_t>(i)]; bar != nullptr) {
        bar->setPosition(x, y);
        bar->setSize(barWidth, barHeight);
      }
      x += barWidth + gap;
    }
    return;
  }

  const float barHeight = std::max(1.0f, std::floor(height() / std::max(1.0f, slotUnits)));
  const float gap = std::floor(barHeight * m_spacingRatio);
  const float usedHeight =
      barHeight * static_cast<float>(barCount) + gap * static_cast<float>(std::max(0, barCount - 1));
  float y = std::floor(std::max(0.0f, (height() - usedHeight) * 0.5f));

  for (int i = 0; i < barCount; ++i) {
    const int valueIndex =
        m_mirrored ? (i < static_cast<int>(m_values.size()) ? static_cast<int>(m_values.size()) - 1 - i
                                                            : i - static_cast<int>(m_values.size()))
                   : i;
    const float value =
        valueIndex >= 0 && valueIndex < static_cast<int>(m_values.size())
            ? std::clamp(m_values[static_cast<std::size_t>(valueIndex)], 0.0f, 1.0f)
            : 0.0f;
    const float barWidth = std::floor(value * width() + 0.5f);
    const float x = m_centered ? std::floor((width() - barWidth) * 0.5f) : std::floor(width() - barWidth);
    if (auto* bar = m_bars[static_cast<std::size_t>(i)]; bar != nullptr) {
      bar->setPosition(x, y);
      bar->setSize(barWidth, barHeight);
    }
    y += barHeight + gap;
  }
}

void AudioSpectrum::ensureBarCount(std::size_t count) {
  while (m_bars.size() < count) {
    auto bar = std::make_unique<Box>();
    bar->setBorder(rgba(0, 0, 0, 0), 0.0f);
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
  const std::size_t lastIndex = m_bars.empty() ? 0 : m_bars.size() - 1;
  for (std::size_t i = 0; i < m_bars.size(); ++i) {
    const float t = lastIndex == 0 ? 0.0f : static_cast<float>(i) / static_cast<float>(lastIndex);
    if (auto* bar = m_bars[i]; bar != nullptr) {
      bar->setFill(lerpColor(m_lowColor, m_highColor, t));
    }
  }
}

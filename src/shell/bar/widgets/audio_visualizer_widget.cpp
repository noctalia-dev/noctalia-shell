#include "shell/bar/widgets/audio_visualizer_widget.h"

#include "pipewire/pipewire_spectrum.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "ui/controls/audio_spectrum.h"
#include "ui/palette.h"

#include <algorithm>
#include <memory>

AudioVisualizerWidget::AudioVisualizerWidget(PipeWireSpectrum* spectrum, float width, float height, int bands,
                                             bool mirrored, ThemeColor lowColor, ThemeColor highColor)
    : m_spectrum(spectrum), m_width(width), m_height(height), m_bands(std::max(1, bands)), m_mirrored(mirrored),
      m_lowColor(lowColor), m_highColor(highColor) {}

AudioVisualizerWidget::~AudioVisualizerWidget() {
  if (m_spectrum != nullptr && m_listenerId != 0) {
    m_spectrum->removeChangeListener(m_listenerId);
  }
}

void AudioVisualizerWidget::create() {
  auto root = std::make_unique<InputArea>();
  root->setEnabled(false);

  auto visualizer = std::make_unique<AudioSpectrum>();
  visualizer->setOrientation(AudioSpectrumOrientation::Horizontal);
  visualizer->setLayoutMode(AudioSpectrumLayoutMode::Fill);
  visualizer->setCentered(true);
  visualizer->setMirrored(m_mirrored);
  visualizer->setSpacingRatio(0.4f);
  visualizer->setGradient(m_lowColor, m_highColor);
  m_visualizer = visualizer.get();
  root->addChild(std::move(visualizer));

  if (m_spectrum != nullptr) {
    m_listenerId = m_spectrum->addChangeListener(m_bands, [this]() {
      m_pendingSpectrumUpdate = true;
      requestRedraw();
    });
  }

  setRoot(std::move(root));
}

void AudioVisualizerWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  m_renderer = &renderer;
  if (root() == nullptr || m_visualizer == nullptr) {
    return;
  }

  m_isVertical = containerHeight > containerWidth;
  m_visualizer->setOrientation(m_isVertical ? AudioSpectrumOrientation::Vertical
                                            : AudioSpectrumOrientation::Horizontal);
  const float width = std::max(1.0f, (m_isVertical ? m_height : m_width) * m_contentScale);
  const float height = std::max(1.0f, (m_isVertical ? m_width : m_height) * m_contentScale);
  m_visualizer->setPosition(0.0f, 0.0f);
  m_visualizer->setSize(width, height);
  m_visualizer->layout(renderer);
  root()->setSize(width, height);
}

void AudioVisualizerWidget::doUpdate(Renderer& renderer) {
  m_renderer = &renderer;
  syncSpectrum();
}

void AudioVisualizerWidget::onFrameTick(float deltaMs) {
  if (m_visualizer == nullptr) {
    return;
  }
  syncSpectrum();
  m_visualizer->tick(deltaMs);
  if (m_renderer != nullptr) {
    m_visualizer->layout(*m_renderer);
  }
}

bool AudioVisualizerWidget::needsFrameTick() const {
  return m_visualizer != nullptr && (m_pendingSpectrumUpdate || !m_visualizer->converged());
}

void AudioVisualizerWidget::syncSpectrum() {
  if (!m_pendingSpectrumUpdate || m_visualizer == nullptr || m_spectrum == nullptr || m_listenerId == 0) {
    return;
  }

  m_visualizer->setValues(m_spectrum->values(m_listenerId));
  m_pendingSpectrumUpdate = false;
  if (m_renderer != nullptr) {
    m_visualizer->layout(*m_renderer);
  }
}

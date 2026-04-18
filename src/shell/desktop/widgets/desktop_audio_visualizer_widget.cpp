#include "shell/desktop/widgets/desktop_audio_visualizer_widget.h"

#include "pipewire/pipewire_spectrum.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/audio_spectrum.h"
#include "ui/palette.h"

#include <algorithm>
#include <memory>

DesktopAudioVisualizerWidget::DesktopAudioVisualizerWidget(PipeWireSpectrum* spectrum, float width, float height,
                                                           int bands)
    : m_spectrum(spectrum), m_width(std::max(1.0f, width)), m_height(std::max(1.0f, height)), m_bands(std::max(1, bands)) {}

DesktopAudioVisualizerWidget::~DesktopAudioVisualizerWidget() {
  if (m_spectrum != nullptr && m_listenerId != 0) {
    m_spectrum->removeChangeListener(m_listenerId);
  }
}

void DesktopAudioVisualizerWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto visualizer = std::make_unique<AudioSpectrum>();
  visualizer->setOrientation(AudioSpectrumOrientation::Horizontal);
  visualizer->setLayoutMode(AudioSpectrumLayoutMode::Fill);
  visualizer->setCentered(true);
  visualizer->setMirrored(false);
  visualizer->setSpacingRatio(0.4f);
  visualizer->setSmoothingTimeMs(60.0f);
  visualizer->setGradient(resolveColorRole(ColorRole::Primary), resolveColorRole(ColorRole::Secondary));
  m_visualizer = visualizer.get();
  rootNode->addChild(std::move(visualizer));

  if (m_spectrum != nullptr) {
    m_spectrum->setBandCount(m_bands);
    m_listenerId = m_spectrum->addChangeListener([this]() {
      m_pendingSpectrumUpdate = true;
      requestRedraw();
    });
  }

  setRoot(std::move(rootNode));
}

bool DesktopAudioVisualizerWidget::needsFrameTick() const {
  return m_visualizer != nullptr && (m_pendingSpectrumUpdate || !m_visualizer->converged());
}

void DesktopAudioVisualizerWidget::onFrameTick(float deltaMs, Renderer& renderer) {
  if (m_visualizer == nullptr) {
    return;
  }
  syncSpectrum(&renderer);
  m_visualizer->tick(deltaMs);
  m_visualizer->layout(renderer);
}

void DesktopAudioVisualizerWidget::doLayout(Renderer& renderer) {
  if (root() == nullptr || m_visualizer == nullptr) {
    return;
  }

  syncSpectrum(&renderer);
  const float width = m_width * m_contentScale;
  const float height = m_height * m_contentScale;
  m_visualizer->setPosition(0.0f, 0.0f);
  m_visualizer->setSize(width, height);
  m_visualizer->layout(renderer);
  root()->setSize(width, height);
}

void DesktopAudioVisualizerWidget::doUpdate(Renderer& renderer) { syncSpectrum(&renderer); }

void DesktopAudioVisualizerWidget::syncSpectrum(Renderer* renderer) {
  if (!m_pendingSpectrumUpdate || m_visualizer == nullptr || m_spectrum == nullptr) {
    return;
  }

  m_visualizer->setValues(m_spectrum->values());
  m_pendingSpectrumUpdate = false;
  if (renderer != nullptr) {
    m_visualizer->layout(*renderer);
  }
}

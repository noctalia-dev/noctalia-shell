#include "shell/desktop/widgets/desktop_audio_visualizer_widget.h"

#include "pipewire/pipewire_spectrum.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/audio_spectrum.h"
#include "ui/palette.h"

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

  constexpr float kDefaultVisualizerArea = 240.0f * 96.0f;

  float clampAspectRatio(float aspectRatio) { return std::max(0.05f, aspectRatio); }

  float visualizerBaseWidth(float aspectRatio) {
    return std::sqrt(kDefaultVisualizerArea * clampAspectRatio(aspectRatio));
  }

  float visualizerBaseHeight(float aspectRatio) {
    return std::sqrt(kDefaultVisualizerArea / clampAspectRatio(aspectRatio));
  }

} // namespace

DesktopAudioVisualizerWidget::DesktopAudioVisualizerWidget(PipeWireSpectrum* spectrum, float aspectRatio, int bands,
                                                           bool mirrored, ColorSpec lowColor, ColorSpec highColor,
                                                           float minValue)
    : m_spectrum(spectrum), m_aspectRatio(clampAspectRatio(aspectRatio)), m_bands(std::max(1, bands)),
      m_mirrored(mirrored), m_lowColor(lowColor), m_highColor(highColor), m_minValue(std::clamp(minValue, 0.0f, 1.0f)) {
}

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
  visualizer->setMirrored(m_mirrored);
  visualizer->setSpacingRatio(0.4f);
  visualizer->setGradient(m_lowColor, m_highColor);
  visualizer->setMinDisplayValue(m_minValue);
  m_visualizer = visualizer.get();
  rootNode->addChild(std::move(visualizer));

  if (m_spectrum != nullptr) {
    m_listenerId = m_spectrum->addChangeListener(m_bands, [this]() {
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
  const float width = visualizerBaseWidth(m_aspectRatio) * m_contentScale;
  const float height = visualizerBaseHeight(m_aspectRatio) * m_contentScale;
  m_visualizer->setPosition(0.0f, 0.0f);
  m_visualizer->setSize(width, height);
  m_visualizer->layout(renderer);
  root()->setSize(width, height);
}

void DesktopAudioVisualizerWidget::doUpdate(Renderer& renderer) { syncSpectrum(&renderer); }

void DesktopAudioVisualizerWidget::syncSpectrum(Renderer* renderer) {
  if (!m_pendingSpectrumUpdate || m_visualizer == nullptr || m_spectrum == nullptr || m_listenerId == 0) {
    return;
  }

  m_visualizer->setValues(m_spectrum->values(m_listenerId));
  m_pendingSpectrumUpdate = false;
  if (renderer != nullptr) {
    m_visualizer->layout(*renderer);
  }
}

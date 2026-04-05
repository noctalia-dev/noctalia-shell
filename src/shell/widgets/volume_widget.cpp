#include "shell/widgets/volume_widget.h"

#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace {

const char* volumeIconName(float volume, bool muted) {
  if (muted || volume <= 0.0f) {
    return "volume-mute";
  }
  if (volume < 0.4f) {
    return "volume-low";
  }
  return "volume-high";
}

} // namespace

VolumeWidget::VolumeWidget(PipeWireService* audio) : m_audio(audio) {}

void VolumeWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Node>();

  auto icon = std::make_unique<Icon>();
  icon->setIcon("volume-high");
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  container->addChild(std::move(icon));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  m_label = label.get();
  container->addChild(std::move(label));

  m_root = std::move(container);
  syncState(renderer);
}

void VolumeWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_icon == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }

  m_icon->measure(renderer);
  m_label->measure(renderer);

  // Icon and label share the same reference line height, so y=0 aligns both.
  m_icon->setPosition(0.0f, 0.0f);
  m_label->setPosition(m_icon->width() + Style::spaceXs, 0.0f);

  rootNode->setSize(m_label->x() + m_label->width(), m_icon->height());
}

void VolumeWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void VolumeWidget::syncState(Renderer& renderer) {
  if (m_audio == nullptr || m_icon == nullptr || m_label == nullptr) {
    return;
  }

  const auto* sink = m_audio->defaultSink();
  float volume = sink != nullptr ? sink->volume : 0.0f;
  bool muted = sink != nullptr ? sink->muted : false;

  if (volume == m_lastVolume && muted == m_lastMuted) {
    return;
  }

  m_lastVolume = volume;
  m_lastMuted = muted;

  m_icon->setIcon(volumeIconName(volume, muted));
  m_icon->setColor(muted ? palette.onSurfaceVariant : palette.onSurface);
  m_icon->measure(renderer);

  int pct = static_cast<int>(std::round(volume * 100.0f));
  m_label->setText(std::to_string(pct) + "%");
  m_label->measure(renderer);

  requestRedraw();
}

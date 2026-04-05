#include "shell/widgets/volume_widget.h"

#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "ui/controls/flex.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

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
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Horizontal);
  container->setGap(Style::spaceXs);
  container->setAlign(FlexAlign::Center);

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
  if (m_icon != nullptr) {
    m_icon->measure(renderer);
  }
  if (m_label != nullptr) {
    m_label->measure(renderer);
  }
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

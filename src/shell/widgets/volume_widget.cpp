#include "shell/widgets/volume_widget.h"

#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/glyph.h"
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

VolumeWidget::VolumeWidget(PipeWireService* audio, wl_output* output, std::int32_t scale)
    : m_audio(audio), m_output(output), m_scale(scale) {}

void VolumeWidget::create(Renderer& renderer) {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    // auto* node = root();
    // if (node != nullptr) {
    //   Node::absolutePosition(node, absX, absY);
    //   absX += node->width() * 0.5f;
    //   absY += node->height() * 0.5f;
    // }
    PanelManager::instance().togglePanel("control-center", m_output, m_scale, absX, absY, "media");
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("volume-high");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.onSurface);
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  area->addChild(std::move(label));

  m_root = std::move(area);
  syncState(renderer);
}

void VolumeWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }

  m_glyph->measure(renderer);
  m_label->measure(renderer);

  // Glyph and label share the same reference line height, so y=0 aligns both.
  m_glyph->setPosition(0.0f, 0.0f);
  m_label->setPosition(m_glyph->width() + Style::spaceXs, 0.0f);

  rootNode->setSize(m_label->x() + m_label->width(), m_glyph->height());
}

void VolumeWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void VolumeWidget::syncState(Renderer& renderer) {
  if (m_audio == nullptr || m_glyph == nullptr || m_label == nullptr) {
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

  m_glyph->setGlyph(volumeIconName(volume, muted));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->setColor(muted ? palette.onSurfaceVariant : palette.onSurface);
  m_glyph->measure(renderer);

  int pct = static_cast<int>(std::round(volume * 100.0f));
  m_label->setText(std::to_string(pct) + "%");
  m_label->measure(renderer);

  requestRedraw();
}

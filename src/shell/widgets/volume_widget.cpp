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

const char* volumeGlyphName(float volume, bool muted) {
  if (muted || volume <= 0.0f) {
    return "volume-mute";
  }
  if (volume < 0.4f) {
    return "volume-low";
  }
  return "volume-high";
}

} // namespace

VolumeWidget::VolumeWidget(PipeWireService* audio, wl_output* output)
    : m_audio(audio), m_output(output) {}

void VolumeWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("control-center", m_output, 0.0f, 0.0f, "audio");
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("volume-high");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  area->addChild(std::move(label));

  setRoot(std::move(area));
}

void VolumeWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (m_glyph == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;
  syncState(renderer);

  m_glyph->measure(renderer);
  m_label->measure(renderer);

  if (m_isVertical) {
    const float w = std::max(m_glyph->width(), m_label->width());
    m_glyph->setPosition(std::round((w - m_glyph->width()) * 0.5f), 0.0f);
    m_label->setPosition(std::round((w - m_label->width()) * 0.5f), m_glyph->height());
    rootNode->setSize(w, m_glyph->height() + m_label->height());
  } else {
    // Glyph and label share the same reference line height, so y=0 aligns both.
    m_glyph->setPosition(0.0f, 0.0f);
    m_label->setPosition(m_glyph->width() + Style::spaceXs, 0.0f);
    rootNode->setSize(m_label->x() + m_label->width(), m_glyph->height());
  }
}

void VolumeWidget::doUpdate(Renderer& renderer) {
  syncState(renderer);
}

void VolumeWidget::syncState(Renderer& renderer) {
  if (m_audio == nullptr || m_glyph == nullptr || m_label == nullptr) {
    return;
  }

  const auto* sink = m_audio->defaultSink();
  float volume = sink != nullptr ? sink->volume : 0.0f;
  bool muted = sink != nullptr ? sink->muted : false;

  if (volume == m_lastVolume && muted == m_lastMuted && m_isVertical == m_lastVertical) {
    return;
  }

  m_lastVolume = volume;
  m_lastMuted = muted;
  m_lastVertical = m_isVertical;

  m_glyph->setGlyph(volumeGlyphName(volume, muted));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->setColor(muted ? roleColor(ColorRole::OnSurfaceVariant)
                          : widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph->measure(renderer);

  int pct = static_cast<int>(std::round(volume * 100.0f));
  m_label->setFontSize((m_isVertical ? Style::fontSizeCaption : Style::fontSizeBody) * m_contentScale);
  m_label->setText(m_isVertical ? std::to_string(pct) : std::to_string(pct) + "%");
  m_label->setColor(muted ? roleColor(ColorRole::OnSurfaceVariant)
                          : widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_label->measure(renderer);

  requestRedraw();
}

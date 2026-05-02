#include "shell/bar/widgets/power_profiles_widget.h"

#include "dbus/power/power_profiles_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

PowerProfilesWidget::PowerProfilesWidget(PowerProfilesService* powerProfiles) : m_powerProfiles(powerProfiles) {}

void PowerProfilesWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) { cycleProfile(); });
  m_area = area.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("balanced");
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  setRoot(std::move(area));
}

void PowerProfilesWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || rootNode == nullptr) {
    return;
  }
  syncState(renderer);

  m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  m_glyph->setColor(m_available ? widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface))
                                : colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_glyph->measure(renderer);
  m_glyph->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_glyph->width(), m_glyph->height());
}

void PowerProfilesWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void PowerProfilesWidget::syncState(Renderer& renderer) {
  if (m_glyph == nullptr || m_area == nullptr) {
    return;
  }

  const std::string profile = m_powerProfiles != nullptr ? m_powerProfiles->activeProfile() : std::string{};
  const bool available = m_powerProfiles != nullptr && (!profile.empty() || !m_powerProfiles->profiles().empty());

  if (profile == m_lastProfile && available == m_available) {
    return;
  }

  m_available = available;
  m_lastProfile = profile;

  m_glyph->setGlyph(glyphForProfile(profile));
  m_glyph->setColor(m_available ? widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface))
                                : colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_glyph->measure(renderer);
  m_area->setEnabled(m_available);
  if (auto* rootNode = root(); rootNode != nullptr) {
    rootNode->setOpacity(m_available ? 1.0f : 0.55f);
  }
  requestRedraw();
}

void PowerProfilesWidget::cycleProfile() {
  if (m_powerProfiles == nullptr) {
    return;
  }

  const auto& profiles = m_powerProfiles->profiles();
  if (profiles.empty()) {
    return;
  }

  const auto current = m_powerProfiles->activeProfile();
  auto it = std::find(profiles.begin(), profiles.end(), current);
  if (it == profiles.end()) {
    (void)m_powerProfiles->setActiveProfile(profiles.front());
    return;
  }

  ++it;
  if (it == profiles.end()) {
    it = profiles.begin();
  }
  (void)m_powerProfiles->setActiveProfile(*it);
}

const char* PowerProfilesWidget::glyphForProfile(std::string_view profile) {
  if (profile == "performance") {
    return "performance";
  }
  if (profile == "power-saver") {
    return "powersaver";
  }
  return "balanced";
}

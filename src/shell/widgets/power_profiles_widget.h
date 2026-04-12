#pragma once

#include "shell/widget/widget.h"

#include <string>

class Glyph;
class InputArea;
class PowerProfilesService;

class PowerProfilesWidget : public Widget {
public:
  explicit PowerProfilesWidget(PowerProfilesService* powerProfiles);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);
  void cycleProfile();
  [[nodiscard]] static const char* glyphForProfile(std::string_view profile);

  PowerProfilesService* m_powerProfiles = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  std::string m_lastProfile;
  bool m_available = false;
};

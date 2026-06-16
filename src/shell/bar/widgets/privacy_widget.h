#pragma once

#include "shell/bar/widget.h"
#include "shell/tooltip/tooltip_content.h"
#include "ui/palette.h"

#include <optional>
#include <regex>
#include <string>
#include <vector>

class Glyph;
class InputArea;
class PipeWireService;
class Renderer;

struct PrivacyWidgetConfig {
  bool hideInactive = false;
  int iconSpacing = 4;
  ColorSpec activeColor = colorSpecFromRole(ColorRole::Primary);
  ColorSpec inactiveColor = colorSpecFromRole(ColorRole::Outline);
  std::string micFilterRegex;
  std::string camFilterRegex;
};

class PrivacyWidget : public Widget {
public:
  PrivacyWidget(PipeWireService* pipewire, PrivacyWidgetConfig config);

  void create() override;

private:
  struct Snapshot {
    std::vector<std::string> micApps;
    std::vector<std::string> cameraApps;
    std::vector<std::string> screenApps;
    bool vertical = false;

    [[nodiscard]] bool micActive() const { return !micApps.empty(); }
    [[nodiscard]] bool cameraActive() const { return !cameraApps.empty(); }
    [[nodiscard]] bool screenActive() const { return !screenApps.empty(); }
    [[nodiscard]] bool anyActive() const { return micActive() || cameraActive() || screenActive(); }
    [[nodiscard]] bool visible(bool hideInactive) const { return !hideInactive || anyActive(); }

    bool operator==(const Snapshot&) const = default;
  };

  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState();
  [[nodiscard]] Snapshot snapshot() const;
  [[nodiscard]] std::vector<TooltipRow> buildTooltipRows() const;
  [[nodiscard]] bool matchesFilter(const std::optional<std::regex>& filter, const std::string& value) const;

  PipeWireService* m_pipewire = nullptr;
  PrivacyWidgetConfig m_config;
  std::optional<std::regex> m_micFilter;
  std::optional<std::regex> m_camFilter;

  InputArea* m_area = nullptr;
  Glyph* m_micGlyph = nullptr;
  Glyph* m_cameraGlyph = nullptr;
  Glyph* m_screenGlyph = nullptr;

  std::optional<Snapshot> m_cachedSnapshot;
  bool m_isVertical = false;
};

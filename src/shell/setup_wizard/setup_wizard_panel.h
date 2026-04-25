#pragma once

#include "shell/panel/panel.h"

#include <string>

class Button;
class ConfigService;
class Flex;
class Image;
class Label;
class Renderer;
class Select;
class Toggle;
class WaylandConnection;

class SetupWizardPanel : public Panel {
public:
  SetupWizardPanel(ConfigService* config, WaylandConnection* wayland) : m_config(config), m_wayland(wayland) {}

  void create() override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(560.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(500.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] bool hasDecoration() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::OnDemand; }

  static bool isFirstRun();

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void commit();

  ConfigService* m_config = nullptr;
  WaylandConnection* m_wayland = nullptr;
  Flex* m_root = nullptr;
  Image* m_logo = nullptr;
  Toggle* m_telemetryToggle = nullptr;
  Select* m_modeSelect = nullptr;
  Select* m_paletteSelect = nullptr;
  Label* m_wallpaperLabel = nullptr;
  std::string m_wallpaperDir;
};

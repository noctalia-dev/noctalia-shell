#pragma once

#include "dbus/tray/tray_service.h"
#include "shell/panel/panel.h"

#include <memory>
#include <string>
#include <vector>

class ConfigService;
class Renderer;
class TrayWidget;

class TrayDrawerPanel : public Panel {
public:
  TrayDrawerPanel(TrayService* tray, ConfigService* config, std::size_t drawerColumns = 3);
  ~TrayDrawerPanel() override;

  void create() override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override;
  [[nodiscard]] float preferredHeight() const override;
  [[nodiscard]] bool centeredHorizontally() const override { return false; }
  [[nodiscard]] bool centeredVertically() const override { return false; }
  [[nodiscard]] bool prefersAttachedToBar() const noexcept override { return true; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::OnDemand; }

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  [[nodiscard]] std::vector<std::string> currentHiddenItems() const;
  [[nodiscard]] std::vector<std::string> currentPinnedItems() const;
  [[nodiscard]] std::size_t visibleItemCount() const;

  TrayService* m_tray = nullptr;
  ConfigService* m_config = nullptr;
  std::size_t m_drawerColumns = 3;
  std::unique_ptr<TrayWidget> m_drawerWidget;
};

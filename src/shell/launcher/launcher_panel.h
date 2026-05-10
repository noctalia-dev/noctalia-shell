#pragma once

#include "launcher/app_categories.h"
#include "launcher/launcher_provider.h"
#include "launcher/usage_tracker.h"
#include "shell/panel/panel.h"
#include "system/icon_resolver.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class ContextMenuPopup;
class Flex;
class Input;
class InputArea;
class Label;
class LauncherResultAdapter;
class Renderer;
class Segmented;
class VirtualGridView;
class ConfigService;
class AsyncTextureCache;
class AppProvider;

class LauncherPanel : public Panel {
public:
  LauncherPanel(ConfigService* config, AsyncTextureCache* asyncTextures);
  ~LauncherPanel() override;

  void addProvider(std::unique_ptr<LauncherProvider> provider);

  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;
  void onIconThemeChanged() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(560.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(460.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;
  [[nodiscard]] bool prefersAttachedToBar() const noexcept override;
  [[nodiscard]] bool wantsCloseAnimation() const noexcept override { return false; }

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void onInputChanged(const std::string& text);
  void refreshResults();
  void activateAt(std::size_t index);
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void applyEmptyState();
  void openAppActionsMenu(std::size_t index, float anchorX, float anchorY);
  [[nodiscard]] std::unique_ptr<Segmented> createCategoryTabs(float scale);
  [[nodiscard]] std::unique_ptr<Flex> createCategoryTooltip(float scale);
  [[nodiscard]] AppProvider* appProvider() const;
  void updateCategoryTabs();
  void selectCategory(std::size_t index);
  void cycleCategory(bool reverse);
  void updateCategoryTooltip(std::string_view label, float localAnchorX);
  void hideCategoryTooltip();
  void layoutCategoryTooltip(Renderer& renderer);

  std::vector<std::unique_ptr<LauncherProvider>> m_providers;
  std::vector<LauncherResult> m_results;
  std::vector<LauncherAppCategory> m_categories;
  UsageTracker m_usageTracker;
  IconResolver m_iconResolver;

  Flex* m_container = nullptr;
  Input* m_input = nullptr;
  Segmented* m_categoryTabs = nullptr;
  Flex* m_categoryTooltip = nullptr;
  Label* m_categoryTooltipLabel = nullptr;
  Flex* m_body = nullptr;
  VirtualGridView* m_grid = nullptr;
  Label* m_emptyLabel = nullptr;
  std::unique_ptr<LauncherResultAdapter> m_adapter;

  std::string m_query;
  std::size_t m_selectedIndex = 0;
  std::optional<float> m_categoryTooltipAnchorX;
  bool m_updatingCategoryTabs = false;
  ConfigService* m_config = nullptr;
  AsyncTextureCache* m_asyncTextures = nullptr;
  std::unique_ptr<ContextMenuPopup> m_actionsMenu;
};

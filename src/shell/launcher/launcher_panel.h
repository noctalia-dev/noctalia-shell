#pragma once

#include "launcher/launcher_provider.h"
#include "launcher/usage_tracker.h"
#include "shell/panel/panel.h"
#include "system/icon_resolver.h"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

class Flex;
class Glyph;
class Image;
class Input;
class InputArea;
class Label;
class Node;
class Renderer;
class ScrollView;
class ConfigService;
class AsyncTextureCache;

class LauncherPanel : public Panel {
public:
  LauncherPanel(ConfigService* config, AsyncTextureCache* asyncTextures);

  void addProvider(std::unique_ptr<LauncherProvider> provider);

  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(560.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(460.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  void onInputChanged(const std::string& text);
  void rebuildResults(Renderer& renderer, float width);
  void ensureRowPool(float viewportHeight);
  void updateVisibleRowStates();
  bool resolveVisibleIcons(std::size_t budget);
  bool hasPendingVisibleIcons() const;
  void scheduleVisibleIconUpdate();
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void scrollToSelected();

  std::vector<std::unique_ptr<LauncherProvider>> m_providers;
  std::vector<LauncherResult> m_results;
  UsageTracker m_usageTracker;
  IconResolver m_iconResolver;

  Flex* m_container = nullptr;
  Input* m_input = nullptr;
  ScrollView* m_scrollView = nullptr;
  Flex* m_list = nullptr;
  Node* m_resultsRoot = nullptr;
  Label* m_emptyLabel = nullptr;
  std::vector<InputArea*> m_rowPool;

  std::string m_query;
  std::size_t m_selectedIndex = 0;
  std::size_t m_hoverIndex = static_cast<std::size_t>(-1);
  std::size_t m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  float m_lastWidth = 0.0f;
  float m_lastListWidth = -1.0f;
  float m_virtualRowHeight = 0.0f;
  bool m_dirty = false;
  bool m_iconUpdateQueued = false;
  bool m_mouseActive = false;
  bool m_pendingScrollToSelected = false;
  ConfigService* m_config = nullptr;
  AsyncTextureCache* m_asyncTextures = nullptr;
};

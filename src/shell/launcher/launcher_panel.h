#pragma once

#include "launcher/launcher_provider.h"
#include "shell/panel/panel.h"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

class Flex;
class Icon;
class Image;
class Input;
class InputArea;
class Label;
class Renderer;
class ScrollView;

class LauncherPanel : public Panel {
public:
  LauncherPanel();

  void addProvider(std::unique_ptr<LauncherProvider> provider);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return 560.0f; }
  [[nodiscard]] float preferredHeight() const override { return 460.0f; }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void onInputChanged(const std::string& text);
  void rebuildResults(Renderer& renderer, float width);
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void scrollToSelected();

  std::vector<std::unique_ptr<LauncherProvider>> m_providers;
  std::vector<LauncherResult> m_results;

  Flex* m_container = nullptr;
  Input* m_input = nullptr;
  ScrollView* m_scrollView = nullptr;
  Flex* m_list = nullptr;

  std::string m_query;
  std::size_t m_selectedIndex = 0;
  float m_lastWidth = 0.0f;
  bool m_dirty = false;
};

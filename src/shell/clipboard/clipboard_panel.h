#pragma once

#include "shell/panel/panel.h"
#include "core/timer_manager.h"

#include <cstddef>
#include <cstdint>

class Button;
class ClipboardService;
class Flex;
class Image;
class InputArea;
class Label;
class Renderer;
class ScrollView;

class ClipboardPanel : public Panel {
public:
  explicit ClipboardPanel(ClipboardService* clipboard);

  void create() override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(920.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(560.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void schedulePreviewPayloadRefresh(bool debounced);
  void rebuildList(Renderer& renderer, float width);
  void rebuildPreview(Renderer& renderer, float width, float height);
  void selectIndex(std::size_t index);
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void scrollToSelected();

  ClipboardService* m_clipboard = nullptr;

  InputArea* m_focusArea = nullptr;
  Flex* m_rootLayout = nullptr;
  Flex* m_sidebar = nullptr;
  Flex* m_sidebarHeaderRow = nullptr;
  Label* m_sidebarTitle = nullptr;
  Button* m_clearHistoryButton = nullptr;
  ScrollView* m_listScrollView = nullptr;
  Flex* m_list = nullptr;

  Flex* m_previewCard = nullptr;
  Flex* m_previewHeaderRow = nullptr;
  Label* m_previewTitle = nullptr;
  Label* m_previewMeta = nullptr;
  Button* m_copyButton = nullptr;
  ScrollView* m_previewScrollView = nullptr;
  Flex* m_previewContent = nullptr;
  Image* m_previewImage = nullptr;

  std::size_t m_selectedIndex = 0;
  std::size_t m_previewPayloadIndex = static_cast<std::size_t>(-1);
  std::size_t m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
  std::size_t m_hoverIndex = static_cast<std::size_t>(-1);
  Timer m_previewPayloadDebounceTimer;
  bool m_mouseActive = false;
  std::uint64_t m_lastChangeSerial = 0;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  float m_lastListWidth = -1.0f;
  float m_lastPreviewWidth = -1.0f;
  float m_lastPreviewHeight = -1.0f;
  bool m_pendingScrollToSelected = false;
};

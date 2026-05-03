#pragma once

#include "core/timer_manager.h"
#include "shell/panel/panel.h"
#include "wayland/clipboard_service.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

class Button;
class ClipboardService;
class Flex;
class Image;
class Input;
class InputArea;
class Label;
class Renderer;
class ScrollView;
class ConfigService;

class ClipboardPanel : public Panel {
public:
  ClipboardPanel(ClipboardService* clipboard, ConfigService* config);
  void setActivateCallback(std::function<void(const ClipboardEntry&)> callback);

  void create() override;
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
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  void schedulePreviewPayloadRefresh(bool debounced);
  void rebuildList(Renderer& renderer, float width);
  void rebuildPreview(Renderer& renderer, float width, float height);
  void updateRowSelection(std::size_t previousIndex);
  void selectIndex(std::size_t index);
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void scrollToSelected();
  void deleteSelectedEntry();
  void applyFilter();
  void onFilterChanged(const std::string& text);
  [[nodiscard]] std::size_t selectedHistoryIndex() const;

  ClipboardService* m_clipboard = nullptr;
  std::function<void(const ClipboardEntry&)> m_activateCallback;
  ConfigService* m_config = nullptr;

  InputArea* m_focusArea = nullptr;
  Flex* m_rootLayout = nullptr;
  Flex* m_sidebar = nullptr;
  Flex* m_sidebarHeaderRow = nullptr;
  Label* m_sidebarTitle = nullptr;
  Button* m_clearHistoryButton = nullptr;
  Input* m_filterInput = nullptr;
  ScrollView* m_listScrollView = nullptr;
  Flex* m_list = nullptr;
  std::vector<Flex*> m_rowFlexes;
  std::vector<std::size_t> m_filteredIndices;
  std::string m_filterQuery;

  Flex* m_previewCard = nullptr;
  Flex* m_previewHeaderRow = nullptr;
  Label* m_previewTitle = nullptr;
  Label* m_previewMeta = nullptr;
  Button* m_copyButton = nullptr;
  Button* m_deleteEntryButton = nullptr;
  ScrollView* m_previewScrollView = nullptr;
  Flex* m_previewContent = nullptr;
  Image* m_previewImage = nullptr;

  std::size_t m_selectedIndex = 0;
  std::size_t m_previewPayloadIndex = static_cast<std::size_t>(-1);
  std::size_t m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
  std::size_t m_hoverIndex = static_cast<std::size_t>(-1);
  Timer m_previewPayloadDebounceTimer;
  Timer m_filterDebounceTimer;
  std::string m_pendingFilterQuery;
  bool m_mouseActive = false;
  std::uint64_t m_lastChangeSerial = 0;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  float m_lastListWidth = -1.0f;
  float m_lastPreviewWidth = -1.0f;
  float m_lastPreviewHeight = -1.0f;
  bool m_pendingScrollToSelected = false;
};

#pragma once

#include "ui/controls/flex.h"

#include <cstddef>
#include <functional>
#include <utility>
#include <string>
#include <string_view>
#include <vector>

class InputArea;
class Glyph;
class Label;
class Node;
class RectNode;
class Renderer;

class Select : public Flex {
public:
  Select();
  ~Select() override;

  void setOptions(std::vector<std::string> options);
  void setSelectedIndex(std::size_t index);
  void setEnabled(bool enabled);
  void setPlaceholder(std::string_view placeholder);
  void setOnSelectionChanged(std::function<void(std::size_t, std::string_view)> callback);
  static void handleGlobalPointerPress(InputArea* target);
  static void closeAnyOpen();

  [[nodiscard]] std::size_t selectedIndex() const noexcept { return m_selectedIndex; }
  [[nodiscard]] std::string_view selectedText() const noexcept;
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool open() const noexcept { return m_open; }

  void layout(Renderer& renderer) override;

private:
  struct OptionView {
    RectNode* background = nullptr;
    Label* label = nullptr;
    Glyph* checkGlyph = nullptr;
    InputArea* area = nullptr;
  };

  static constexpr std::size_t npos = static_cast<std::size_t>(-1);

  void clearOptionViews();
  void rebuildOptionViews();
  void syncTriggerText();
  void applyVisualState();
  void toggleOpen();
  void closeMenu();
  bool containsNode(const Node* node) const noexcept;
  void scrollBy(float delta);
  void clampScrollOffset();
  [[nodiscard]] float menuViewportHeight() const noexcept;
  void liftAncestorChain();
  void restoreAncestorChain();

  static Select* s_openSelect;

  RectNode* m_triggerBackground = nullptr;
  Label* m_triggerLabel = nullptr;
  Glyph* m_triggerGlyph = nullptr;
  InputArea* m_triggerArea = nullptr;
  Node* m_menuViewport = nullptr;
  RectNode* m_menuBackground = nullptr;
  InputArea* m_menuArea = nullptr;

  std::vector<OptionView> m_optionViews;
  std::vector<std::string> m_options;
  std::size_t m_selectedIndex = npos;
  std::size_t m_hoveredOptionIndex = npos;
  std::string m_placeholder = "Select an option";
  bool m_enabled = true;
  bool m_open = false;
  bool m_openUpward = false;
  float m_fixedWidth = 0.0f;
  float m_scrollOffset = 0.0f;
  std::vector<std::pair<Node*, std::int32_t>> m_liftedNodes;

  std::function<void(std::size_t, std::string_view)> m_onSelectionChanged;
};

#pragma once

#include "ui/controls/box.h"

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

class InputArea;
class Icon;
class Label;
class RectNode;
class Renderer;

class Select : public Box {
public:
  Select();

  void setOptions(std::vector<std::string> options);
  void setSelectedIndex(std::size_t index);
  void setEnabled(bool enabled);
  void setPlaceholder(std::string_view placeholder);
  void setOnSelectionChanged(std::function<void(std::size_t, std::string_view)> callback);

  [[nodiscard]] std::size_t selectedIndex() const noexcept { return m_selectedIndex; }
  [[nodiscard]] std::string_view selectedText() const noexcept;
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool open() const noexcept { return m_open; }

  void layout(Renderer& renderer) override;

private:
  struct OptionView {
    RectNode* background = nullptr;
    Label* label = nullptr;
    Icon* checkIcon = nullptr;
    InputArea* area = nullptr;
  };

  static constexpr std::size_t npos = static_cast<std::size_t>(-1);

  void clearOptionViews();
  void rebuildOptionViews();
  void syncTriggerText();
  void applyVisualState();
  void toggleOpen();
  void closeMenu();

  RectNode* m_triggerBackground = nullptr;
  Label* m_triggerLabel = nullptr;
  Icon* m_triggerIcon = nullptr;
  InputArea* m_triggerArea = nullptr;
  RectNode* m_menuBackground = nullptr;

  std::vector<OptionView> m_optionViews;
  std::vector<std::string> m_options;
  std::size_t m_selectedIndex = npos;
  std::size_t m_hoveredOptionIndex = npos;
  std::string m_placeholder = "Select an option";
  bool m_enabled = true;
  bool m_open = false;
  float m_fixedWidth = 0.0f;

  std::function<void(std::size_t, std::string_view)> m_onSelectionChanged;
};

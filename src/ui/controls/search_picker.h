#pragma once

#include "ui/controls/flex.h"

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

class Input;
class InputArea;
class Label;
class Renderer;
class ScrollView;

struct SearchPickerOption {
  std::string value;
  std::string label;
  std::string description;
  std::string category;
  bool enabled = true;
};

class SearchPicker : public Flex {
public:
  SearchPicker();

  void setOptions(std::vector<SearchPickerOption> options);
  void setPlaceholder(std::string_view placeholder);
  void setEmptyText(std::string_view text);
  void setSelectedValue(std::string_view value);
  void setOnActivated(std::function<void(const SearchPickerOption&)> callback);
  void setOnCancel(std::function<void()> callback);

  [[nodiscard]] const std::string& filter() const noexcept { return m_filter; }
  [[nodiscard]] InputArea* filterInputArea() const noexcept;

private:
  struct RowView {
    Flex* row = nullptr;
    Label* title = nullptr;
    Label* detail = nullptr;
    InputArea* area = nullptr;
  };

  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;
  void applyFilter();
  void rebuildRows();
  void setHighlightedVisibleIndex(std::size_t index);
  void moveHighlight(int delta);
  void activateHighlighted();
  void ensureHighlightedVisible();
  void applyRowStates();
  [[nodiscard]] double matchScore(const SearchPickerOption& option, std::string_view query) const;

  Input* m_input = nullptr;
  ScrollView* m_scroll = nullptr;
  std::vector<SearchPickerOption> m_options;
  std::vector<std::size_t> m_visible;
  std::vector<RowView> m_rows;
  std::string m_filter;
  std::string m_emptyText;
  std::string m_selectedValue;
  std::size_t m_highlightedVisibleIndex = 0;
  std::function<void(const SearchPickerOption&)> m_onActivated;
  std::function<void()> m_onCancel;
};

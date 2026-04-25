#include "ui/controls/search_picker.h"

#include "cursor-shape-v1-client-protocol.h"
#include "render/scene/input_area.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <linux/input-event-codes.h>
#include <memory>
#include <string>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr float kDefaultWidth = 320.0f;
  constexpr float kDefaultHeight = 360.0f;

  std::string lower(std::string_view value) {
    std::string out(value);
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
  }

  std::string detailText(const SearchPickerOption& option) {
    if (!option.description.empty() && !option.category.empty()) {
      return option.category + " - " + option.description;
    }
    if (!option.description.empty()) {
      return option.description;
    }
    return option.category;
  }

} // namespace

SearchPicker::SearchPicker() {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(Style::spaceSm);
  setPadding(Style::spaceSm);
  setFill(roleColor(ColorRole::Surface));
  setBorder(roleColor(ColorRole::Outline), Style::borderWidth);
  setRadius(Style::radiusMd);
  setSize(kDefaultWidth, kDefaultHeight);

  auto input = std::make_unique<Input>();
  input->setPlaceholder("Search...");
  input->setControlHeight(Style::controlHeight);
  input->setOnChange([this](const std::string& value) {
    m_filter = value;
    applyFilter();
  });
  input->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t /*modifiers*/) {
    if (sym == XKB_KEY_Down) {
      moveHighlight(1);
      return true;
    }
    if (sym == XKB_KEY_Up) {
      moveHighlight(-1);
      return true;
    }
    if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
      activateHighlighted();
      return true;
    }
    if (sym == XKB_KEY_Escape) {
      if (m_onCancel) {
        m_onCancel();
      }
      return true;
    }
    return false;
  });
  m_input = static_cast<Input*>(addChild(std::move(input)));

  auto scroll = std::make_unique<ScrollView>();
  scroll->setFlexGrow(1.0f);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(0.0f);
  m_scroll = static_cast<ScrollView*>(addChild(std::move(scroll)));
}

void SearchPicker::setOptions(std::vector<SearchPickerOption> options) {
  m_options = std::move(options);
  applyFilter();
}

void SearchPicker::setPlaceholder(std::string_view placeholder) {
  if (m_input != nullptr) {
    m_input->setPlaceholder(placeholder);
  }
}

void SearchPicker::setEmptyText(std::string_view text) {
  m_emptyText = std::string(text);
  rebuildRows();
}

void SearchPicker::setSelectedValue(std::string_view value) {
  m_selectedValue = std::string(value);
  applyRowStates();
}

void SearchPicker::setOnActivated(std::function<void(const SearchPickerOption&)> callback) {
  m_onActivated = std::move(callback);
}

void SearchPicker::setOnCancel(std::function<void()> callback) { m_onCancel = std::move(callback); }

void SearchPicker::doLayout(Renderer& renderer) {
  Flex::doLayout(renderer);
  for (const auto& row : m_rows) {
    if (row.row == nullptr || row.area == nullptr) {
      continue;
    }
    row.area->setPosition(0.0f, 0.0f);
    row.area->setFrameSize(row.row->width(), row.row->height());
  }
}

void SearchPicker::applyFilter() {
  m_visible.clear();
  for (std::size_t i = 0; i < m_options.size(); ++i) {
    if (matchesFilter(m_options[i])) {
      m_visible.push_back(i);
    }
  }
  m_highlightedVisibleIndex = 0;
  rebuildRows();
}

void SearchPicker::rebuildRows() {
  if (m_scroll == nullptr || m_scroll->content() == nullptr) {
    return;
  }

  auto* content = m_scroll->content();
  while (!content->children().empty()) {
    content->removeChild(content->children().back().get());
  }
  m_rows.clear();

  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceXs);

  if (m_visible.empty()) {
    auto empty = std::make_unique<Label>();
    empty->setText(m_emptyText);
    empty->setFontSize(Style::fontSizeBody);
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    content->addChild(std::move(empty));
    markLayoutDirty();
    return;
  }

  for (std::size_t visibleIndex = 0; visibleIndex < m_visible.size(); ++visibleIndex) {
    const auto sourceIndex = m_visible[visibleIndex];
    const auto& option = m_options[sourceIndex];

    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Vertical);
    row->setAlign(FlexAlign::Stretch);
    row->setGap(1.0f);
    row->setPadding(Style::spaceXs, Style::spaceSm);
    row->setRadius(Style::radiusSm);
    row->setMinHeight(46.0f);
    row->setFillParentMainAxis(true);

    auto title = std::make_unique<Label>();
    title->setText(option.label);
    title->setFontSize(Style::fontSizeBody);
    auto* titlePtr = static_cast<Label*>(row->addChild(std::move(title)));

    auto detail = std::make_unique<Label>();
    detail->setText(detailText(option));
    detail->setFontSize(Style::fontSizeCaption);
    auto* detailPtr = static_cast<Label*>(row->addChild(std::move(detail)));

    auto area = std::make_unique<InputArea>();
    area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    area->setEnabled(option.enabled);
    area->setParticipatesInLayout(false);
    area->setOnEnter(
        [this, visibleIndex](const InputArea::PointerData& /*data*/) { setHighlightedVisibleIndex(visibleIndex); });
    area->setOnClick([this, visibleIndex](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT || visibleIndex >= m_visible.size()) {
        return;
      }
      const auto activatedIndex = m_visible[visibleIndex];
      if (activatedIndex < m_options.size() && m_options[activatedIndex].enabled && m_onActivated) {
        m_onActivated(m_options[activatedIndex]);
      }
    });
    auto* areaPtr = static_cast<InputArea*>(row->addChild(std::move(area)));

    auto* rowPtr = static_cast<Flex*>(content->addChild(std::move(row)));
    m_rows.push_back(RowView{.row = rowPtr, .title = titlePtr, .detail = detailPtr, .area = areaPtr});
  }

  applyRowStates();
  markLayoutDirty();
}

void SearchPicker::setHighlightedVisibleIndex(std::size_t index) {
  if (index >= m_visible.size()) {
    return;
  }
  m_highlightedVisibleIndex = index;
  applyRowStates();
}

void SearchPicker::moveHighlight(int delta) {
  if (m_visible.empty()) {
    return;
  }
  const int count = static_cast<int>(m_visible.size());
  const int next = (static_cast<int>(m_highlightedVisibleIndex) + delta + count) % count;
  setHighlightedVisibleIndex(static_cast<std::size_t>(next));
}

void SearchPicker::activateHighlighted() {
  if (m_highlightedVisibleIndex >= m_visible.size()) {
    return;
  }
  const auto optionIndex = m_visible[m_highlightedVisibleIndex];
  if (optionIndex < m_options.size() && m_options[optionIndex].enabled && m_onActivated) {
    m_onActivated(m_options[optionIndex]);
  }
}

void SearchPicker::applyRowStates() {
  for (std::size_t i = 0; i < m_rows.size(); ++i) {
    auto& row = m_rows[i];
    if (row.row == nullptr || row.title == nullptr || row.detail == nullptr || i >= m_visible.size()) {
      continue;
    }

    const auto& option = m_options[m_visible[i]];
    const bool highlighted = i == m_highlightedVisibleIndex;
    const bool selected = option.value == m_selectedValue;
    const bool enabled = option.enabled;

    row.row->setFill(highlighted ? roleColor(ColorRole::Primary)
                                 : (selected ? roleColor(ColorRole::Primary, 0.16f) : clearThemeColor()));
    row.title->setColor(highlighted
                            ? roleColor(ColorRole::OnPrimary)
                            : (enabled ? roleColor(ColorRole::OnSurface) : roleColor(ColorRole::OnSurface, 0.55f)));
    row.detail->setColor(highlighted ? roleColor(ColorRole::OnPrimary, 0.78f)
                                     : roleColor(ColorRole::OnSurfaceVariant, enabled ? 1.0f : 0.55f));
    if (row.area != nullptr) {
      row.area->setEnabled(enabled);
    }
  }
  markPaintDirty();
}

bool SearchPicker::matchesFilter(const SearchPickerOption& option) const {
  const std::string query = lower(m_filter);
  if (query.empty()) {
    return true;
  }

  const std::string haystack =
      lower(option.label + " " + option.value + " " + option.description + " " + option.category);
  return haystack.find(query) != std::string::npos;
}

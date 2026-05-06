#include "ui/controls/search_picker.h"

#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "render/scene/input_area.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/fuzzy_match.h"
#include "util/string_utils.h"

#include <algorithm>
#include <linux/input-event-codes.h>
#include <memory>
#include <string>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr float kDefaultWidth = 320.0f;
  constexpr float kDefaultHeight = 360.0f;

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
  m_emptyText = i18n::tr("ui.controls.search-picker.empty");

  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(Style::spaceSm);
  setPadding(Style::spaceSm);
  setFill(colorSpecFromRole(ColorRole::Surface));
  setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
  setRadius(Style::radiusMd);
  setSize(kDefaultWidth, kDefaultHeight);

  auto input = std::make_unique<Input>();
  input->setPlaceholder(i18n::tr("ui.controls.search-picker.placeholder"));
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

InputArea* SearchPicker::filterInputArea() const noexcept {
  return m_input != nullptr ? m_input->inputArea() : nullptr;
}

void SearchPicker::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  if (m_input != nullptr) {
    m_input->setEnabled(enabled);
  }
  for (auto& row : m_rows) {
    if (row.area != nullptr) {
      row.area->setEnabled(enabled);
    }
  }
  setOpacity(enabled ? 1.0f : 0.55f);
}

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

LayoutSize SearchPicker::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  return measureByLayout(renderer, constraints);
}

void SearchPicker::doArrange(Renderer& renderer, const LayoutRect& rect) { arrangeByLayout(renderer, rect); }

void SearchPicker::applyFilter() {
  struct ScoredOption {
    std::size_t index = 0;
    double score = 0.0;
  };

  m_visible.clear();
  std::vector<ScoredOption> scored;
  const std::string query = StringUtils::trim(m_filter);

  for (std::size_t i = 0; i < m_options.size(); ++i) {
    if (query.empty()) {
      m_visible.push_back(i);
      continue;
    }

    const double score = matchScore(m_options[i], query);
    if (FuzzyMatch::isMatch(score)) {
      scored.push_back(ScoredOption{.index = i, .score = score});
    }
  }

  if (!query.empty()) {
    std::stable_sort(scored.begin(), scored.end(),
                     [](const ScoredOption& lhs, const ScoredOption& rhs) { return lhs.score > rhs.score; });
    m_visible.reserve(scored.size());
    for (const auto& item : scored) {
      m_visible.push_back(item.index);
    }
  }

  m_highlightedVisibleIndex = 0;
  if (m_scroll != nullptr) {
    m_scroll->setScrollOffset(0.0f);
  }
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
    empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
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
    const std::string detail = detailText(option);
    row->setGap(detail.empty() ? 0.0f : 1.0f);
    row->setPadding(Style::spaceXs, Style::spaceSm);
    row->setRadius(Style::radiusSm);
    row->setMinHeight(detail.empty() ? Style::controlHeight : Style::controlHeightLg);
    row->setFillWidth(true);

    auto title = std::make_unique<Label>();
    title->setText(option.label);
    title->setFontSize(Style::fontSizeBody);
    auto* titlePtr = static_cast<Label*>(row->addChild(std::move(title)));

    Label* detailPtr = nullptr;
    if (!detail.empty()) {
      auto detailLabel = std::make_unique<Label>();
      detailLabel->setText(detail);
      detailLabel->setFontSize(Style::fontSizeCaption);
      detailPtr = static_cast<Label*>(row->addChild(std::move(detailLabel)));
    }

    auto area = std::make_unique<InputArea>();
    area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    area->setEnabled(m_enabled && option.enabled);
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
  ensureHighlightedVisible();
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

void SearchPicker::ensureHighlightedVisible() {
  if (m_scroll == nullptr || m_highlightedVisibleIndex >= m_rows.size()) {
    return;
  }

  const auto& row = m_rows[m_highlightedVisibleIndex];
  if (row.row == nullptr || row.row->height() <= 0.0f || m_scroll->height() <= 0.0f) {
    return;
  }

  const float top = row.row->y();
  const float bottom = top + row.row->height();
  const float offset = m_scroll->scrollOffset();
  const float viewportHeight = m_scroll->height();
  if (top < offset) {
    m_scroll->setScrollOffset(top);
  } else if (bottom > offset + viewportHeight) {
    m_scroll->setScrollOffset(bottom - viewportHeight);
  }
}

void SearchPicker::applyRowStates() {
  for (std::size_t i = 0; i < m_rows.size(); ++i) {
    auto& row = m_rows[i];
    if (row.row == nullptr || row.title == nullptr || i >= m_visible.size()) {
      continue;
    }

    const auto& option = m_options[m_visible[i]];
    const bool highlighted = i == m_highlightedVisibleIndex;
    const bool selected = option.value == m_selectedValue;
    const bool enabled = option.enabled;

    row.row->setFill(highlighted ? colorSpecFromRole(ColorRole::Primary)
                                 : (selected ? colorSpecFromRole(ColorRole::Primary, 0.16f) : clearColorSpec()));
    row.title->setColor(highlighted ? colorSpecFromRole(ColorRole::OnPrimary)
                                    : (enabled ? colorSpecFromRole(ColorRole::OnSurface)
                                               : colorSpecFromRole(ColorRole::OnSurface, 0.55f)));
    if (row.detail != nullptr) {
      row.detail->setColor(highlighted ? colorSpecFromRole(ColorRole::OnPrimary, 0.78f)
                                       : colorSpecFromRole(ColorRole::OnSurfaceVariant, enabled ? 1.0f : 0.55f));
    }
    if (row.area != nullptr) {
      row.area->setEnabled(enabled);
    }
  }
  markPaintDirty();
}

double SearchPicker::matchScore(const SearchPickerOption& option, std::string_view query) const {
  const std::string haystack = option.label + " " + option.value + " " + option.description + " " + option.category;
  return FuzzyMatch::score(query, haystack);
}

#include "ui/controls/search_picker.h"

#include "i18n/i18n.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/fuzzy_match.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr float kDefaultWidth = 320.0f;
  constexpr float kDefaultHeight = 360.0f;

  class SearchPickerRow : public Flex {
  public:
    SearchPickerRow() {
      setDirection(FlexDirection::Vertical);
      setAlign(FlexAlign::Stretch);
      setPadding(Style::spaceXs, Style::spaceSm);
      setRadius(Style::scaledRadiusSm());
      setFillWidth(true);

      auto title = std::make_unique<Label>();
      title->setFontSize(Style::fontSizeBody);
      m_title = static_cast<Label*>(addChild(std::move(title)));

      auto detail = std::make_unique<Label>();
      detail->setFontSize(Style::fontSizeCaption);
      detail->setVisible(false);
      m_detail = static_cast<Label*>(addChild(std::move(detail)));
    }

    void bind(const SearchPickerOption& option, bool highlighted, bool selected, bool hovered) {
      const bool hasDetail = !option.description.empty();
      setJustify(FlexJustify::Center);
      setFill(highlighted || hovered ? colorSpecFromRole(ColorRole::Primary)
                                     : (selected ? colorSpecFromRole(ColorRole::Primary, 0.16f) : clearColorSpec()));

      if (m_title != nullptr) {
        m_title->setText(option.label);
        m_title->setBold(hasDetail);
        m_title->setColor(highlighted || hovered ? colorSpecFromRole(ColorRole::OnPrimary)
                                                 : (option.enabled ? colorSpecFromRole(ColorRole::OnSurface)
                                                                   : colorSpecFromRole(ColorRole::OnSurface, 0.55f)));
      }
      if (m_detail != nullptr) {
        m_detail->setVisible(hasDetail);
        m_detail->setParticipatesInLayout(hasDetail);
        m_detail->setText(option.description);
        m_detail->setColor(highlighted || hovered
                               ? colorSpecFromRole(ColorRole::OnPrimary, 0.78f)
                               : colorSpecFromRole(ColorRole::OnSurfaceVariant, option.enabled ? 1.0f : 0.55f));
      }
    }

  private:
    Label* m_title = nullptr;
    Label* m_detail = nullptr;
  };

} // namespace

SearchPicker::SearchPicker() {
  m_emptyText = i18n::tr("ui.controls.search-picker.empty");

  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(Style::spaceSm);
  setPadding(Style::spaceSm);
  setFill(colorSpecFromRole(ColorRole::Surface));
  setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
  setRadius(Style::scaledRadiusMd());
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

  auto empty = std::make_unique<Label>();
  empty->setText(m_emptyText);
  empty->setFontSize(Style::fontSizeBody);
  empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  empty->setVisible(false);
  m_emptyLabel = static_cast<Label*>(addChild(std::move(empty)));

  auto list = std::make_unique<VirtualListView>();
  list->setFlexGrow(1.0f);
  list->setItemGap(Style::spaceXs);
  list->setOverscanItems(4);
  list->setAdapter(this);
  m_list = static_cast<VirtualListView*>(addChild(std::move(list)));
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
  if (m_emptyLabel != nullptr) {
    m_emptyLabel->setText(m_emptyText);
  }
  markLayoutDirty();
}

void SearchPicker::setSelectedValue(std::string_view value) {
  m_selectedValue = std::string(value);
  ++m_revision;
  if (m_list != nullptr) {
    m_list->notifyDataChanged();
  }
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
  ++m_revision;
  if (m_list != nullptr) {
    m_list->notifyDataChanged();
  }
  setOpacity(enabled ? 1.0f : 0.55f);
}

void SearchPicker::doLayout(Renderer& renderer) { Flex::doLayout(renderer); }

LayoutSize SearchPicker::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  return measureByLayout(renderer, constraints);
}

void SearchPicker::doArrange(Renderer& renderer, const LayoutRect& rect) { arrangeByLayout(renderer, rect); }

std::size_t SearchPicker::itemCount() const { return m_visible.size(); }

std::uint64_t SearchPicker::itemKey(std::size_t index) const {
  if (index >= m_visible.size()) {
    return 0;
  }
  return static_cast<std::uint64_t>(m_visible[index]);
}

std::uint64_t SearchPicker::itemRevision(std::size_t index) const {
  std::uint64_t revision = m_revision;
  if (index >= m_visible.size()) {
    return revision;
  }
  const auto sourceIndex = m_visible[index];
  if (sourceIndex < m_options.size() && m_options[sourceIndex].value == m_selectedValue) {
    revision ^= (1ULL << 32);
  }
  if (index == m_highlightedVisibleIndex) {
    revision ^= (1ULL << 33);
  }
  return revision;
}

bool SearchPicker::itemInteractive(std::size_t index) const {
  if (!m_enabled || index >= m_visible.size()) {
    return false;
  }
  const auto sourceIndex = m_visible[index];
  return sourceIndex < m_options.size() && m_options[sourceIndex].enabled;
}

float SearchPicker::measureItem(Renderer& /*renderer*/, std::size_t index, float /*width*/) {
  if (index >= m_visible.size()) {
    return Style::controlHeight;
  }
  const auto sourceIndex = m_visible[index];
  const bool hasDetail = sourceIndex < m_options.size() && !m_options[sourceIndex].description.empty();
  return hasDetail ? Style::controlHeightLg : Style::controlHeight;
}

std::unique_ptr<Node> SearchPicker::createItem() { return std::make_unique<SearchPickerRow>(); }

void SearchPicker::bindItem(Renderer& /*renderer*/, Node& item, std::size_t index, float /*width*/, bool hovered) {
  auto* row = dynamic_cast<SearchPickerRow*>(&item);
  if (row == nullptr || index >= m_visible.size()) {
    return;
  }
  const auto sourceIndex = m_visible[index];
  if (sourceIndex >= m_options.size()) {
    return;
  }

  const auto& option = m_options[sourceIndex];
  const bool highlighted = index == m_highlightedVisibleIndex;
  const bool selected = option.value == m_selectedValue;
  row->bind(option, highlighted, selected, hovered);
}

void SearchPicker::onActivate(std::size_t index) {
  if (index >= m_visible.size()) {
    return;
  }
  const auto sourceIndex = m_visible[index];
  if (sourceIndex < m_options.size() && m_options[sourceIndex].enabled && m_onActivated) {
    m_onActivated(m_options[sourceIndex]);
  }
}

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
  if (query.empty() && !m_selectedValue.empty()) {
    for (std::size_t i = 0; i < m_visible.size(); ++i) {
      const auto sourceIndex = m_visible[i];
      if (sourceIndex < m_options.size() && m_options[sourceIndex].value == m_selectedValue) {
        m_highlightedVisibleIndex = i;
        break;
      }
    }
  }
  ++m_revision;
  if (m_emptyLabel != nullptr) {
    m_emptyLabel->setVisible(m_visible.empty());
  }
  if (m_list != nullptr) {
    m_list->setVisible(!m_visible.empty());
    m_list->scrollView().setScrollOffset(0.0f);
    m_list->notifyDataChanged();
    if (!m_visible.empty() && m_highlightedVisibleIndex > 0) {
      m_list->scrollToIndex(m_highlightedVisibleIndex);
    }
  }
  markLayoutDirty();
}

void SearchPicker::setHighlightedVisibleIndex(std::size_t index) {
  if (index >= m_visible.size()) {
    return;
  }
  const std::size_t previous = m_highlightedVisibleIndex;
  m_highlightedVisibleIndex = index;
  notifyHighlightedChanged(previous, m_highlightedVisibleIndex);
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
  if (m_list == nullptr || m_highlightedVisibleIndex >= m_visible.size()) {
    return;
  }
  m_list->scrollToIndex(m_highlightedVisibleIndex);
}

void SearchPicker::notifyHighlightedChanged(std::size_t previous, std::size_t next) {
  if (m_list == nullptr) {
    return;
  }
  if (previous < m_visible.size()) {
    m_list->notifyItemChanged(previous);
  }
  if (next < m_visible.size() && next != previous) {
    m_list->notifyItemChanged(next);
  }
  markPaintDirty();
}

double SearchPicker::matchScore(const SearchPickerOption& option, std::string_view query) const {
  const std::string haystack = option.label + " " + option.value + " " + option.description;
  return FuzzyMatch::score(query, haystack);
}

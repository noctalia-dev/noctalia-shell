#include "ui/controls/list_editor.h"

#include "ui/controls/button.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>
#include <utility>

namespace {

  constexpr float kLabelCellWidth = 200.0f;
  constexpr float kFreeformInputWidth = 190.0f;
  constexpr float kItemRowHeight = 26.0f;
  constexpr float kSuggestedAddHeight = 30.0f;
  constexpr float kVerticalGap = 2.0f;

  std::unique_ptr<Label> makeListLabel(std::string_view text, float scale) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(Style::fontSizeCaption * scale);
    label->setColor(colorSpecFromRole(ColorRole::OnSurface));
    return label;
  }

} // namespace

ListEditor::ListEditor() {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(kVerticalGap);
}

void ListEditor::setItems(std::vector<std::string> items) {
  m_items = std::move(items);
  rebuildRows();
}

void ListEditor::setSuggestedOptions(std::vector<ListEditorOption> options) {
  m_suggestedOptions = std::move(options);
  rebuildRows();
}

void ListEditor::setAddPlaceholder(std::string_view placeholder) {
  m_addPlaceholder = std::string(placeholder);
  rebuildRows();
}

void ListEditor::setScale(float scale) {
  m_scale = std::max(0.1f, scale);
  setGap(kVerticalGap * m_scale);
  rebuildRows();
}

void ListEditor::setMaxItems(std::size_t maxItems) {
  m_maxItems = maxItems;
  rebuildRows();
}

void ListEditor::setOnAddRequested(std::function<void(std::string)> callback) {
  m_onAddRequested = std::move(callback);
}

void ListEditor::setOnRemoveRequested(std::function<void(std::size_t)> callback) {
  m_onRemoveRequested = std::move(callback);
}

void ListEditor::setOnMoveRequested(std::function<void(std::size_t, std::size_t)> callback) {
  m_onMoveRequested = std::move(callback);
}

std::string ListEditor::labelForValue(std::string_view value) const {
  for (const auto& opt : m_suggestedOptions) {
    if (opt.value == value) {
      return opt.label;
    }
  }
  return std::string(value);
}

std::vector<ListEditorOption> ListEditor::remainingOptions() const {
  std::vector<ListEditorOption> remaining;
  remaining.reserve(m_suggestedOptions.size());
  for (const auto& opt : m_suggestedOptions) {
    if (std::find(m_items.begin(), m_items.end(), opt.value) == m_items.end()) {
      remaining.push_back(opt);
    }
  }
  return remaining;
}

void ListEditor::rebuildRows() {
  while (!children().empty()) {
    removeChild(children().back().get());
  }

  const float labelCellWidth = kLabelCellWidth * m_scale;
  const float itemRowHeight = kItemRowHeight * m_scale;
  const float suggestedAddHeight = kSuggestedAddHeight * m_scale;

  for (std::size_t i = 0; i < m_items.size(); ++i) {
    auto itemRow = std::make_unique<Flex>();
    itemRow->setDirection(FlexDirection::Horizontal);
    itemRow->setAlign(FlexAlign::Center);
    itemRow->setGap(Style::spaceXs * m_scale);
    itemRow->setMinHeight(itemRowHeight);

    auto labelCell = std::make_unique<Flex>();
    labelCell->setDirection(FlexDirection::Horizontal);
    labelCell->setAlign(FlexAlign::Center);
    labelCell->setMinWidth(labelCellWidth);
    labelCell->addChild(makeListLabel(labelForValue(m_items[i]), m_scale));
    itemRow->addChild(std::move(labelCell));

    addGhostIconButton(*itemRow, "close", Style::fontSizeCaption * m_scale, [this, i] {
      if (m_onRemoveRequested) {
        m_onRemoveRequested(i);
      }
    });

    if (i > 0) {
      addGhostIconButton(*itemRow, "chevron-up", Style::fontSizeCaption * m_scale, [this, i] {
        if (m_onMoveRequested) {
          m_onMoveRequested(i, i - 1);
        }
      });
    }
    if (i + 1 < m_items.size()) {
      addGhostIconButton(*itemRow, "chevron-down", Style::fontSizeCaption * m_scale, [this, i] {
        if (m_onMoveRequested) {
          m_onMoveRequested(i, i + 1);
        }
      });
    }

    addChild(std::move(itemRow));
  }

  if (m_maxItems > 0 && m_items.size() >= m_maxItems) {
    markLayoutDirty();
    return;
  }

  auto addRow = std::make_unique<Flex>();
  addRow->setDirection(FlexDirection::Horizontal);
  addRow->setAlign(FlexAlign::Center);
  addRow->setGap(Style::spaceSm * m_scale);

  if (!m_suggestedOptions.empty()) {
    const auto remaining = remainingOptions();
    if (remaining.empty()) {
      markLayoutDirty();
      return;
    }

    std::vector<std::string> remainingLabels;
    remainingLabels.reserve(remaining.size());
    for (const auto& opt : remaining) {
      remainingLabels.push_back(opt.label);
    }

    auto select = std::make_unique<Select>();
    select->setOptions(std::move(remainingLabels));
    select->setPlaceholder(m_addPlaceholder);
    select->setFontSize(Style::fontSizeCaption * m_scale);
    select->setControlHeight(suggestedAddHeight);
    select->setGlyphSize(Style::fontSizeCaption * m_scale);
    select->setSize(labelCellWidth, suggestedAddHeight);
    auto* selectPtr = select.get();

    auto addBtn = std::make_unique<Button>();
    addBtn->setGlyph("add");
    addBtn->setVariant(ButtonVariant::Ghost);
    addBtn->setGlyphSize(Style::fontSizeCaption * m_scale);
    addBtn->setMinWidth(suggestedAddHeight);
    addBtn->setMinHeight(suggestedAddHeight);
    addBtn->setPadding(Style::spaceXs * m_scale);
    addBtn->setRadius(Style::radiusSm * m_scale);
    addBtn->setOnClick([this, selectPtr, remaining] {
      const std::size_t index = selectPtr->selectedIndex();
      if (index < remaining.size() && m_onAddRequested) {
        m_onAddRequested(remaining[index].value);
      }
    });

    addRow->addChild(std::move(select));
    addRow->addChild(std::move(addBtn));
  } else {
    auto addInput = std::make_unique<Input>();
    addInput->setPlaceholder(m_addPlaceholder);
    addInput->setFontSize(Style::fontSizeBody * m_scale);
    addInput->setControlHeight(Style::controlHeight * m_scale);
    addInput->setHorizontalPadding(Style::spaceSm * m_scale);
    addInput->setSize(kFreeformInputWidth * m_scale, Style::controlHeight * m_scale);
    auto* addInputPtr = addInput.get();

    auto addBtn = std::make_unique<Button>();
    addBtn->setGlyph("add");
    addBtn->setVariant(ButtonVariant::Ghost);
    addBtn->setGlyphSize(Style::fontSizeBody * m_scale);
    addBtn->setMinWidth(Style::controlHeight * m_scale);
    addBtn->setMinHeight(Style::controlHeight * m_scale);
    addBtn->setPadding(Style::spaceSm * m_scale);
    addBtn->setRadius(Style::radiusMd * m_scale);
    addBtn->setOnClick([this, addInputPtr] {
      const auto& text = addInputPtr->value();
      if (!text.empty() && m_onAddRequested) {
        m_onAddRequested(text);
      }
    });

    addInput->setOnSubmit([this](const std::string& text) {
      if (!text.empty() && m_onAddRequested) {
        m_onAddRequested(text);
      }
    });

    addRow->addChild(std::move(addInput));
    addRow->addChild(std::move(addBtn));
  }

  addChild(std::move(addRow));
  markLayoutDirty();
}

void ListEditor::addGhostIconButton(Flex& row, std::string_view glyph, float size, std::function<void()> callback) {
  auto button = std::make_unique<Button>();
  button->setGlyph(glyph);
  button->setVariant(ButtonVariant::Ghost);
  button->setGlyphSize(size);
  button->setMinWidth(kItemRowHeight * m_scale);
  button->setMinHeight(kItemRowHeight * m_scale);
  button->setPadding(Style::spaceXs * m_scale);
  button->setRadius(Style::radiusSm * m_scale);
  button->setOnClick(std::move(callback));
  row.addChild(std::move(button));
}

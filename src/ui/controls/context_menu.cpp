#include "ui/controls/context_menu.h"

#include "core/ui_phase.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <linux/input-event-codes.h>

namespace {

  constexpr float kMenuPadding = 6.0f;
  constexpr float kItemHeight = Style::controlHeightSm;
  constexpr float kSeparatorHeight = 10.0f;
  constexpr float kItemGap = 0.0f;

  ThemeColor enabledItemColor() { return roleColor(ColorRole::OnSurface); }

  ThemeColor disabledItemColor() { return roleColor(ColorRole::OnSurface, 0.55f); }

} // namespace

ContextMenuControl::ContextMenuControl() : Node(NodeType::Base) {}

void ContextMenuControl::setEntries(std::vector<ContextMenuControlEntry> entries) {
  m_entries = std::move(entries);
  m_needsRebuild = true;
  markLayoutDirty();
}

void ContextMenuControl::setMaxVisible(std::size_t maxVisible) {
  m_maxVisible = std::max<std::size_t>(1, maxVisible);
  m_needsRebuild = true;
  markLayoutDirty();
}

void ContextMenuControl::setMenuWidth(float width) {
  m_menuWidth = std::max(1.0f, width);
  m_needsRebuild = true;
  markLayoutDirty();
}

void ContextMenuControl::setSubmenuDirection(ContextSubmenuDirection direction) {
  m_submenuDirection = direction;
  m_needsRebuild = true;
  markLayoutDirty();
}

void ContextMenuControl::setOnActivate(std::function<void(const ContextMenuControlEntry&)> onActivate) {
  m_onActivate = std::move(onActivate);
}

void ContextMenuControl::setOnSubmenuOpen(
    std::function<void(const ContextMenuControlEntry&, float rowCenterY)> onSubmenuOpen) {
  m_onSubmenuOpen = std::move(onSubmenuOpen);
}

void ContextMenuControl::setRedrawCallback(std::function<void()> redrawCallback) {
  m_redrawCallback = std::move(redrawCallback);
}

float ContextMenuControl::preferredHeight() const { return preferredHeight(m_entries, m_maxVisible); }

float ContextMenuControl::preferredHeight(const std::vector<ContextMenuControlEntry>& entries, std::size_t maxVisible) {
  const std::size_t visibleEntries = std::min(entries.size(), std::max<std::size_t>(1, maxVisible));
  if (visibleEntries == 0) {
    return kMenuPadding * 2.0f;
  }

  float contentHeight = 0.0f;
  for (std::size_t i = 0; i < visibleEntries; ++i) {
    contentHeight += entries[i].separator ? kSeparatorHeight : kItemHeight;
  }
  return kMenuPadding * 2.0f + contentHeight + kItemGap * static_cast<float>(visibleEntries - 1);
}

void ContextMenuControl::doLayout(Renderer& renderer) {
  if (m_needsRebuild) {
    rebuild(renderer);
  }
}

void ContextMenuControl::rebuild(Renderer& renderer) {
  uiAssertNotRendering("ContextMenuControl::rebuild");
  while (!children().empty()) {
    removeChild(children().back().get());
  }

  setSize(m_menuWidth, preferredHeight());

  auto bg = std::make_unique<Box>();
  bg->setCardStyle();
  bg->setRadius(Style::radiusLg);
  bg->setFill(fixedColor(brighten(resolveColorRole(ColorRole::Surface), 1.03f)));
  bg->setBorder(roleColor(ColorRole::Outline, 0.9f), Style::borderWidth);
  bg->setFrameSize(width(), height());
  addChild(std::move(bg));

  rebuildRows(renderer);
  m_needsRebuild = false;
}

void ContextMenuControl::rebuildRows(Renderer& renderer) {
  const std::size_t visibleItems = std::min(m_entries.size(), m_maxVisible);
  const float rowWidth = width() - kMenuPadding * 2.0f;
  float currentY = kMenuPadding;

  for (std::size_t i = 0; i < visibleItems; ++i) {
    const ContextMenuControlEntry& entry = m_entries[i];
    const bool interactive = entry.enabled && !entry.separator;
    const bool separator = entry.separator;
    const float rowHeight = separator ? kSeparatorHeight : kItemHeight;

    auto row = std::make_unique<InputArea>();
    row->setFrameSize(rowWidth, rowHeight);
    row->setPosition(kMenuPadding, currentY);
    row->setEnabled(interactive);

    Box* rowBgPtr = nullptr;
    Label* labelPtr = nullptr;
    Glyph* chevronPtr = nullptr;

    const float rowCenterY = currentY + rowHeight * 0.5f;
    row->setOnClick([this, entry, rowCenterY](const InputArea::PointerData& data) {
      if (!entry.enabled || entry.separator || data.button != BTN_LEFT) {
        return;
      }
      if (entry.hasSubmenu) {
        if (m_onSubmenuOpen) {
          m_onSubmenuOpen(entry, rowCenterY);
        }
      } else {
        if (m_onActivate) {
          m_onActivate(entry);
        }
      }
    });

    if (!entry.separator) {
      auto rowBg = std::make_unique<Box>();
      rowBg->setFill(clearThemeColor());
      rowBg->setRadius(Style::radiusSm);
      rowBg->setFrameSize(rowWidth, rowHeight);
      rowBgPtr = static_cast<Box*>(row->addChild(std::move(rowBg)));

      std::string labelText = entry.label;
      auto label = std::make_unique<Label>();
      label->setText(labelText);
      label->setFontSize(Style::fontSizeBody);
      label->setColor(entry.enabled ? enabledItemColor() : disabledItemColor());
      label->setMaxWidth(entry.hasSubmenu ? (rowWidth - 30.0f) : (rowWidth - 16.0f));
      label->measure(renderer);
      label->setPosition(8.0f, (rowHeight - label->height()) * 0.5f);
      labelPtr = static_cast<Label*>(row->addChild(std::move(label)));

      if (entry.hasSubmenu) {
        auto chevron = std::make_unique<Glyph>();
        chevron->setGlyph(m_submenuDirection == ContextSubmenuDirection::Right ? "chevron-right" : "chevron-left");
        chevron->setGlyphSize(Style::fontSizeBody - 1.0f);
        chevron->setColor(entry.enabled ? enabledItemColor() : disabledItemColor());
        chevron->measure(renderer);
        chevron->setPosition(rowWidth - 8.0f - chevron->width(), (rowHeight - chevron->height()) * 0.5f);
        chevronPtr = static_cast<Glyph*>(row->addChild(std::move(chevron)));
      }
    } else {
      auto rowBg = std::make_unique<Box>();
      rowBg->setFill(clearThemeColor());
      rowBg->setRadius(Style::radiusSm);
      rowBg->setFrameSize(rowWidth, rowHeight);
      rowBgPtr = static_cast<Box*>(row->addChild(std::move(rowBg)));

      auto label = std::make_unique<Label>();
      label->setText("");
      label->setFontSize(Style::fontSizeBody);
      label->setColor(roleColor(ColorRole::OnSurfaceVariant));
      labelPtr = static_cast<Label*>(row->addChild(std::move(label)));

      auto separatorLine = std::make_unique<Box>();
      separatorLine->setFill(roleColor(ColorRole::Outline, 0.85f));
      separatorLine->setFrameSize(rowWidth - 20.0f, 1.0f);
      separatorLine->setPosition(10.0f, (rowHeight - 1.0f) * 0.5f);
      row->addChild(std::move(separatorLine));
    }

    if (rowBgPtr != nullptr && labelPtr != nullptr) {
      const auto applyRowState = [rowBgPtr, labelPtr, chevronPtr, interactive, separator](bool highlighted) {
        rowBgPtr->setFill(highlighted ? roleColor(ColorRole::Hover) : clearThemeColor());
        if (separator) {
          labelPtr->setColor(roleColor(ColorRole::OnSurfaceVariant));
        } else {
          labelPtr->setColor(highlighted ? roleColor(ColorRole::OnHover)
                                         : (interactive ? enabledItemColor() : disabledItemColor()));
        }
        if (chevronPtr != nullptr) {
          chevronPtr->setColor(highlighted ? roleColor(ColorRole::OnHover)
                                           : (interactive ? enabledItemColor() : disabledItemColor()));
        }
      };

      row->setOnEnter([this, applyRowState](const InputArea::PointerData& /*data*/) {
        applyRowState(true);
        if (m_redrawCallback) {
          m_redrawCallback();
        }
      });
      row->setOnLeave([this, applyRowState]() {
        applyRowState(false);
        if (m_redrawCallback) {
          m_redrawCallback();
        }
      });
      row->setOnPress([this, applyRowState, interactive](const InputArea::PointerData& /*data*/) {
        if (!interactive) {
          return;
        }
        applyRowState(true);
        if (m_redrawCallback) {
          m_redrawCallback();
        }
      });
    }

    addChild(std::move(row));
    currentY += rowHeight + kItemGap;
  }
}

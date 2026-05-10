#include "i18n/i18n.h"
#include "launcher/app_provider.h"
#include "render/core/renderer.h"
#include "shell/launcher/launcher_panel.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/segmented.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>
#include <string_view>
#include <vector>

std::unique_ptr<Segmented> LauncherPanel::createCategoryTabs(float scale) {
  auto categoryTabs = std::make_unique<Segmented>();
  categoryTabs->setScale(scale);
  categoryTabs->setFontSize(Style::fontSizeCaption);
  categoryTabs->setFillWidth(true);
  categoryTabs->setEqualSegmentWidths(true);
  categoryTabs->setIconOnlyHoverLabelsEnabled(true);
  categoryTabs->setToolbarStyle(true);
  categoryTabs->setSelectOnPress(true);
  categoryTabs->setOnHoverLabelChange([this](std::optional<std::size_t> index, std::string_view label, float anchorX) {
    if (index.has_value()) {
      updateCategoryTooltip(label, anchorX);
    } else {
      hideCategoryTooltip();
    }
  });
  categoryTabs->setVisible(false);
  categoryTabs->setParticipatesInLayout(false);
  categoryTabs->setOnChange([this](std::size_t index) {
    if (!m_updatingCategoryTabs) {
      selectCategory(index);
    }
  });
  return categoryTabs;
}

std::unique_ptr<Flex> LauncherPanel::createCategoryTooltip(float scale) {
  auto tooltip = std::make_unique<Flex>();
  tooltip->setDirection(FlexDirection::Horizontal);
  tooltip->setAlign(FlexAlign::Center);
  tooltip->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
  tooltip->setRadius(Style::radiusSm * scale);
  tooltip->setFill(colorSpecFromRole(ColorRole::Surface));
  tooltip->setBorder(colorSpecFromRole(ColorRole::Outline, 0.7f), Style::borderWidth * scale);
  tooltip->setVisible(false);
  tooltip->setParticipatesInLayout(false);
  tooltip->setZIndex(3);

  auto tooltipLabel = std::make_unique<Label>();
  tooltipLabel->setCaptionStyle();
  tooltipLabel->setFontSize(Style::fontSizeCaption * scale);
  tooltipLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_categoryTooltipLabel = static_cast<Label*>(tooltip->addChild(std::move(tooltipLabel)));
  return tooltip;
}

void LauncherPanel::updateCategoryTooltip(std::string_view label, float localAnchorX) {
  if (m_categoryTooltip == nullptr || m_categoryTooltipLabel == nullptr || m_categoryTabs == nullptr) {
    return;
  }

  m_categoryTooltipLabel->setText(label);
  m_categoryTooltipAnchorX = m_categoryTabs->x() + localAnchorX;
  m_categoryTooltip->setVisible(true);
  PanelManager::instance().requestLayout();
  PanelManager::instance().requestRedraw();
}

void LauncherPanel::hideCategoryTooltip() {
  m_categoryTooltipAnchorX.reset();
  if (m_categoryTooltip != nullptr) {
    m_categoryTooltip->setVisible(false);
  }
  PanelManager::instance().requestLayout();
  PanelManager::instance().requestRedraw();
}

void LauncherPanel::layoutCategoryTooltip(Renderer& renderer) {
  if (m_categoryTooltip == nullptr || m_categoryTooltipLabel == nullptr || m_categoryTabs == nullptr ||
      !m_categoryTooltip->visible() || !m_categoryTooltipAnchorX.has_value()) {
    return;
  }

  m_categoryTooltip->layout(renderer);
  const float gap = Style::spaceXs * contentScale();
  const float x = std::clamp(std::round(*m_categoryTooltipAnchorX - m_categoryTooltip->width() * 0.5f), 0.0f,
                             std::max(0.0f, m_container->width() - m_categoryTooltip->width()));
  const float y = std::round(m_categoryTabs->y() + m_categoryTabs->height() + gap);
  m_categoryTooltip->setPosition(x, y);
}

AppProvider* LauncherPanel::appProvider() const {
  for (const auto& provider : m_providers) {
    if (auto* apps = dynamic_cast<AppProvider*>(provider.get())) {
      return apps;
    }
  }
  return nullptr;
}

void LauncherPanel::updateCategoryTabs() {
  if (m_categoryTabs == nullptr) {
    return;
  }

  AppProvider* apps = appProvider();
  const bool show = apps != nullptr && m_query.empty();
  const auto categories = apps == nullptr ? std::vector<LauncherAppCategory>{} : apps->availableCategories();
  const bool visible = show && categories.size() > 1;

  auto sameCategories = [&]() {
    if (m_categories.size() != categories.size()) {
      return false;
    }
    for (std::size_t i = 0; i < categories.size(); ++i) {
      if (m_categories[i].id != categories[i].id) {
        return false;
      }
    }
    return true;
  };

  const bool categoriesChanged = !sameCategories();
  m_updatingCategoryTabs = true;
  if (categoriesChanged) {
    m_categories = categories;
    m_categoryTabs->clearOptions();
    for (const auto& category : m_categories) {
      m_categoryTabs->addOption(i18n::tr(category.labelKey), category.glyphName);
    }
  }

  std::size_t selected = 0;
  if (apps != nullptr) {
    const auto selectedCategory = apps->selectedCategory();
    for (std::size_t i = 0; i < m_categories.size(); ++i) {
      if (m_categories[i].id == selectedCategory) {
        selected = i;
        break;
      }
    }
  }
  m_categoryTabs->setSelectedIndex(selected);
  m_categoryTabs->setVisible(visible);
  m_categoryTabs->setParticipatesInLayout(visible);
  if (!visible || categoriesChanged) {
    hideCategoryTooltip();
  }
  m_updatingCategoryTabs = false;
}

void LauncherPanel::selectCategory(std::size_t index) {
  AppProvider* apps = appProvider();
  if (apps == nullptr || index >= m_categories.size()) {
    return;
  }
  apps->selectCategory(m_categories[index].id);
  onInputChanged(m_query);
}

void LauncherPanel::cycleCategory(bool reverse) {
  if (m_categoryTabs == nullptr || !m_categoryTabs->visible() || m_categories.empty()) {
    return;
  }

  const std::size_t current = m_categoryTabs->selectedIndex();
  const std::size_t next =
      reverse ? (current == 0 ? m_categories.size() - 1 : current - 1) : (current + 1) % m_categories.size();
  selectCategory(next);
}

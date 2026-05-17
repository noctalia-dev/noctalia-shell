#include "config/config_service.h"
#include "i18n/i18n.h"
#include "launcher/launcher_category_state.h"
#include "shell/launcher/launcher_panel.h"
#include "ui/controls/segmented.h"
#include "ui/style.h"

#include <memory>

std::unique_ptr<Segmented> LauncherPanel::createCategoryTabs(float scale) {
  auto categoryTabs = std::make_unique<Segmented>();
  categoryTabs->setScale(scale);
  categoryTabs->setFontSize(Style::fontSizeCaption);
  categoryTabs->setFillWidth(true);
  categoryTabs->setEqualSegmentWidths(true);
  categoryTabs->setIconOnlyHoverLabelsEnabled(true);
  categoryTabs->setToolbarStyle(true);
  categoryTabs->setSelectOnPress(true);
  categoryTabs->setVisible(false);
  categoryTabs->setParticipatesInLayout(false);
  categoryTabs->setOnChange([this](std::size_t index) {
    if (!m_updatingCategoryTabs) {
      selectCategory(index);
    }
  });
  return categoryTabs;
}

LauncherProvider* LauncherPanel::categoryProvider() const {
  return LauncherCategoryState::singleCategoryProvider(m_providers);
}

bool LauncherPanel::categoryTabsEnabled() const noexcept {
  return m_config != nullptr && m_config->config().launcher.showCategories;
}

void LauncherPanel::updateCategoryTabs() {
  if (m_categoryTabs == nullptr) {
    return;
  }

  const auto state = LauncherCategoryState::resolveTabs(m_providers, m_query, categoryTabsEnabled());
  LauncherProvider* provider = state.provider;
  const auto& categories = state.categories;
  const bool visible = state.visible;

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
  if (provider != nullptr) {
    const auto selectedCategory = provider->selectedCategory();
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
  m_updatingCategoryTabs = false;
}

void LauncherPanel::selectCategory(std::size_t index) {
  if (!categoryTabsEnabled()) {
    return;
  }

  LauncherProvider* provider = categoryProvider();
  if (provider == nullptr || index >= m_categories.size()) {
    return;
  }
  provider->selectCategory(m_categories[index].id);
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

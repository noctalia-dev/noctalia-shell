#include "config/config_service.h"
#include "i18n/i18n.h"
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
  LauncherProvider* candidate = nullptr;
  for (const auto& provider : m_providers) {
    if (provider == nullptr || !provider->prefix().empty() || provider->availableCategories().empty()) {
      continue;
    }
    if (candidate != nullptr) {
      return nullptr;
    }
    candidate = provider.get();
  }
  return candidate;
}

bool LauncherPanel::categoryTabsEnabled() const noexcept {
  return m_config != nullptr && m_config->config().launcher.showCategories;
}

void LauncherPanel::updateCategoryTabs() {
  if (m_categoryTabs == nullptr) {
    return;
  }

  LauncherProvider* provider = nullptr;
  std::vector<LauncherCategory> categories;
  bool visible = false;

  if (categoryTabsEnabled() && m_query.empty()) {
    provider = categoryProvider();
    if (provider != nullptr) {
      categories = provider->availableCategories();
      visible = categories.size() > 1;
    }
  }

  if (!visible) {
    m_selectedCategory.clear();
  }

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
  if (!m_selectedCategory.empty()) {
    bool foundSelectedCategory = false;
    for (std::size_t i = 0; i < m_categories.size(); ++i) {
      if (m_categories[i].id == m_selectedCategory) {
        selected = i;
        foundSelectedCategory = true;
        break;
      }
    }
    if (!foundSelectedCategory) {
      m_selectedCategory.clear();
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
  if (index == 0) {
    m_selectedCategory.clear();
  } else {
    m_selectedCategory = m_categories[index].id;
  }
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

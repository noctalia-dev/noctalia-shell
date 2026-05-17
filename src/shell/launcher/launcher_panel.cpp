#include "shell/launcher/launcher_panel.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/async_texture_cache.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "shell/launcher/launcher_result_adapter.h"
#include "shell/panel/panel_manager.h"
#include "system/desktop_entry.h"
#include "ui/controls/context_menu_popup.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/controls/virtual_grid_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/fuzzy_match.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr std::size_t kMaxResults = 50;
  constexpr std::size_t kRowOverscan = 3;
  constexpr std::uint32_t kModShift = 1u << 0;
  constexpr double kUsageScorePerCount = 0.1;
  constexpr double kTypedUsageScoreCap = 0.5;

  double usageBoostForScore(double score, int usageCount, bool typedQuery) {
    if (usageCount <= 0) {
      return 0.0;
    }

    const double rawBoost = static_cast<double>(usageCount) * kUsageScorePerCount;
    if (!typedQuery) {
      return rawBoost;
    }
    if (!FuzzyMatch::isMatch(score)) {
      return 0.0;
    }

    // For typed searches, usage should nudge close matches without letting a
    // weak fuzzy hit outrank a much stronger lexical match.
    return std::min(rawBoost, kTypedUsageScoreCap);
  }

} // namespace

LauncherPanel::LauncherPanel(ConfigService* config, AsyncTextureCache* asyncTextures)
    : m_config(config), m_asyncTextures(asyncTextures) {}

LauncherPanel::~LauncherPanel() = default;

bool LauncherPanel::prefersAttachedToBar() const noexcept {
  return m_config != nullptr && m_config->config().shell.panel.attachLauncher;
}

void LauncherPanel::addProvider(std::unique_ptr<LauncherProvider> provider) {
  provider->initialize();
  m_providers.push_back(std::move(provider));
}

void LauncherPanel::create() {
  const float scale = contentScale();
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setAlign(FlexAlign::Stretch);
  container->setGap(Style::spaceSm * scale);

  auto input = std::make_unique<Input>();
  input->setPlaceholder(i18n::tr("launcher.search-placeholder"));
  input->setFontSize(Style::fontSizeBody * scale);
  input->setControlHeight(Style::controlHeight * scale);
  input->setHorizontalPadding(Style::spaceMd * scale);
  input->setClearButtonEnabled(true);
  input->setOnChange([this](const std::string& text) { onInputChanged(text); });
  input->setOnSubmit([this](const std::string& /*text*/) { activateSelected(); });
  input->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_input = input.get();
  container->addChild(std::move(input));

  auto categoryTabs = createCategoryTabs(scale);
  m_categoryTabs = static_cast<Segmented*>(container->addChild(std::move(categoryTabs)));

  auto body = std::make_unique<Flex>();
  body->setDirection(FlexDirection::Vertical);
  body->setAlign(FlexAlign::Stretch);
  body->setFlexGrow(1.0f);
  body->setFillWidth(true);
  m_body = body.get();

  m_adapter = std::make_unique<LauncherResultAdapter>(scale, m_asyncTextures);
  m_adapter->setResults(&m_results);
  m_adapter->setOnActivate([this](std::size_t index) { activateAt(index); });
  m_adapter->setOnSecondaryActivate(
      [this](std::size_t index, float ax, float ay) { openAppActionsMenu(index, ax, ay); });

  auto grid = std::make_unique<VirtualGridView>();
  grid->setColumns(1);
  grid->setSquareCells(false);
  grid->setCellHeight(launcherResultRowHeight(scale));
  grid->setColumnGap(0.0f);
  grid->setRowGap(0.0f);
  grid->setOverscanRows(kRowOverscan);
  grid->setFlexGrow(1.0f);
  grid->setFillWidth(true);
  grid->setAdapter(m_adapter.get());
  grid->setOnSelectionChanged([this](std::optional<std::size_t> idx) {
    if (idx.has_value() && *idx < m_results.size()) {
      m_selectedIndex = *idx;
    }
  });
  m_grid = static_cast<VirtualGridView*>(body->addChild(std::move(grid)));

  auto emptyLabel = std::make_unique<Label>();
  emptyLabel->setCaptionStyle();
  emptyLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  emptyLabel->setVisible(false);
  emptyLabel->setParticipatesInLayout(false);
  m_emptyLabel = static_cast<Label*>(body->addChild(std::move(emptyLabel)));

  container->addChild(std::move(body));

  m_container = container.get();
  setRoot(std::move(container));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }
}

void LauncherPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_container == nullptr || m_input == nullptr) {
    return;
  }

  if (m_adapter != nullptr) {
    m_adapter->setRenderer(&renderer);
  }

  m_container->setSize(width, height);
  m_container->layout(renderer);
}

void LauncherPanel::onOpen(std::string_view context) {
  const std::string initialValue(context);
  if (m_input != nullptr) {
    m_input->setValue(initialValue);
  }
  if (m_grid != nullptr) {
    m_grid->scrollView().setScrollOffset(0.0f);
  }
  for (auto& provider : m_providers) {
    provider->resetCategory();
  }
  // Clear cached icon misses before each open so newly installed app icons appear.
  m_iconResolver.invalidateCache();
  onInputChanged(initialValue);
}

void LauncherPanel::onClose() {
  if (m_actionsMenu != nullptr && m_actionsMenu->isOpen()) {
    m_actionsMenu->close();
  }

  if (m_asyncTextures != nullptr) {
    DeferredCall::callLater([asyncTextures = m_asyncTextures]() { asyncTextures->trimUnused(0); });
  }

  m_query.clear();
  m_results.clear();
  m_categories.clear();
  m_selectedIndex = 0;

  if (m_grid != nullptr) {
    m_grid->setAdapter(nullptr);
  }
  m_adapter.reset();

  // The scene tree (and all nodes) is destroyed by PanelManager after onClose().
  m_container = nullptr;
  m_input = nullptr;
  m_categoryTabs = nullptr;
  m_body = nullptr;
  m_grid = nullptr;
  m_emptyLabel = nullptr;
  clearReleasedRoot();
}

void LauncherPanel::onIconThemeChanged() {
  std::string selectedProvider;
  std::string selectedId;
  if (m_selectedIndex < m_results.size()) {
    selectedProvider = m_results[m_selectedIndex].providerName;
    selectedId = m_results[m_selectedIndex].id;
  }

  onInputChanged(m_query);

  if (!selectedId.empty()) {
    for (std::size_t i = 0; i < m_results.size(); ++i) {
      if (m_results[i].providerName == selectedProvider && m_results[i].id == selectedId) {
        m_selectedIndex = i;
        break;
      }
    }
  }
  refreshResults();
}

void LauncherPanel::onConfigReloaded() { onInputChanged(m_query); }

InputArea* LauncherPanel::initialFocusArea() const { return m_input != nullptr ? m_input->inputArea() : nullptr; }

void LauncherPanel::onInputChanged(const std::string& text) {
  m_query = text;
  m_results.clear();
  updateCategoryTabs();

  // Route query to providers
  LauncherProvider* activeProvider = nullptr;
  std::string_view queryText = text;

  // Check for prefix match (longest first)
  for (auto& provider : m_providers) {
    auto prefix = provider->prefix();
    if (prefix.empty()) {
      continue;
    }
    if (text.size() >= prefix.size() && std::string_view(text).substr(0, prefix.size()) == prefix) {
      activeProvider = provider.get();
      queryText = std::string_view(text).substr(prefix.size());
      // Trim leading space after prefix
      if (!queryText.empty() && queryText.front() == ' ') {
        queryText = queryText.substr(1);
      }
      break;
    }
  }

  const bool typedQuery = !queryText.empty();

  auto applyUsageBoost = [&](std::vector<LauncherResult>& results, const LauncherProvider& provider) {
    if (!provider.trackUsage()) {
      return;
    }
    for (auto& result : results) {
      const int usageCount = m_usageTracker.getCount(provider.name(), result.id);
      result.score += usageBoostForScore(result.score, usageCount, typedQuery);
    }
  };

  if (activeProvider != nullptr) {
    m_results = activeProvider->query(queryText);
    applyUsageBoost(m_results, *activeProvider);
    for (auto& result : m_results) {
      result.providerName = activeProvider->name();
    }
  } else {
    // Query default providers (empty prefix)
    for (auto& provider : m_providers) {
      if (provider->prefix().empty()) {
        auto results = provider->query(queryText);
        applyUsageBoost(results, *provider);
        for (auto& result : results) {
          result.providerName = provider->name();
        }
        m_results.insert(m_results.end(), std::make_move_iterator(results.begin()),
                         std::make_move_iterator(results.end()));
      }
    }
    // Stable sort by score descending — preserves provider order (e.g. alphabetical) for ties
    std::stable_sort(m_results.begin(), m_results.end(),
                     [](const LauncherResult& a, const LauncherResult& b) { return a.score > b.score; });
  }

  if (!text.empty() && m_results.size() > kMaxResults) {
    m_results.resize(kMaxResults);
  }

  for (auto& result : m_results) {
    if (result.iconPath.empty() && !result.iconName.empty()) {
      const std::string& resolved = m_iconResolver.resolve(result.iconName);
      if (!resolved.empty()) {
        result.iconPath = resolved;
      } else if (result.iconName != "application-x-executable") {
        const std::string& fallback = m_iconResolver.resolve("application-x-executable");
        if (!fallback.empty()) {
          result.iconPath = fallback;
        }
      }
      result.iconName.clear();
    }
  }

  m_selectedIndex = 0;
  refreshResults();
}

void LauncherPanel::refreshResults() {
  uiAssertNotRendering("LauncherPanel::refreshResults");
  if (m_grid == nullptr || m_emptyLabel == nullptr) {
    return;
  }

  m_grid->notifyDataChanged();
  if (m_results.empty()) {
    m_grid->setSelectedIndex(std::nullopt);
    m_grid->scrollView().setScrollOffset(0.0f);
  } else {
    m_grid->setSelectedIndex(m_selectedIndex);
  }
  applyEmptyState();
}

void LauncherPanel::applyEmptyState() {
  if (m_grid == nullptr || m_emptyLabel == nullptr) {
    return;
  }
  const bool empty = m_results.empty();
  m_grid->setVisible(!empty);
  m_grid->setParticipatesInLayout(!empty);
  m_emptyLabel->setVisible(empty);
  m_emptyLabel->setParticipatesInLayout(empty);
  if (empty) {
    m_emptyLabel->setText(m_query.empty() ? i18n::tr("launcher.empty.type-to-search")
                                          : i18n::tr("launcher.empty.no-results"));
  }
}

void LauncherPanel::openAppActionsMenu(std::size_t index, float anchorX, float anchorY) {
  if (index >= m_results.size()) {
    return;
  }
  const LauncherResult& base = m_results[index];

  const DesktopEntry* match = nullptr;
  for (const auto& e : desktopEntries()) {
    if (e.path == base.id) {
      match = &e;
      break;
    }
  }
  if (match == nullptr || match->actions.empty()) {
    return;
  }

  WaylandConnection* wl = PanelManager::instance().wayland();
  RenderContext* rc = PanelManager::instance().renderContext();
  if (wl == nullptr || rc == nullptr) {
    return;
  }

  const auto parentCtx = PanelManager::instance().fallbackPopupParentContext();
  if (!parentCtx.has_value()) {
    return;
  }

  if (m_actionsMenu == nullptr) {
    m_actionsMenu = std::make_unique<ContextMenuPopup>(*wl, *rc);
  }

  std::vector<DesktopAction> actionsCopy = match->actions;

  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(actionsCopy.size() + 1);
  entries.push_back(ContextMenuControlEntry{
      .id = -1,
      .label = i18n::tr("launcher.context-menu.open"),
      .enabled = true,
      .separator = false,
      .hasSubmenu = false,
  });
  for (std::int32_t i = 0; i < static_cast<std::int32_t>(actionsCopy.size()); ++i) {
    entries.push_back(ContextMenuControlEntry{
        .id = i,
        .label = actionsCopy[static_cast<std::size_t>(i)].name,
        .enabled = true,
        .separator = false,
        .hasSubmenu = false,
    });
  }

  const float scale = contentScale();
  constexpr float kMenuWidth = 240.0f;
  const float menuWidth = kMenuWidth * scale;

  if (m_config != nullptr) {
    m_actionsMenu->setShadowConfig(m_config->config().shell.shadow);
  }
  PanelManager::instance().beginAttachedPopup(parentCtx->surface);
  PanelManager::instance().setActivePopup(m_actionsMenu.get());

  m_actionsMenu->setOnDismissed([parentSurface = parentCtx->surface]() {
    PanelManager::instance().clearActivePopup();
    PanelManager::instance().endAttachedPopup(parentSurface);
  });

  m_actionsMenu->setOnActivate(
      [this, base, actionsCopy = std::move(actionsCopy)](const ContextMenuControlEntry& entry) {
        LauncherResult result = base;
        result.desktopActionId.clear();
        if (entry.id >= 0 && entry.id < static_cast<std::int32_t>(actionsCopy.size())) {
          result.desktopActionId = actionsCopy[static_cast<std::size_t>(entry.id)].id;
        } else if (entry.id != -1) {
          return;
        }

        for (auto& provider : m_providers) {
          if (provider->name() != std::string_view(result.providerName)) {
            continue;
          }
          if (!provider->activate(result)) {
            return;
          }
          if (provider->trackUsage()) {
            m_usageTracker.record(provider->name(), result.id);
          }
          PanelManager::instance().closePanel();
          return;
        }
      });

  const float inset = std::round(std::max(4.0f, Style::spaceXs * scale));
  const std::int32_t ax = static_cast<std::int32_t>(std::round(anchorX - inset));
  const std::int32_t ay = static_cast<std::int32_t>(std::round(anchorY - inset));
  const std::int32_t aw = static_cast<std::int32_t>(std::round(inset * 2.0f));
  const std::int32_t ah = static_cast<std::int32_t>(std::round(inset * 2.0f));

  m_actionsMenu->open(std::move(entries), menuWidth, 12, ax, ay, std::max(1, aw), std::max(1, ah),
                      parentCtx->layerSurface, parentCtx->output);
}

void LauncherPanel::activateAt(std::size_t index) {
  if (index >= m_results.size()) {
    return;
  }
  m_selectedIndex = index;
  activateSelected();
}

void LauncherPanel::activateSelected() {
  if (m_selectedIndex >= m_results.size()) {
    return;
  }

  const auto& result = m_results[m_selectedIndex];

  // Dispatch only to the provider that produced this result. Providers can use
  // overlapping id shapes, so probing every provider risks side effects.
  for (auto& provider : m_providers) {
    if (provider->name() != std::string_view(result.providerName)) {
      continue;
    }

    if (!provider->activate(result)) {
      return;
    }

    if (provider->trackUsage()) {
      m_usageTracker.record(provider->name(), result.id);
    }
    PanelManager::instance().closePanel();
    return;
  }
}

bool LauncherPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (sym == XKB_KEY_Tab && m_categoryTabs != nullptr && m_categoryTabs->visible()) {
    cycleCategory((modifiers & kModShift) != 0);
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    if (m_selectedIndex > 0) {
      --m_selectedIndex;
      if (m_grid != nullptr) {
        m_grid->setSelectedIndex(m_selectedIndex);
      }
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    if (!m_results.empty() && m_selectedIndex < m_results.size() - 1) {
      ++m_selectedIndex;
      if (m_grid != nullptr) {
        m_grid->setSelectedIndex(m_selectedIndex);
      }
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) {
    activateSelected();
    return true;
  }

  return false;
}

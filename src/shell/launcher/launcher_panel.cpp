#include "shell/launcher/launcher_panel.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/async_texture_cache.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/virtual_grid_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/fuzzy_match.h"

#include <algorithm>
#include <cmath>
#include <functional>
#include <memory>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr std::size_t kMaxResults = 50;
  constexpr std::size_t kRowOverscan = 3;
  constexpr float kIconSize = 32.0f;
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

  float launcherRowHeight(float scale) {
    const float paddingY = Style::spaceXs * scale;
    const float textGap = Style::spaceXs * scale;
    const float titleHeight = Style::fontSizeBody * scale * 1.35f;
    const float subtitleHeight = Style::fontSizeCaption * scale * 1.25f;
    const float textHeight = titleHeight + textGap + subtitleHeight;
    return std::ceil(std::max(kIconSize * scale, textHeight) + paddingY * 2.0f);
  }

  class LauncherResultRow final : public Node {
  public:
    LauncherResultRow(float scale, AsyncTextureCache* asyncTextures)
        : m_scale(scale), m_rowHeight(launcherRowHeight(scale)), m_asyncTextures(asyncTextures) {
      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Center);
      row->setGap(Style::spaceMd * scale);
      row->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      row->setRadius(Style::radiusMd * scale);
      m_row = static_cast<Flex*>(addChild(std::move(row)));

      auto actionLabel = std::make_unique<Label>();
      actionLabel->setFontSize(kIconSize * scale);
      actionLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
      actionLabel->setVisible(false);
      m_actionLabel = static_cast<Label*>(m_row->addChild(std::move(actionLabel)));

      auto image = std::make_unique<Image>();
      image->setSize(kIconSize * scale, kIconSize * scale);
      image->setVisible(false);
      m_image = static_cast<Image*>(m_row->addChild(std::move(image)));

      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyphSize(kIconSize * scale);
      glyph->setColor(colorSpecFromRole(ColorRole::OnSurface));
      glyph->setVisible(false);
      m_glyph = static_cast<Glyph*>(m_row->addChild(std::move(glyph)));

      m_image->setAsyncReadyCallback([this]() {
        if (m_actionTextVisible || m_iconPath.empty() || m_image == nullptr || m_glyph == nullptr ||
            !m_image->hasImage()) {
          return;
        }
        m_image->setVisible(true);
        m_glyph->setVisible(false);
      });

      auto textCol = std::make_unique<Flex>();
      textCol->setDirection(FlexDirection::Vertical);
      textCol->setAlign(FlexAlign::Start);
      textCol->setGap(Style::spaceXs * 0.5f * scale);
      textCol->setFlexGrow(1.0f);
      m_textCol = static_cast<Flex*>(m_row->addChild(std::move(textCol)));

      auto title = std::make_unique<Label>();
      title->setFontSize(Style::fontSizeBody * scale);
      title->setBold(true);
      title->setColor(colorSpecFromRole(ColorRole::OnSurface));
      title->setMaxLines(1);
      title->setStableBaseline(true);
      m_title = static_cast<Label*>(m_textCol->addChild(std::move(title)));

      auto subtitle = std::make_unique<Label>();
      subtitle->setCaptionStyle();
      subtitle->setFontSize(Style::fontSizeCaption * scale);
      subtitle->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      subtitle->setMaxLines(1);
      subtitle->setStableBaseline(true);
      m_subtitle = static_cast<Label*>(m_textCol->addChild(std::move(subtitle)));
    }

    void bind(Renderer& renderer, const LauncherResult& result, float width, bool selected, bool hovered) {
      m_selected = selected;
      m_hovered = hovered;
      m_iconPath = result.iconPath;
      m_fallbackGlyph = result.glyphName.empty() ? "app-window" : result.glyphName;
      m_iconTargetSize = static_cast<int>(std::round(kIconSize * m_scale));
      m_actionTextVisible = !result.actionText.empty();

      setSize(width, m_rowHeight);
      m_row->setFrameSize(width, m_rowHeight);

      m_actionLabel->setVisible(false);
      m_image->setVisible(false);
      m_glyph->setVisible(false);

      if (m_actionTextVisible) {
        m_actionLabel->setText(result.actionText);
        m_actionLabel->setSize(kIconSize * m_scale, kIconSize * m_scale);
        m_actionLabel->setVisible(true);
        m_image->clear(renderer);
      } else if (!m_iconPath.empty()) {
        const bool ready = refreshAsyncIcon(renderer);
        m_image->setVisible(ready);
        m_glyph->setGlyph(m_fallbackGlyph);
        m_glyph->setVisible(!ready);
      } else {
        m_image->clear(renderer);
        m_glyph->setGlyph(m_fallbackGlyph);
        m_glyph->setVisible(true);
      }

      const float textWidth =
          std::max(0.0f, width - kIconSize * m_scale - Style::spaceSm * m_scale * 2.0f - Style::spaceMd * m_scale);
      m_title->setText(result.title);
      m_title->setMaxWidth(textWidth);

      if (result.subtitle.empty()) {
        m_subtitle->setVisible(false);
        m_subtitle->setText("");
      } else {
        m_subtitle->setVisible(true);
        m_subtitle->setText(result.subtitle);
        m_subtitle->setMaxWidth(textWidth);
      }

      applyVisualState();
    }

    bool refreshAsyncIcon(Renderer& renderer) {
      if (m_actionTextVisible || m_iconPath.empty()) {
        return false;
      }

      bool ready = false;
      if (m_asyncTextures != nullptr) {
        ready = m_image->setSourceFileAsync(renderer, *m_asyncTextures, m_iconPath, m_iconTargetSize, true);
      } else {
        ready = m_image->setSourceFile(renderer, m_iconPath, m_iconTargetSize, true);
      }

      m_image->setSize(kIconSize * m_scale, kIconSize * m_scale);
      m_image->setVisible(ready);
      m_glyph->setGlyph(m_fallbackGlyph);
      m_glyph->setVisible(!ready);
      return ready;
    }

  protected:
    void doLayout(Renderer& renderer) override {
      if (!m_actionTextVisible && !m_iconPath.empty()) {
        (void)refreshAsyncIcon(renderer);
      }
      Node::doLayout(renderer);
    }

  private:
    void applyVisualState() {
      if (m_selected) {
        m_row->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
      } else if (m_hovered) {
        m_row->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.45f));
      } else {
        m_row->setFill(rgba(0, 0, 0, 0));
      }
    }

    float m_scale = 1.0f;
    float m_rowHeight = 0.0f;
    bool m_selected = false;
    bool m_hovered = false;
    Flex* m_row = nullptr;
    Label* m_actionLabel = nullptr;
    Image* m_image = nullptr;
    Glyph* m_glyph = nullptr;
    Flex* m_textCol = nullptr;
    Label* m_title = nullptr;
    Label* m_subtitle = nullptr;
    AsyncTextureCache* m_asyncTextures = nullptr;
    std::string m_iconPath;
    std::string m_fallbackGlyph;
    int m_iconTargetSize = 0;
    bool m_actionTextVisible = false;
  };

} // namespace

class LauncherResultAdapter final : public VirtualGridAdapter {
public:
  using ActivateCallback = std::function<void(std::size_t)>;

  LauncherResultAdapter(float scale, AsyncTextureCache* cache) : m_scale(scale), m_cache(cache) {}

  void setResults(const std::vector<LauncherResult>* results) { m_results = results; }
  void setRenderer(Renderer* renderer) { m_renderer = renderer; }
  void setOnActivate(ActivateCallback callback) { m_onActivate = std::move(callback); }

  [[nodiscard]] std::size_t itemCount() const override { return m_results == nullptr ? 0u : m_results->size(); }

  [[nodiscard]] std::unique_ptr<Node> createTile() override {
    return std::make_unique<LauncherResultRow>(m_scale, m_cache);
  }

  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override {
    if (m_renderer == nullptr || m_results == nullptr || index >= m_results->size()) {
      return;
    }
    auto* row = static_cast<LauncherResultRow*>(&tile);
    row->bind(*m_renderer, (*m_results)[index], tile.width(), selected, hovered);
  }

  void onActivate(std::size_t index) override {
    if (m_onActivate) {
      m_onActivate(index);
    }
  }

private:
  float m_scale;
  AsyncTextureCache* m_cache = nullptr;
  Renderer* m_renderer = nullptr;
  const std::vector<LauncherResult>* m_results = nullptr;
  ActivateCallback m_onActivate;
};

LauncherPanel::LauncherPanel(ConfigService* config, AsyncTextureCache* asyncTextures)
    : m_config(config), m_asyncTextures(asyncTextures) {}

LauncherPanel::~LauncherPanel() = default;

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

  auto body = std::make_unique<Flex>();
  body->setDirection(FlexDirection::Vertical);
  body->setAlign(FlexAlign::Stretch);
  body->setFlexGrow(1.0f);
  body->setFillWidth(true);
  m_body = body.get();

  m_adapter = std::make_unique<LauncherResultAdapter>(scale, m_asyncTextures);
  m_adapter->setResults(&m_results);
  m_adapter->setOnActivate([this](std::size_t index) { activateAt(index); });

  auto grid = std::make_unique<VirtualGridView>();
  grid->setColumns(1);
  grid->setSquareCells(false);
  grid->setCellHeight(launcherRowHeight(scale));
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
  onInputChanged(initialValue);
}

void LauncherPanel::onClose() {
  if (m_asyncTextures != nullptr) {
    DeferredCall::callLater([asyncTextures = m_asyncTextures]() { asyncTextures->trimUnused(0); });
  }

  m_query.clear();
  m_results.clear();
  m_selectedIndex = 0;

  if (m_grid != nullptr) {
    m_grid->setAdapter(nullptr);
  }
  m_adapter.reset();

  // The scene tree (and all nodes) is destroyed by PanelManager after onClose().
  m_container = nullptr;
  m_input = nullptr;
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

InputArea* LauncherPanel::initialFocusArea() const { return m_input != nullptr ? m_input->inputArea() : nullptr; }

void LauncherPanel::onInputChanged(const std::string& text) {
  m_query = text;
  m_results.clear();

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

#include "shell/launcher/launcher_panel.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/ui_phase.h"
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
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/clipboard_service.h"

#include <algorithm>
#include <cmath>
#include <functional>
#include <memory>
#include <optional>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr std::size_t kMaxResults = 50;
  constexpr std::size_t kRowOverscan = 3;
  constexpr float kIconSize = 32.0f;
  constexpr float kScrollViewPaddingV = Style::spaceSm;

  float launcherRowHeight(float scale) {
    const float paddingY = Style::spaceXs * scale;
    const float textGap = Style::spaceXs * scale;
    const float titleHeight = Style::fontSizeBody * scale * 1.35f;
    const float subtitleHeight = Style::fontSizeCaption * scale * 1.25f;
    const float textHeight = titleHeight + textGap + subtitleHeight;
    return std::ceil(std::max(kIconSize * scale, textHeight) + paddingY * 2.0f);
  }

  std::size_t rowPoolCount(float viewportHeight, float rowHeight) {
    const float safeHeight = std::max(rowHeight, 1.0f);
    return std::max<std::size_t>(1,
                                 static_cast<std::size_t>(std::ceil(viewportHeight / safeHeight)) + kRowOverscan * 2);
  }

  class LauncherResultRow final : public InputArea {
  public:
    using IndexCallback = std::function<void(std::size_t)>;

    LauncherResultRow(float scale, AsyncTextureCache* asyncTextures)
        : m_scale(scale), m_rowHeight(launcherRowHeight(scale)), m_asyncTextures(asyncTextures) {
      setPropagateEvents(true);
      setOnClick([this](const InputArea::PointerData&) {
        if (m_boundIndex != static_cast<std::size_t>(-1) && m_onClick) {
          m_onClick(m_boundIndex);
        }
      });
      setOnMotion([this](const InputArea::PointerData&) {
        if (m_boundIndex != static_cast<std::size_t>(-1) && m_onMotion) {
          m_onMotion(m_boundIndex);
        }
      });
      setOnEnter([this](const InputArea::PointerData&) {
        if (m_boundIndex != static_cast<std::size_t>(-1) && m_onEnter) {
          m_onEnter(m_boundIndex);
        }
      });
      setOnLeave([this]() {
        if (m_boundIndex != static_cast<std::size_t>(-1) && m_onLeave) {
          m_onLeave(m_boundIndex);
        }
      });

      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Center);
      row->setGap(Style::spaceMd * scale);
      row->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      row->setRadius(Style::radiusMd * scale);
      m_row = static_cast<Flex*>(addChild(std::move(row)));

      auto actionLabel = std::make_unique<Label>();
      actionLabel->setFontSize(kIconSize * scale);
      actionLabel->setColor(roleColor(ColorRole::OnSurface));
      actionLabel->setVisible(false);
      m_actionLabel = static_cast<Label*>(m_row->addChild(std::move(actionLabel)));

      auto image = std::make_unique<Image>();
      image->setSize(kIconSize * scale, kIconSize * scale);
      image->setVisible(false);
      m_image = static_cast<Image*>(m_row->addChild(std::move(image)));

      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyphSize(kIconSize * scale);
      glyph->setColor(roleColor(ColorRole::OnSurface));
      glyph->setVisible(false);
      m_glyph = static_cast<Glyph*>(m_row->addChild(std::move(glyph)));

      auto textCol = std::make_unique<Flex>();
      textCol->setDirection(FlexDirection::Vertical);
      textCol->setAlign(FlexAlign::Start);
      textCol->setGap(Style::spaceXs * scale);
      textCol->setFlexGrow(1.0f);
      m_textCol = static_cast<Flex*>(m_row->addChild(std::move(textCol)));

      auto title = std::make_unique<Label>();
      title->setFontSize(Style::fontSizeBody * scale);
      title->setBold(true);
      title->setColor(roleColor(ColorRole::OnSurface));
      m_title = static_cast<Label*>(m_textCol->addChild(std::move(title)));

      auto subtitle = std::make_unique<Label>();
      subtitle->setCaptionStyle();
      subtitle->setFontSize(Style::fontSizeCaption * scale);
      subtitle->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_subtitle = static_cast<Label*>(m_textCol->addChild(std::move(subtitle)));

      setVisible(false);
    }

    [[nodiscard]] std::size_t boundIndex() const noexcept { return m_boundIndex; }

    void setCallbacks(IndexCallback onClick, IndexCallback onMotion, IndexCallback onEnter, IndexCallback onLeave) {
      m_onClick = std::move(onClick);
      m_onMotion = std::move(onMotion);
      m_onEnter = std::move(onEnter);
      m_onLeave = std::move(onLeave);
    }

    void bind(Renderer& renderer, const LauncherResult& result, std::size_t index, float width, bool selected,
              bool hovered) {
      m_boundIndex = index;
      m_selected = selected;
      m_hovered = hovered;
      m_iconPath = result.iconPath;
      m_fallbackGlyph = result.glyphName.empty() ? "app-window" : result.glyphName;
      m_iconTargetSize = static_cast<int>(std::round(kIconSize * m_scale));
      m_actionTextVisible = !result.actionText.empty();

      setVisible(true);
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
      layout(renderer);
    }

    bool refreshAsyncIcon(Renderer& renderer) {
      if (m_actionTextVisible || m_iconPath.empty()) {
        return false;
      }

      bool ready = false;
      if (m_asyncTextures != nullptr) {
        ready = m_image->setSourceFileAsync(renderer, *m_asyncTextures, m_iconPath, m_iconTargetSize);
      } else {
        ready = m_image->setSourceFile(renderer, m_iconPath, m_iconTargetSize);
      }

      m_image->setSize(kIconSize * m_scale, kIconSize * m_scale);
      m_image->setVisible(ready);
      m_glyph->setGlyph(m_fallbackGlyph);
      m_glyph->setVisible(!ready);
      return ready;
    }

    void clear(Renderer& renderer) {
      m_boundIndex = static_cast<std::size_t>(-1);
      m_selected = false;
      m_hovered = false;
      m_actionTextVisible = false;
      m_iconPath.clear();
      m_fallbackGlyph = "app-window";
      m_iconTargetSize = 0;
      m_image->clear(renderer);
      m_actionLabel->setVisible(false);
      m_image->setVisible(false);
      m_glyph->setVisible(false);
      setVisible(false);
    }

    void setVisualState(bool selected, bool hovered) {
      if (m_selected == selected && m_hovered == hovered) {
        return;
      }
      m_selected = selected;
      m_hovered = hovered;
      applyVisualState();
    }

  protected:
    void doLayout(Renderer& renderer) override {
      if (!m_actionTextVisible && !m_iconPath.empty()) {
        (void)refreshAsyncIcon(renderer);
      }
      InputArea::doLayout(renderer);
    }

  private:
    void applyVisualState() {
      if (m_selected) {
        m_row->setFill(roleColor(ColorRole::SurfaceVariant));
      } else if (m_hovered) {
        m_row->setFill(roleColor(ColorRole::SurfaceVariant, 0.45f));
      } else {
        m_row->setFill(rgba(0, 0, 0, 0));
      }
    }

    float m_scale = 1.0f;
    float m_rowHeight = 0.0f;
    std::size_t m_boundIndex = static_cast<std::size_t>(-1);
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
    IndexCallback m_onClick;
    IndexCallback m_onMotion;
    IndexCallback m_onEnter;
    IndexCallback m_onLeave;
  };

} // namespace

LauncherPanel::LauncherPanel(ConfigService* config, AsyncTextureCache* asyncTextures)
    : m_config(config), m_asyncTextures(asyncTextures) {}

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
  input->setPlaceholder("Search applications...");
  input->setFontSize(Style::fontSizeBody * scale);
  input->setControlHeight(Style::controlHeight * scale);
  input->setHorizontalPadding(Style::spaceMd * scale);
  input->setOnChange([this](const std::string& text) { onInputChanged(text); });
  input->setOnSubmit([this](const std::string& /*text*/) { activateSelected(); });
  input->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_input = input.get();

  container->addChild(std::move(input));

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setScrollbarVisible(true);
  scrollView->setFlexGrow(1.0f);
  scrollView->setOnScrollChanged([this](float offset) {
    if (m_virtualRowHeight <= 0.0f || m_results.empty()) {
      return;
    }
    const auto topIndex = static_cast<std::size_t>(std::floor(offset / m_virtualRowHeight));
    const auto startIndex = topIndex > kRowOverscan ? topIndex - kRowOverscan : 0;
    if (startIndex != m_rowPoolStartIndex) {
      m_dirty = true;
      PanelManager::instance().requestLayout();
    }
  });
  m_scrollView = scrollView.get();
  m_list = scrollView->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  auto resultsRoot = std::make_unique<Node>();
  m_resultsRoot = static_cast<Node*>(m_list->addChild(std::move(resultsRoot)));
  auto emptyLabel = std::make_unique<Label>();
  emptyLabel->setCaptionStyle();
  emptyLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  emptyLabel->setVisible(false);
  m_emptyLabel = static_cast<Label*>(m_resultsRoot->addChild(std::move(emptyLabel)));
  container->addChild(std::move(scrollView));

  m_container = container.get();
  setRoot(std::move(container));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }
}

void LauncherPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_container == nullptr || m_input == nullptr || m_scrollView == nullptr) {
    return;
  }

  m_container->setSize(width, height);
  m_container->layout(renderer);

  bool relayoutNeeded = false;
  if (m_dirty || m_lastListWidth != m_scrollView->contentViewportWidth()) {
    rebuildResults(renderer, m_scrollView->contentViewportWidth());
    m_dirty = false;
    relayoutNeeded = true;
  }

  if (relayoutNeeded) {
    m_container->layout(renderer);
    // Rebuilding may have shown/hidden the scrollbar, which changes the
    // viewport width. Re-measure and rebuild once more so every row lands at
    // the final width — otherwise the first-frame selection background can
    // overshoot.
    if (m_lastListWidth != m_scrollView->contentViewportWidth()) {
      rebuildResults(renderer, m_scrollView->contentViewportWidth());
      m_container->layout(renderer);
    }
  }

  if (m_pendingScrollToSelected) {
    scrollToSelected();
    m_pendingScrollToSelected = false;
  }

  m_lastWidth = width;
}

void LauncherPanel::doUpdate(Renderer& renderer) {
  if (m_dirty && m_lastWidth > 0.0f) {
    const float listWidth = m_scrollView != nullptr ? m_scrollView->contentViewportWidth() : m_lastWidth;
    rebuildResults(renderer, listWidth);
    m_dirty = false;
  }
}

void LauncherPanel::onOpen(std::string_view context) {
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
  m_pendingScrollToSelected = false;
  m_lastListWidth = -1.0f;
  const std::string initialValue(context);
  if (m_input != nullptr) {
    m_input->setValue(initialValue);
  }
  if (m_scrollView != nullptr) {
    m_scrollView->setScrollOffset(0.0f);
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
  m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  m_lastWidth = 0.0f;
  m_lastListWidth = -1.0f;
  m_virtualRowHeight = 0.0f;
  m_dirty = false;
  m_pendingScrollToSelected = false;

  // The scene tree (and all nodes) is destroyed by PanelManager after onClose(),
  // so null out all raw pointers to avoid dangling references on re-open.
  m_container = nullptr;
  m_input = nullptr;
  m_scrollView = nullptr;
  m_list = nullptr;
  m_resultsRoot = nullptr;
  m_emptyLabel = nullptr;
  m_rowPool.clear();
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
  m_pendingScrollToSelected = true;
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

  constexpr int kUsageScorePerCount = 20;

  auto applyUsageBoost = [&](std::vector<LauncherResult>& results, const LauncherProvider& provider) {
    if (!provider.trackUsage()) {
      return;
    }
    for (auto& result : results) {
      result.score += m_usageTracker.getCount(provider.name(), result.id) * kUsageScorePerCount;
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
  m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  m_dirty = true;
}

void LauncherPanel::rebuildResults(Renderer& renderer, float width) {
  uiAssertNotRendering("LauncherPanel::rebuildResults");
  if (m_list == nullptr || m_resultsRoot == nullptr || m_emptyLabel == nullptr || m_scrollView == nullptr) {
    return;
  }

  const float viewportHeight = std::max(0.0f, m_scrollView->height() - kScrollViewPaddingV * 2.0f);
  m_virtualRowHeight = launcherRowHeight(contentScale());
  ensureRowPool(viewportHeight);

  if (m_results.empty()) {
    m_emptyLabel->setVisible(true);
    m_emptyLabel->setText(m_query.empty() ? "Type to search..." : "No results found");
    m_emptyLabel->setMaxWidth(width);
    m_emptyLabel->measure(renderer);
    m_emptyLabel->setPosition(0.0f, 0.0f);
    m_resultsRoot->setSize(width, m_emptyLabel->height());
    for (auto* rowArea : m_rowPool) {
      static_cast<LauncherResultRow*>(rowArea)->clear(renderer);
    }
    m_rowPoolStartIndex = static_cast<std::size_t>(-1);
    m_lastListWidth = width;
    return;
  }

  m_emptyLabel->setVisible(false);
  m_resultsRoot->setSize(width, m_virtualRowHeight * static_cast<float>(m_results.size()));

  const auto topIndex = std::min(
      static_cast<std::size_t>(std::floor(m_scrollView->scrollOffset() / m_virtualRowHeight)), m_results.size() - 1);
  const auto startIndex = topIndex > kRowOverscan ? topIndex - kRowOverscan : 0;
  m_rowPoolStartIndex = startIndex;

  for (std::size_t slot = 0; slot < m_rowPool.size(); ++slot) {
    auto* row = static_cast<LauncherResultRow*>(m_rowPool[slot]);
    const std::size_t resultIndex = startIndex + slot;
    if (resultIndex < m_results.size()) {
      row->setPosition(0.0f, static_cast<float>(resultIndex) * m_virtualRowHeight);
      row->bind(renderer, m_results[resultIndex], resultIndex, width, resultIndex == m_selectedIndex,
                m_mouseActive && resultIndex == m_hoverIndex && resultIndex != m_selectedIndex);
    } else {
      row->clear(renderer);
    }
  }

  m_lastListWidth = width;
}

void LauncherPanel::ensureRowPool(float viewportHeight) {
  if (m_resultsRoot == nullptr) {
    return;
  }

  const std::size_t desiredPoolSize = rowPoolCount(viewportHeight, m_virtualRowHeight);
  if (m_rowPool.size() == desiredPoolSize) {
    return;
  }

  for (auto* rowArea : m_rowPool) {
    m_resultsRoot->removeChild(rowArea);
  }
  m_rowPool.clear();

  const float scale = contentScale();
  for (std::size_t i = 0; i < desiredPoolSize; ++i) {
    auto row = std::make_unique<LauncherResultRow>(scale, m_asyncTextures);
    row->setCallbacks(
        [this](std::size_t index) {
          m_selectedIndex = index;
          activateSelected();
        },
        [this](std::size_t index) {
          if (!m_mouseActive) {
            m_mouseActive = true;
          }
          if (index != m_selectedIndex && m_hoverIndex != index) {
            m_hoverIndex = index;
            updateVisibleRowStates();
            PanelManager::instance().requestRedraw();
          }
        },
        [this](std::size_t index) {
          if (!m_mouseActive || index == m_selectedIndex || m_hoverIndex == index) {
            return;
          }
          m_hoverIndex = index;
          updateVisibleRowStates();
          PanelManager::instance().requestRedraw();
        },
        [this](std::size_t index) {
          if (m_hoverIndex != index || index == m_selectedIndex) {
            return;
          }
          m_hoverIndex = static_cast<std::size_t>(-1);
          updateVisibleRowStates();
          PanelManager::instance().requestRedraw();
        });
    auto* rowPtr = static_cast<LauncherResultRow*>(m_resultsRoot->addChild(std::move(row)));
    m_rowPool.push_back(rowPtr);
  }
}

void LauncherPanel::updateVisibleRowStates() {
  for (auto* rowArea : m_rowPool) {
    auto* row = static_cast<LauncherResultRow*>(rowArea);
    const std::size_t index = row->boundIndex();
    if (index == static_cast<std::size_t>(-1)) {
      continue;
    }
    row->setVisualState(index == m_selectedIndex, m_mouseActive && index == m_hoverIndex && index != m_selectedIndex);
  }
}

void LauncherPanel::activateSelected() {
  if (m_selectedIndex >= m_results.size()) {
    return;
  }

  const auto& result = m_results[m_selectedIndex];

  // Find the provider that owns this result
  for (auto& provider : m_providers) {
    if (provider->activate(result)) {
      if (provider->trackUsage()) {
        m_usageTracker.record(provider->name(), result.id);
      }
      PanelManager::instance().closePanel();
      return;
    }
  }
}

bool LauncherPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    if (m_selectedIndex > 0) {
      --m_selectedIndex;
      m_dirty = true;
      m_pendingScrollToSelected = true;
      if (root() != nullptr) {
        root()->markLayoutDirty();
      }
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    if (!m_results.empty() && m_selectedIndex < m_results.size() - 1) {
      ++m_selectedIndex;
      m_dirty = true;
      m_pendingScrollToSelected = true;
      if (root() != nullptr) {
        root()->markLayoutDirty();
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

void LauncherPanel::scrollToSelected() {
  if (m_scrollView == nullptr || m_virtualRowHeight <= 0.0f || m_selectedIndex >= m_results.size()) {
    return;
  }

  const float itemTop = static_cast<float>(m_selectedIndex) * m_virtualRowHeight;
  const float itemBottom = itemTop + m_virtualRowHeight;
  const float viewportH = m_scrollView->height() - kScrollViewPaddingV * 2.0f;
  const float scrollOffset = m_scrollView->scrollOffset();

  if (itemTop < scrollOffset) {
    m_scrollView->setScrollOffset(itemTop);
  } else if (itemBottom > scrollOffset + viewportH) {
    m_scrollView->setScrollOffset(itemBottom - viewportH);
  }
}

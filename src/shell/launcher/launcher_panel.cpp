#include "shell/launcher/launcher_panel.h"

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

#include <algorithm>
#include <memory>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

constexpr std::size_t kMaxResults = 50;
constexpr float kIconSize = 32.0f;

} // namespace

LauncherPanel::LauncherPanel() = default;

void LauncherPanel::addProvider(std::unique_ptr<LauncherProvider> provider) {
  provider->initialize();
  m_providers.push_back(std::move(provider));
}

void LauncherPanel::create(Renderer& renderer) {
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
  input->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t modifiers) {
    return handleKeyEvent(sym, modifiers);
  });
  m_input = input.get();
  container->addChild(std::move(input));

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setScrollbarVisible(true);
  scrollView->setFlexGrow(1.0f);
  m_scrollView = scrollView.get();
  m_list = scrollView->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  container->addChild(std::move(scrollView));

  m_container = container.get();
  m_root = std::move(container);

  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  // Run initial query to populate list
  onInputChanged("");
  rebuildResults(renderer, preferredWidth());
}

void LauncherPanel::layout(Renderer& renderer, float width, float height) {
  if (m_container == nullptr || m_input == nullptr || m_scrollView == nullptr) {
    return;
  }

  m_container->setSize(width, height);
  m_container->layout(renderer);

  if (m_dirty) {
    rebuildResults(renderer, m_scrollView->contentViewportWidth());
    m_dirty = false;
  }

  m_lastWidth = width;
}

void LauncherPanel::update(Renderer& renderer) {
  if (m_dirty && m_lastWidth > 0.0f) {
    const float listWidth = m_scrollView != nullptr ? m_scrollView->contentViewportWidth() : m_lastWidth;
    rebuildResults(renderer, listWidth);
    m_dirty = false;
  }
}

void LauncherPanel::onOpen(std::string_view /*context*/) {
  m_query.clear();
  m_selectedIndex = 0;
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
  m_dirty = true;
  if (m_input != nullptr) {
    m_input->setValue("");
  }
  if (m_scrollView != nullptr) {
    m_scrollView->setScrollOffset(0.0f);
  }
}

void LauncherPanel::onClose() {
  m_query.clear();
  m_results.clear();
  m_selectedIndex = 0;
  m_lastWidth = 0.0f;
  m_dirty = false;

  // The scene tree (and all nodes) is destroyed by PanelManager after onClose(),
  // so null out all raw pointers to avoid dangling references on re-open.
  m_container = nullptr;
  m_input = nullptr;
  m_scrollView = nullptr;
  m_list = nullptr;
}

InputArea* LauncherPanel::initialFocusArea() const {
  return m_input != nullptr ? m_input->inputArea() : nullptr;
}

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

  if (m_results.size() > kMaxResults) {
    m_results.resize(kMaxResults);
  }

  m_selectedIndex = 0;
  m_dirty = true;
}

void LauncherPanel::rebuildResults(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  const float scale = contentScale();
  const float iconSize = kIconSize * scale;

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (m_results.empty()) {
    auto emptyLabel = std::make_unique<Label>();
    emptyLabel->setText(m_query.empty() ? "Type to search..." : "No results found");
    emptyLabel->setCaptionStyle();
    emptyLabel->setColor(palette.onSurfaceVariant);
    emptyLabel->setMaxWidth(width);
    m_list->addChild(std::move(emptyLabel));
    return;
  }

  for (std::size_t i = 0; i < m_results.size(); ++i) {
    const auto& result = m_results[i];

    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(Style::spaceMd * scale);
    row->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
    row->setMinWidth(width);
    row->setRadius(Style::radiusMd * scale);
    if (i == m_selectedIndex) {
      row->setBackground(palette.surfaceVariant);
    }

    auto* rowPtr = row.get();
    auto area = std::make_unique<InputArea>();
    area->setPropagateEvents(true);
    area->setOnClick([this, idx = i](const InputArea::PointerData& /*data*/) {
      m_selectedIndex = idx;
      activateSelected();
    });
    area->setOnMotion([this, idx = i, rowPtr](const InputArea::PointerData& /*data*/) {
      if (!m_mouseActive) {
        m_mouseActive = true;
        if (idx != m_selectedIndex && m_hoverIndex != idx) {
          m_hoverIndex = idx;
          rowPtr->setBackground(
              rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.45f));
          PanelManager::instance().refresh();
        }
      }
    });
    area->setOnEnter([this, idx = i, rowPtr](const InputArea::PointerData& /*data*/) {
      if (!m_mouseActive || idx == m_selectedIndex) {
        return;
      }
      m_hoverIndex = idx;
      rowPtr->setBackground(
          rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.45f));
      PanelManager::instance().refresh();
    });
    area->setOnLeave([this, idx = i, rowPtr]() {
      if (m_hoverIndex != idx || idx == m_selectedIndex) {
        return;
      }
      m_hoverIndex = static_cast<std::size_t>(-1);
      rowPtr->setBackground(rgba(0, 0, 0, 0));
      PanelManager::instance().refresh();
    });

    // Icon/action text
    if (!result.actionText.empty()) {
      auto actionLabel = std::make_unique<Label>();
      actionLabel->setText(result.actionText);
      actionLabel->setFontSize(Style::fontSizeTitle * scale);
      actionLabel->setColor(palette.onSurface);
      actionLabel->setSize(iconSize, iconSize);
      row->addChild(std::move(actionLabel));
    } else if (!result.iconPath.empty()) {
      auto image = std::make_unique<Image>();
      image->setSize(iconSize, iconSize);
      image->setSourceFile(renderer, result.iconPath, static_cast<int>(iconSize));
      row->addChild(std::move(image));
    } else {
      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyph(result.glyphName.empty() ? "app-window" : result.glyphName);
      glyph->setGlyphSize(iconSize);
      glyph->setColor(palette.onSurface);
      row->addChild(std::move(glyph));
    }

    // Text column
    auto textCol = std::make_unique<Flex>();
    textCol->setDirection(FlexDirection::Vertical);
    textCol->setAlign(FlexAlign::Start);
    textCol->setGap(Style::spaceXs * scale);

    const float textWidth = std::max(0.0f, width - iconSize - Style::spaceSm * scale * 2.0f - Style::spaceMd * scale);

    auto title = std::make_unique<Label>();
    title->setText(result.title);
    title->setFontSize(Style::fontSizeBody * scale);
    title->setBold(true);
    title->setColor(palette.onSurface);
    title->setMaxWidth(textWidth);
    textCol->addChild(std::move(title));

    if (!result.subtitle.empty()) {
      auto subtitle = std::make_unique<Label>();
      subtitle->setText(result.subtitle);
      subtitle->setCaptionStyle();
      subtitle->setFontSize(Style::fontSizeCaption * scale);
      subtitle->setColor(palette.onSurfaceVariant);
      subtitle->setMaxWidth(textWidth);
      textCol->addChild(std::move(subtitle));
    }

    row->addChild(std::move(textCol));
    row->layout(renderer);

    area->setSize(row->width(), row->height());
    area->addChild(std::move(row));
    m_list->addChild(std::move(area));
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

bool LauncherPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t /*modifiers*/) {
  if (sym == XKB_KEY_Up) {
    if (m_selectedIndex > 0) {
      --m_selectedIndex;
      m_dirty = true;
      scrollToSelected();
      if (root() != nullptr) {
        root()->markDirty();
      }
    }
    return true;
  }

  if (sym == XKB_KEY_Down) {
    if (!m_results.empty() && m_selectedIndex < m_results.size() - 1) {
      ++m_selectedIndex;
      m_dirty = true;
      scrollToSelected();
      if (root() != nullptr) {
        root()->markDirty();
      }
    }
    return true;
  }

  if (sym == XKB_KEY_Return) {
    activateSelected();
    return true;
  }

  return false;
}

void LauncherPanel::scrollToSelected() {
  if (m_scrollView == nullptr || m_list == nullptr) {
    return;
  }

  const auto& children = m_list->children();
  if (m_selectedIndex >= children.size()) {
    return;
  }

  const auto* item = children[m_selectedIndex].get();
  const float itemTop = item->y();
  const float itemBottom = itemTop + item->height();
  // The ScrollView viewport is smaller than the outer widget by vertical padding
  constexpr float kScrollViewPaddingV = Style::spaceSm;
  const float viewportH = m_scrollView->height() - kScrollViewPaddingV * 2.0f;
  const float scrollOffset = m_scrollView->scrollOffset();

  if (itemTop < scrollOffset) {
    m_scrollView->setScrollOffset(itemTop);
  } else if (itemBottom > scrollOffset + viewportH) {
    m_scrollView->setScrollOffset(itemBottom - viewportH);
  }
}

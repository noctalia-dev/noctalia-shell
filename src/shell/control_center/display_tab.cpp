#include "shell/control_center/display_tab.h"

#include "config/config_service.h"
#include "render/core/renderer.h"
#include "system/brightness_service.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/controls/slider.h"
#include "ui/palette.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>

using namespace control_center;

namespace {

  constexpr float kBrightnessSyncEpsilon = 0.005f;
  constexpr auto kBrightnessCommitInterval = std::chrono::milliseconds(16);
  constexpr auto kBrightnessStateHoldoff = std::chrono::milliseconds(180);

  std::string buildDisplayListKey(const std::vector<BrightnessDisplay>& displays) {
    std::string key;
    for (const auto& d : displays) {
      key += d.id;
      key += ';';
    }
    return key;
  }

} // namespace

DisplayTab::DisplayTab(BrightnessService* brightness, ConfigService* config)
    : m_brightness(brightness), m_config(config) {}

std::unique_ptr<Flex> DisplayTab::create() {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  // Empty state (shown when no displays have brightness control)
  auto emptyState = std::make_unique<Flex>();
  emptyState->setDirection(FlexDirection::Vertical);
  emptyState->setAlign(FlexAlign::Center);
  emptyState->setJustify(FlexJustify::Center);
  emptyState->setFlexGrow(1.0f);
  auto emptyLabel = std::make_unique<Label>();
  emptyLabel->setText("No brightness control available");
  emptyLabel->setFontSize(Style::fontSizeBody * scale);
  emptyLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  emptyState->addChild(std::move(emptyLabel));
  m_emptyState = emptyState.get();
  tab->addChild(std::move(emptyState));

  return tab;
}

void DisplayTab::onClose() {
  flushPendingBrightness(true);
  m_debounceTimer.stop();
  m_rootLayout = nullptr;
  m_emptyState = nullptr;
  m_cards.clear();
  m_lastDisplayListKey.clear();
}

bool DisplayTab::dragging() const noexcept {
  for (const auto& card : m_cards) {
    if (card.slider != nullptr && card.slider->dragging()) {
      return true;
    }
  }
  return false;
}

void DisplayTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }

  rebuildCards(renderer);

  const float scale = contentScale();
  const float cardWidth = std::max(1.0f, contentWidth);
  const float cardInnerWidth = std::max(1.0f, cardWidth - Style::spaceMd * scale * 2.0f);
  const float headerTextMaxWidth =
      std::max(1.0f, cardInnerWidth - Style::fontSizeTitle * scale - Style::spaceSm * scale);
  for (auto& card : m_cards) {
    if (card.card != nullptr) {
      card.card->setMinWidth(cardWidth);
    }
    if (card.nameLabel != nullptr) {
      card.nameLabel->setMaxLines(1);
      card.nameLabel->setMaxWidth(headerTextMaxWidth);
    }
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);
}

void DisplayTab::doUpdate(Renderer& renderer) {
  rebuildCards(renderer);

  if (m_brightness == nullptr) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();

  for (auto& card : m_cards) {
    const auto* display = m_brightness->findDisplay(card.displayId);
    if (display == nullptr || card.slider == nullptr) {
      continue;
    }

    const bool isDragging = card.slider->dragging();
    const bool isPending = m_pendingDisplayId == card.displayId && m_pendingBrightness >= 0.0f;
    const bool holdState = isDragging && m_lastSentBrightness >= 0.0f && now < m_ignoreStateUntil &&
                           std::abs(display->brightness - m_lastSentBrightness) > 0.02f;

    const float displayedBrightness = std::clamp(
        isPending ? m_pendingBrightness : (holdState ? m_lastSentBrightness : display->brightness), 0.0f, 1.0f);

    card.slider->setEnabled(true);
    if (!isDragging && std::abs(displayedBrightness - card.lastBrightness) >= kBrightnessSyncEpsilon) {
      m_syncingSlider = true;
      card.slider->setValue(displayedBrightness);
      m_syncingSlider = false;
      if (card.valueLabel != nullptr) {
        card.valueLabel->setText(std::to_string(static_cast<int>(std::round(displayedBrightness * 100.0f))) + "%");
      }
      card.lastBrightness = displayedBrightness;
    }
  }
}

void DisplayTab::rebuildCards(Renderer& /*renderer*/) {
  if (m_brightness == nullptr || m_rootLayout == nullptr) {
    return;
  }

  const auto& displays = m_brightness->displays();
  const std::string key = buildDisplayListKey(displays);
  if (key == m_lastDisplayListKey) {
    return;
  }
  m_lastDisplayListKey = key;

  // Remove old cards
  for (auto& card : m_cards) {
    if (card.card != nullptr) {
      m_rootLayout->removeChild(card.card);
    }
  }
  m_cards.clear();

  // Show/hide empty state
  const bool empty = displays.empty();
  if (m_emptyState != nullptr) {
    m_emptyState->setVisible(empty);
  }

  if (empty) {
    return;
  }

  const float scale = contentScale();

  for (const auto& display : displays) {
    // Card container
    auto card = std::make_unique<Flex>();
    applyOutlinedCard(*card, scale);

    // Header row: icon + display name
    auto headerRow = std::make_unique<Flex>();
    headerRow->setDirection(FlexDirection::Horizontal);
    headerRow->setAlign(FlexAlign::Center);
    headerRow->setGap(Style::spaceSm * scale);

    auto icon = std::make_unique<Glyph>();
    icon->setGlyph("device-desktop");
    icon->setGlyphSize(Style::fontSizeTitle * scale);
    icon->setColor(roleColor(ColorRole::OnSurface));
    auto* iconPtr = icon.get();
    headerRow->addChild(std::move(icon));

    auto nameLabel = std::make_unique<Label>();
    nameLabel->setText(display.label);
    nameLabel->setBold(true);
    nameLabel->setFontSize(Style::fontSizeBody * scale);
    nameLabel->setColor(roleColor(ColorRole::OnSurface));
    nameLabel->setFlexGrow(1.0f);
    auto* nameLabelPtr = nameLabel.get();
    headerRow->addChild(std::move(nameLabel));

    card->addChild(std::move(headerRow));

    // Slider row: sun icon + slider + percentage
    auto sliderRow = std::make_unique<Flex>();
    sliderRow->setDirection(FlexDirection::Horizontal);
    sliderRow->setAlign(FlexAlign::Center);
    sliderRow->setGap(Style::spaceSm * scale);

    auto sunIcon = std::make_unique<Glyph>();
    sunIcon->setGlyph("brightness-low");
    sunIcon->setGlyphSize(Style::fontSizeTitle * scale);
    sunIcon->setColor(roleColor(ColorRole::OnSurfaceVariant));
    sliderRow->addChild(std::move(sunIcon));

    auto slider = std::make_unique<Slider>();
    slider->setRange(0.0f, 1.0f);
    slider->setStep(0.01f);
    slider->setFlexGrow(1.0f);
    slider->setControlHeight(Style::controlHeight * scale);
    slider->setTrackHeight(6.0f * scale);
    slider->setThumbSize(16.0f * scale);
    slider->setValue(display.brightness);

    const std::string displayId = display.id;
    slider->setOnValueChanged([this, displayId](float value) {
      if (m_syncingSlider) {
        return;
      }
      queueBrightness(displayId, value);
      // Update the value label immediately
      for (auto& c : m_cards) {
        if (c.displayId == displayId && c.valueLabel != nullptr) {
          c.valueLabel->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
          c.lastBrightness = value;
          break;
        }
      }
    });
    slider->setOnDragEnd([this]() { flushPendingBrightness(true); });

    auto* sliderPtr = slider.get();
    sliderRow->addChild(std::move(slider));

    auto sunHighIcon = std::make_unique<Glyph>();
    sunHighIcon->setGlyph("brightness-high");
    sunHighIcon->setGlyphSize(Style::fontSizeTitle * scale);
    sunHighIcon->setColor(roleColor(ColorRole::OnSurfaceVariant));
    sliderRow->addChild(std::move(sunHighIcon));

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText(std::to_string(static_cast<int>(std::round(display.brightness * 100.0f))) + "%");
    valueLabel->setFontSize(Style::fontSizeBody * scale);
    valueLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
    valueLabel->setMinWidth(Style::controlHeightLg * scale);
    auto* valueLabelPtr = valueLabel.get();
    sliderRow->addChild(std::move(valueLabel));

    card->addChild(std::move(sliderRow));

    auto* cardPtr = card.get();
    m_rootLayout->addChild(std::move(card));

    m_cards.push_back(DisplayCard{
        .displayId = display.id,
        .card = cardPtr,
        .nameLabel = nameLabelPtr,
        .icon = iconPtr,
        .slider = sliderPtr,
        .valueLabel = valueLabelPtr,
        .lastBrightness = display.brightness,
    });
  }
}

void DisplayTab::queueBrightness(const std::string& displayId, float value) {
  m_pendingDisplayId = displayId;
  m_pendingBrightness = value;

  const auto now = std::chrono::steady_clock::now();
  if (now - m_lastCommitAt >= kBrightnessCommitInterval) {
    flushPendingBrightness();
    return;
  }

  if (!m_debounceTimer.active()) {
    m_debounceTimer.start(kBrightnessCommitInterval, [this]() { flushPendingBrightness(); });
  }
}

void DisplayTab::flushPendingBrightness(bool /*force*/) {
  m_debounceTimer.stop();

  if (m_pendingBrightness < 0.0f || m_brightness == nullptr) {
    return;
  }

  m_brightness->setBrightness(m_pendingDisplayId, m_pendingBrightness);
  m_lastSentBrightness = m_pendingBrightness;
  m_lastCommitAt = std::chrono::steady_clock::now();
  m_ignoreStateUntil = m_lastCommitAt + kBrightnessStateHoldoff;
  m_pendingBrightness = -1.0f;
}

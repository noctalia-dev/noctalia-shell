#include "shell/bar/widgets/lock_keys_widget.h"

#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>

namespace {

  constexpr auto kLockKeysProbeInterval = std::chrono::milliseconds(500);

  struct SysfsLockKeysState {
    bool capsLock = false;
    bool numLock = false;
    bool scrollLock = false;
    bool hasAnyLed = false;
  };

  SysfsLockKeysState readLockKeysFromSysfs() {
    namespace fs = std::filesystem;

    SysfsLockKeysState result;
    std::error_code ec;
    const fs::path ledsDir{"/sys/class/leds"};
    if (!fs::is_directory(ledsDir, ec)) {
      return result;
    }

    for (const auto& entry : fs::directory_iterator(ledsDir, ec)) {
      if (ec) {
        break;
      }
      if (!entry.is_directory(ec) || ec) {
        continue;
      }

      const std::string name = entry.path().filename().string();
      const std::size_t sep = name.find("::");
      if (sep == std::string::npos) {
        continue;
      }

      const std::string kind = name.substr(sep + 2);
      if (kind != "capslock" && kind != "numlock" && kind != "scrolllock") {
        continue;
      }

      std::ifstream file(entry.path() / "brightness");
      if (!file.is_open()) {
        continue;
      }
      int brightness = 0;
      file >> brightness;
      if (!file.good() && !file.eof()) {
        continue;
      }

      result.hasAnyLed = true;
      const bool isOn = brightness != 0;
      if (kind == "capslock") {
        result.capsLock = result.capsLock || isOn;
      } else if (kind == "numlock") {
        result.numLock = result.numLock || isOn;
      } else {
        result.scrollLock = result.scrollLock || isOn;
      }
    }

    return result;
  }

  void configureLabel(Label* label, const std::string& text, bool visible, float contentScale) {
    if (label == nullptr) {
      return;
    }

    label->setVisible(visible);
    label->setFontSize(Style::fontSizeBody * contentScale);
    label->setBold(true);
    label->setText(text);
  }

} // namespace

LockKeysWidget::LockKeysWidget(WaylandConnection& wayland, bool showCapsLock, bool showNumLock, bool showScrollLock,
                               bool hideWhenOff, DisplayMode displayMode)
    : m_wayland(wayland), m_showCapsLock(showCapsLock), m_showNumLock(showNumLock), m_showScrollLock(showScrollLock),
      m_hideWhenOff(hideWhenOff), m_displayMode(displayMode) {}

LockKeysWidget::DisplayMode LockKeysWidget::parseDisplayMode(const std::string& value) {
  return value == "full" ? DisplayMode::Full : DisplayMode::Short;
}

void LockKeysWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("lock");
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  rootNode->addChild(std::move(glyph));

  auto caps = std::make_unique<Label>();
  m_capsLabel = caps.get();
  rootNode->addChild(std::move(caps));

  auto num = std::make_unique<Label>();
  m_numLabel = num.get();
  rootNode->addChild(std::move(num));

  auto scroll = std::make_unique<Label>();
  m_scrollLabel = scroll.get();
  rootNode->addChild(std::move(scroll));

  setRoot(std::move(rootNode));

  // Lock LED state updates are not event-driven; probe at a low interval.
  m_refreshTimer.startRepeating(kLockKeysProbeInterval, [this]() {
    if (auto* node = root(); node != nullptr) {
      node->markLayoutDirty();
    }
    requestRedraw();
  });
}

void LockKeysWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  if (root() == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;

  sync(renderer);

  if (!root()->visible()) {
    root()->setSize(0.0f, 0.0f);
    return;
  }

  constexpr float kSpacing = Style::spaceXs;
  const float spacing = kSpacing * m_contentScale;
  float x = 0.0f;
  float y = 0.0f;
  float h = 0.0f;
  float w = 0.0f;

  if (m_glyph != nullptr) {
    m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
    m_glyph->measure(renderer);
    if (m_isVertical) {
      y += m_glyph->height() + spacing;
      w = std::max(w, m_glyph->width());
    } else {
      m_glyph->setPosition(0.0f, 0.0f);
      x += m_glyph->width() + spacing;
      h = std::max(h, m_glyph->height());
    }
  }

  auto layoutLabel = [&](Label* label) {
    if (label == nullptr || !label->visible()) {
      return;
    }
    label->setTextAlign(m_isVertical ? TextAlign::Center : TextAlign::Start);
    label->setMaxWidth(m_isVertical ? containerWidth : 0.0f);
    label->measure(renderer);
    if (m_isVertical) {
      y += label->height() + spacing;
      w = std::max(w, label->width());
    } else {
      label->setPosition(x, 0.0f);
      x += label->width() + spacing;
      h = std::max(h, label->height());
    }
  };

  layoutLabel(m_capsLabel);
  layoutLabel(m_numLabel);
  layoutLabel(m_scrollLabel);

  if (m_isVertical) {
    if (y > 0.0f) {
      y -= spacing;
    }
    float cursorY = 0.0f;
    if (m_glyph != nullptr) {
      m_glyph->setPosition(std::round((w - m_glyph->width()) * 0.5f), 0.0f);
      cursorY = m_glyph->height() + spacing;
    }
    auto placeLabel = [&](Label* label) {
      if (label == nullptr || !label->visible()) {
        return;
      }
      label->setPosition(std::round((w - label->width()) * 0.5f), cursorY);
      cursorY += label->height() + spacing;
    };
    placeLabel(m_capsLabel);
    placeLabel(m_numLabel);
    placeLabel(m_scrollLabel);
    root()->setSize(w, y);
  } else {
    if (x > 0.0f) {
      x -= spacing;
    }
    if (m_glyph != nullptr) {
      const float glyphY = std::round((h - m_glyph->height()) * 0.5f);
      m_glyph->setPosition(0.0f, glyphY);
    }
    auto centerLabel = [h](Label* label) {
      if (label == nullptr || !label->visible()) {
        return;
      }
      label->setPosition(label->x(), std::round((h - label->height()) * 0.5f));
    };
    centerLabel(m_capsLabel);
    centerLabel(m_numLabel);
    centerLabel(m_scrollLabel);
    root()->setSize(x, h);
  }
}

void LockKeysWidget::doUpdate(Renderer& renderer) { sync(renderer); }

void LockKeysWidget::sync(Renderer& renderer) {
  (void)renderer;

  // Prefer sysfs LED state (compositor-agnostic, no group membership required).
  // Fall back to the XKB state from the Wayland seat when sysfs has no LED entries.
  WaylandSeat::LockKeysState lockState;
  const auto sysfs = readLockKeysFromSysfs();
  if (sysfs.hasAnyLed) {
    lockState.capsLock = sysfs.capsLock;
    lockState.numLock = sysfs.numLock;
    lockState.scrollLock = sysfs.scrollLock;
  } else {
    lockState = m_wayland.keyboardLockKeysState();
  }

  const bool capsVisible = m_showCapsLock && (!m_hideWhenOff || lockState.capsLock);
  const bool numVisible = m_showNumLock && (!m_hideWhenOff || lockState.numLock);
  const bool scrollVisible = m_showScrollLock && (!m_hideWhenOff || lockState.scrollLock);
  const bool anyVisible = capsVisible || numVisible || scrollVisible;

  CachedState current{
      .capsLock = lockState.capsLock,
      .numLock = lockState.numLock,
      .scrollLock = lockState.scrollLock,
      .anyVisible = anyVisible,
  };

  if (m_hasState && current == m_cachedState) {
    return;
  }

  m_cachedState = current;
  m_hasState = true;

  if (auto* node = root(); node != nullptr) {
    node->setVisible(anyVisible || !m_hideWhenOff);
  }

  if (m_glyph != nullptr) {
    m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
    m_glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  }

  const bool full = m_displayMode == DisplayMode::Full;
  configureLabel(m_capsLabel,
                 full ? i18n::tr("bar.widgets.lock-keys.caps") : i18n::tr("bar.widgets.lock-keys.caps-short"),
                 capsVisible, m_contentScale);
  configureLabel(m_numLabel, full ? i18n::tr("bar.widgets.lock-keys.num") : i18n::tr("bar.widgets.lock-keys.num-short"),
                 numVisible, m_contentScale);
  configureLabel(m_scrollLabel,
                 full ? i18n::tr("bar.widgets.lock-keys.scroll") : i18n::tr("bar.widgets.lock-keys.scroll-short"),
                 scrollVisible, m_contentScale);

  if (m_capsLabel != nullptr) {
    m_capsLabel->setColor(lockState.capsLock ? colorSpecFromRole(ColorRole::Primary)
                                             : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurfaceVariant)));
  }
  if (m_numLabel != nullptr) {
    m_numLabel->setColor(lockState.numLock ? colorSpecFromRole(ColorRole::Primary)
                                           : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurfaceVariant)));
  }
  if (m_scrollLabel != nullptr) {
    m_scrollLabel->setColor(lockState.scrollLock ? colorSpecFromRole(ColorRole::Primary)
                                                 : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurfaceVariant)));
  }

  if (auto* node = root(); node != nullptr) {
    node->markLayoutDirty();
  }
  requestRedraw();
}

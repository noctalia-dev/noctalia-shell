#include "ui/controls/input.h"

#include "cursor-shape-v1-client-protocol.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "render/programs/rect_program.h"
#include "render/scene/glyph_node.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "ui/controls/glyph_registry.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/clipboard_service.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  ClipboardService* g_clipboard = nullptr;
  Input::PasswordMaskStyle g_passwordMaskStyle = Input::PasswordMaskStyle::CircleFilled;

  std::optional<std::string> readClipboardText() {
    if (g_clipboard == nullptr) {
      return std::nullopt;
    }
    const auto& hist = g_clipboard->history();
    for (std::size_t i = 0; i < hist.size(); ++i) {
      if (hist[i].isImage()) {
        continue;
      }
      if (!g_clipboard->ensureEntryLoaded(i)) {
        continue;
      }
      const auto& entry = g_clipboard->history()[i];
      if (entry.data.empty()) {
        continue;
      }
      return std::string(entry.data.begin(), entry.data.end());
    }
    return std::nullopt;
  }

  // Modifier bitmask — must match KeyMod constants in wayland/wayland_seat.h
  constexpr std::uint32_t kModShift = 1u << 0;
  constexpr std::uint32_t kModCtrl = 1u << 1;

  constexpr float kDefaultWidth = 200.0f;
  constexpr float kCursorWidth = 1.5f;
  constexpr float kCursorPadV = 3.0f;
  constexpr float kPasswordGlyphScale = 0.82f;

  char32_t passwordMaskCodepointForIndex(std::size_t index) {
    if (g_passwordMaskStyle == Input::PasswordMaskStyle::CircleFilled) {
      return GlyphRegistry::lookup("circle-filled");
    }
    static const std::array<char32_t, 7> randomCodepoints = {
        GlyphRegistry::lookup("circle-filled"),        GlyphRegistry::lookup("pentagon-filled"),
        GlyphRegistry::lookup("michelin-star-filled"), GlyphRegistry::lookup("square-rounded-filled"),
        GlyphRegistry::lookup("guitar-pick-filled"),   GlyphRegistry::lookup("blob-filled"),
        GlyphRegistry::lookup("triangle-filled"),
    };
    return randomCodepoints[index % randomCodepoints.size()];
  }

  Color resolved(ColorRole role, float alpha = 1.0f) { return resolveThemeColor(roleColor(role, alpha)); }

} // namespace

Input::Input() {
  setClipChildren(true);

  // 0: background
  auto bg = std::make_unique<RectNode>();
  m_background = static_cast<RectNode*>(addChild(std::move(bg)));

  // 1: selection highlight (rendered behind text)
  auto sel = std::make_unique<RectNode>();
  sel->setStyle(RoundedRectStyle{
      .fill = resolved(ColorRole::Primary),
      .fillMode = FillMode::Solid,
      .radius = 2.0f,
  });
  sel->setOpacity(0.3f);
  sel->setVisible(false);
  m_selectionRect = static_cast<RectNode*>(addChild(std::move(sel)));

  // 2: text
  auto label = std::make_unique<Label>();
  label->setFontSize(m_fontSize);
  label->setMaxLines(1);
  label->setColor(roleColor(ColorRole::OnSurface));
  m_label = static_cast<Label*>(addChild(std::move(label)));

  // 3: cursor
  auto cursor = std::make_unique<RectNode>();
  cursor->setStyle(RoundedRectStyle{
      .fill = resolved(ColorRole::Primary),
      .fillMode = FillMode::Solid,
      .radius = 1.0f,
  });
  cursor->setVisible(false);
  m_cursor = static_cast<RectNode*>(addChild(std::move(cursor)));

  // 4: input area
  auto area = std::make_unique<InputArea>();
  area->setFocusable(true);
  area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_TEXT);
  area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
  area->setOnLeave([this]() { applyVisualState(); });
  area->setOnFocusGain([this]() {
    m_cursor->setVisible(true);
    applyVisualState();
  });
  area->setOnFocusLoss([this]() {
    m_cursor->setVisible(false);
    applyVisualState();
  });
  area->setOnPress([this](const InputArea::PointerData& data) {
    if (data.pressed) {
      const std::size_t offset = xToByteOffset(data.localX - m_horizontalPadding);
      m_cursorPos = offset;
      m_selectionAnchor = offset;
      markPaintDirty();
    }
  });
  area->setOnMotion([this](const InputArea::PointerData& data) {
    if (m_inputArea != nullptr && m_inputArea->pressed()) {
      m_cursorPos = xToByteOffset(data.localX - m_horizontalPadding);
      markPaintDirty();
    }
  });
  area->setOnKeyDown([this](const InputArea::KeyData& k) { handleKey(k.sym, k.utf32, k.modifiers, k.preedit); });
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

  applyVisualState();
  m_paletteConn = paletteChanged().connect([this] {
    updateDisplayText();
    applyVisualState();
  });
}

void Input::setValue(std::string_view value) {
  m_value = std::string(value);
  m_cursorPos = m_value.size();
  m_selectionAnchor = m_cursorPos;
  updateDisplayText();
  markLayoutDirty();
}

void Input::setPlaceholder(std::string_view placeholder) {
  m_placeholder = std::string(placeholder);
  if (m_value.empty()) {
    updateDisplayText();
    markLayoutDirty();
  }
}

void Input::setFontSize(float size) {
  m_fontSize = std::max(1.0f, size);
  if (m_label != nullptr) {
    m_label->setFontSize(m_fontSize);
  }
  markLayoutDirty();
}

void Input::setControlHeight(float height) {
  m_controlHeight = std::max(1.0f, height);
  markLayoutDirty();
}

void Input::setHorizontalPadding(float padding) {
  m_horizontalPadding = std::max(0.0f, padding);
  markLayoutDirty();
}

void Input::setPasswordMode(bool enabled) {
  if (m_passwordMode == enabled) {
    return;
  }
  m_passwordMode = enabled;
  if (!m_passwordMode) {
    syncPasswordGlyphNodes(0);
  }
  updateDisplayText();
  markLayoutDirty();
}

void Input::setOnChange(std::function<void(const std::string&)> callback) { m_onChange = std::move(callback); }

void Input::setOnSubmit(std::function<void(const std::string&)> callback) { m_onSubmit = std::move(callback); }

void Input::setOnKeyEvent(std::function<bool(std::uint32_t, std::uint32_t)> callback) {
  m_onKeyEvent = std::move(callback);
}

void Input::setClipboardService(ClipboardService* clipboard) noexcept { g_clipboard = clipboard; }

void Input::setPasswordMaskStyle(PasswordMaskStyle style) noexcept { g_passwordMaskStyle = style; }

void Input::selectAll() {
  m_selectionAnchor = 0;
  m_cursorPos = m_value.size();
  markPaintDirty();
}

void Input::clearSelection() {
  m_selectionAnchor = m_cursorPos;
  markPaintDirty();
}

void Input::doLayout(Renderer& renderer) {
  const float w = width() > 0.0f ? width() : kDefaultWidth;
  const float h = m_controlHeight;
  setSize(w, h);

  const bool showPasswordGlyphs = m_passwordMode && !m_value.empty();
  m_label->setVisible(!showPasswordGlyphs);
  if (!showPasswordGlyphs) {
    m_label->measure(renderer);
    const float labelY = std::round((h - m_label->height()) * 0.5f);
    m_label->setPosition(m_horizontalPadding, labelY);
  }

  m_stopByte.clear();
  m_stopX.clear();
  m_stopByte.push_back(0);
  m_stopX.push_back(0.0f);
  std::size_t charCount = 0;
  float maskGlyphY = 0.0f;
  float glyphSize = 0.0f;
  if (showPasswordGlyphs) {
    glyphSize = m_fontSize * kPasswordGlyphScale;
    const auto metrics = renderer.measureGlyph(passwordMaskCodepointForIndex(0), glyphSize);
    const float glyphInkCenter = (metrics.top + metrics.bottom) * 0.5f;
    maskGlyphY = std::round(h * 0.5f - glyphInkCenter);
  }
  if (!m_value.empty()) {
    std::size_t pos = 0;
    float maskX = 0.0f;
    while (pos < m_value.size()) {
      pos = nextCharPos(m_value, pos);
      ++charCount;
      m_stopByte.push_back(pos);
      if (showPasswordGlyphs) {
        const auto metrics = renderer.measureGlyph(passwordMaskCodepointForIndex(charCount - 1), glyphSize);
        maskX += metrics.width;
        m_stopX.push_back(maskX);
      } else {
        m_stopX.push_back(renderer.measureText(m_value.substr(0, pos), m_fontSize).width);
      }
    }
  }

  const float cursorX = m_horizontalPadding + stopXForByte(m_cursorPos);
  m_cursor->setPosition(cursorX, kCursorPadV);
  m_cursor->setFrameSize(kCursorWidth, h - kCursorPadV * 2.0f);

  if (hasSelection()) {
    const float selX0 = m_horizontalPadding + stopXForByte(selectionStart());
    const float selX1 = m_horizontalPadding + stopXForByte(selectionEnd());
    m_selectionRect->setPosition(selX0, kCursorPadV);
    m_selectionRect->setFrameSize(selX1 - selX0, h - kCursorPadV * 2.0f);
    m_selectionRect->setVisible(true);
  } else {
    m_selectionRect->setVisible(false);
  }

  if (showPasswordGlyphs) {
    syncPasswordGlyphNodes(charCount);
    float maskX = 0.0f;
    for (std::size_t i = 0; i < m_passwordGlyphs.size(); ++i) {
      auto* glyph = m_passwordGlyphs[i];
      const char32_t codepoint = passwordMaskCodepointForIndex(i);
      const auto metrics = renderer.measureGlyph(codepoint, glyphSize);
      glyph->setCodepoint(codepoint);
      glyph->setFontSize(glyphSize);
      glyph->setColor(resolveThemeColor(roleColor(ColorRole::OnSurface)));
      glyph->setPosition(m_horizontalPadding + maskX, maskGlyphY);
      glyph->setVisible(true);
      maskX += metrics.width;
    }
  } else {
    syncPasswordGlyphNodes(0);
  }

  m_background->setPosition(0.0f, 0.0f);
  m_background->setFrameSize(w, h);

  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setFrameSize(w, h);

  applyVisualState();
}

void Input::handleKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers, bool preedit) {
  if (m_onKeyEvent && m_onKeyEvent(sym, modifiers)) {
    return;
  }

  // Ignore keys that produce no text and aren't action keys we handle below
  if (utf32 == 0 && !preedit && sym != XKB_KEY_BackSpace && sym != XKB_KEY_Delete && sym != XKB_KEY_Left &&
      sym != XKB_KEY_Right && sym != XKB_KEY_Home && sym != XKB_KEY_End && sym != XKB_KEY_Return) {
    return;
  }

  bool changed = false;
  const bool shift = (modifiers & kModShift) != 0;
  const bool ctrl = (modifiers & kModCtrl) != 0;

  // Remove previous preedit text before processing
  if (m_preeditLen > 0) {
    m_value.erase(m_preeditStart, m_preeditLen);
    m_cursorPos = m_preeditStart;
    m_selectionAnchor = m_cursorPos;
    m_preeditLen = 0;
    changed = true;
  }

  if (ctrl && (sym == 'a' || sym == 'A')) {
    // Select all
    m_selectionAnchor = 0;
    m_cursorPos = m_value.size();
  } else if (ctrl && (sym == 'c' || sym == 'C')) {
    if (g_clipboard != nullptr && hasSelection()) {
      g_clipboard->copyText(m_value.substr(selectionStart(), selectionEnd() - selectionStart()));
    }
  } else if (ctrl && (sym == 'x' || sym == 'X')) {
    if (g_clipboard != nullptr && hasSelection()) {
      g_clipboard->copyText(m_value.substr(selectionStart(), selectionEnd() - selectionStart()));
      deleteSelection();
      changed = true;
    }
  } else if (ctrl && (sym == 'v' || sym == 'V')) {
    if (g_clipboard != nullptr) {
      if (auto text = readClipboardText(); text.has_value()) {
        if (hasSelection()) {
          deleteSelection();
        }
        m_value.insert(m_cursorPos, *text);
        m_cursorPos += text->size();
        m_selectionAnchor = m_cursorPos;
        changed = true;
      }
    }
  } else if (sym == XKB_KEY_BackSpace) {
    if (hasSelection()) {
      deleteSelection();
      changed = true;
    } else if (m_cursorPos > 0) {
      const std::size_t prev = prevCharPos(m_value, m_cursorPos);
      m_value.erase(prev, m_cursorPos - prev);
      m_cursorPos = prev;
      m_selectionAnchor = prev;
      changed = true;
    }
  } else if (sym == XKB_KEY_Delete) {
    if (hasSelection()) {
      deleteSelection();
      changed = true;
    } else if (m_cursorPos < m_value.size()) {
      const std::size_t next = nextCharPos(m_value, m_cursorPos);
      m_value.erase(m_cursorPos, next - m_cursorPos);
      changed = true;
    }
  } else if (sym == XKB_KEY_Left) {
    if (!shift && hasSelection()) {
      // Collapse to start of selection
      m_cursorPos = selectionStart();
      m_selectionAnchor = m_cursorPos;
    } else {
      m_cursorPos = prevCharPos(m_value, m_cursorPos);
      if (!shift) {
        m_selectionAnchor = m_cursorPos;
      }
    }
  } else if (sym == XKB_KEY_Right) {
    if (!shift && hasSelection()) {
      // Collapse to end of selection
      m_cursorPos = selectionEnd();
      m_selectionAnchor = m_cursorPos;
    } else {
      m_cursorPos = nextCharPos(m_value, m_cursorPos);
      if (!shift) {
        m_selectionAnchor = m_cursorPos;
      }
    }
  } else if (sym == XKB_KEY_Home) {
    m_cursorPos = 0;
    if (!shift) {
      m_selectionAnchor = 0;
    }
  } else if (sym == XKB_KEY_End) {
    m_cursorPos = m_value.size();
    if (!shift) {
      m_selectionAnchor = m_cursorPos;
    }
  } else if (sym == XKB_KEY_Return) {
    if (m_onSubmit) {
      m_onSubmit(m_value);
    }
  } else if (utf32 >= 0x20U && utf32 != 0x7FU) {
    // Printable character (skip DEL = 0x7F)
    if (hasSelection()) {
      deleteSelection();
      changed = true;
    }
    const auto bytes = utf32ToUtf8(utf32);
    m_value.insert(m_cursorPos, bytes);
    if (preedit) {
      m_preeditStart = m_cursorPos;
      m_preeditLen = bytes.size();
    }
    m_cursorPos += bytes.size();
    m_selectionAnchor = m_cursorPos;
    changed = true;
  }

  updateDisplayText();
  markLayoutDirty();

  if (changed && !preedit && m_onChange) {
    m_onChange(m_value);
  }
}

void Input::applyVisualState() {
  const bool focused = m_inputArea != nullptr && m_inputArea->focused();
  const bool hovered = m_inputArea != nullptr && m_inputArea->hovered();

  const Color fill = focused ? resolved(ColorRole::Surface) : resolved(ColorRole::SurfaceVariant);
  const Color border = focused
                           ? resolved(ColorRole::Primary)
                           : (hovered ? brighten(resolved(ColorRole::Outline), 1.3f) : resolved(ColorRole::Outline));

  m_background->setStyle(RoundedRectStyle{
      .fill = fill,
      .border = border,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });

  auto selectionStyle = m_selectionRect->style();
  selectionStyle.fill = resolved(ColorRole::Primary);
  selectionStyle.fillMode = FillMode::Solid;
  selectionStyle.radius = 2.0f;
  m_selectionRect->setStyle(selectionStyle);

  auto cursorStyle = m_cursor->style();
  cursorStyle.fill = resolved(ColorRole::Primary);
  cursorStyle.fillMode = FillMode::Solid;
  cursorStyle.radius = 1.0f;
  m_cursor->setStyle(cursorStyle);
}

void Input::updateDisplayText() {
  if (m_value.empty() && !m_placeholder.empty()) {
    m_label->setText(m_placeholder);
    m_label->setColor(roleColor(ColorRole::OnSurfaceVariant));
  } else {
    m_label->setText(m_passwordMode ? std::string{} : m_value);
    m_label->setColor(roleColor(ColorRole::OnSurface));
  }
}

void Input::syncPasswordGlyphNodes(std::size_t count) {
  while (m_passwordGlyphs.size() > count) {
    auto* node = m_passwordGlyphs.back();
    (void)removeChild(node);
    m_passwordGlyphs.pop_back();
  }
  while (m_passwordGlyphs.size() < count) {
    auto glyph = std::make_unique<GlyphNode>();
    auto* glyphPtr = static_cast<GlyphNode*>(insertChildAt(3, std::move(glyph)));
    m_passwordGlyphs.push_back(glyphPtr);
  }
}

float Input::measureCursorX(Renderer& renderer) const {
  if (m_cursorPos == 0 || m_value.empty()) {
    return 0.0f;
  }
  return renderer.measureText(m_value.substr(0, m_cursorPos), m_fontSize).width;
}

bool Input::hasSelection() const noexcept { return m_selectionAnchor != m_cursorPos; }

std::size_t Input::selectionStart() const noexcept { return std::min(m_selectionAnchor, m_cursorPos); }

std::size_t Input::selectionEnd() const noexcept { return std::max(m_selectionAnchor, m_cursorPos); }

void Input::deleteSelection() {
  const std::size_t start = selectionStart();
  const std::size_t end = selectionEnd();
  m_value.erase(start, end - start);
  m_cursorPos = start;
  m_selectionAnchor = start;
}

std::size_t Input::xToByteOffset(float localX) const {
  if (m_stopX.empty() || localX <= 0.0f) {
    return 0;
  }
  if (localX >= m_stopX.back()) {
    return m_stopByte.back();
  }
  for (std::size_t i = 1; i < m_stopX.size(); ++i) {
    const float mid = (m_stopX[i - 1] + m_stopX[i]) * 0.5f;
    if (localX < mid) {
      return m_stopByte[i - 1];
    }
  }
  return m_stopByte.back();
}

float Input::stopXForByte(std::size_t bytePos) const {
  for (std::size_t i = 0; i < m_stopByte.size(); ++i) {
    if (m_stopByte[i] == bytePos) {
      return m_stopX[i];
    }
  }
  return m_stopX.empty() ? 0.0f : m_stopX.back();
}

std::size_t Input::nextCharPos(const std::string& s, std::size_t pos) {
  if (pos >= s.size()) {
    return pos;
  }
  ++pos;
  while (pos < s.size() && (static_cast<unsigned char>(s[pos]) & 0xC0U) == 0x80U) {
    ++pos;
  }
  return pos;
}

std::size_t Input::prevCharPos(const std::string& s, std::size_t pos) {
  if (pos == 0) {
    return 0;
  }
  --pos;
  while (pos > 0 && (static_cast<unsigned char>(s[pos]) & 0xC0U) == 0x80U) {
    --pos;
  }
  return pos;
}

std::string Input::utf32ToUtf8(std::uint32_t cp) {
  std::string result;
  if (cp < 0x80U) {
    result += static_cast<char>(cp);
  } else if (cp < 0x800U) {
    result += static_cast<char>(0xC0U | (cp >> 6U));
    result += static_cast<char>(0x80U | (cp & 0x3FU));
  } else if (cp < 0x10000U) {
    result += static_cast<char>(0xE0U | (cp >> 12U));
    result += static_cast<char>(0x80U | ((cp >> 6U) & 0x3FU));
    result += static_cast<char>(0x80U | (cp & 0x3FU));
  } else {
    result += static_cast<char>(0xF0U | (cp >> 18U));
    result += static_cast<char>(0x80U | ((cp >> 12U) & 0x3FU));
    result += static_cast<char>(0x80U | ((cp >> 6U) & 0x3FU));
    result += static_cast<char>(0x80U | (cp & 0x3FU));
  }
  return result;
}

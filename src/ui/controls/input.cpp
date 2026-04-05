#include "ui/controls/input.h"

#include "cursor-shape-v1-client-protocol.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "render/programs/rounded_rect_program.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "render/scene/text_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

namespace {

// XKB keysyms (from xkbcommon/xkbcommon-keysyms.h)
constexpr std::uint32_t kKeyBackspace = 0xFF08;
constexpr std::uint32_t kKeyDelete    = 0xFFFF;
constexpr std::uint32_t kKeyLeft      = 0xFF51;
constexpr std::uint32_t kKeyRight     = 0xFF53;
constexpr std::uint32_t kKeyHome      = 0xFF50;
constexpr std::uint32_t kKeyEnd       = 0xFF57;
constexpr std::uint32_t kKeyReturn    = 0xFF0D;

// Modifier bitmask — must match KeyMod constants in wayland/wayland_seat.h
constexpr std::uint32_t kModShift = 1u << 0;
constexpr std::uint32_t kModCtrl  = 1u << 1;

constexpr float kDefaultWidth = 200.0f;
constexpr float kCursorWidth  = 1.5f;
constexpr float kCursorPadV   = 3.0f;

} // namespace

Input::Input() {
  // 0: background
  auto bg = std::make_unique<RectNode>();
  m_background = static_cast<RectNode*>(addChild(std::move(bg)));

  // 1: selection highlight (rendered behind text)
  auto sel = std::make_unique<RectNode>();
  sel->setStyle(RoundedRectStyle{
      .fill = palette.primary,
      .fillMode = FillMode::Solid,
      .radius = 2.0f,
  });
  sel->setOpacity(0.3f);
  sel->setVisible(false);
  m_selectionRect = static_cast<RectNode*>(addChild(std::move(sel)));

  // 2: text
  auto text = std::make_unique<TextNode>();
  text->setFontSize(Style::fontSizeBody);
  text->setColor(palette.onSurface);
  m_textNode = static_cast<TextNode*>(addChild(std::move(text)));

  // 3: cursor
  auto cursor = std::make_unique<RectNode>();
  cursor->setStyle(RoundedRectStyle{
      .fill = palette.primary,
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
      const std::size_t offset = xToByteOffset(data.localX - Style::paddingH);
      m_cursorPos = offset;
      m_selectionAnchor = offset;
      markDirty();
    }
  });
  area->setOnMotion([this](const InputArea::PointerData& data) {
    if (m_inputArea != nullptr && m_inputArea->pressed()) {
      m_cursorPos = xToByteOffset(data.localX - Style::paddingH);
      markDirty();
    }
  });
  area->setOnKeyDown([this](const InputArea::KeyData& k) { handleKey(k.sym, k.utf32, k.modifiers); });
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

  applyVisualState();
}

void Input::setValue(std::string_view value) {
  m_value = std::string(value);
  m_cursorPos = m_value.size();
  m_selectionAnchor = m_cursorPos;
  updateDisplayText();
  markDirty();
}

void Input::setPlaceholder(std::string_view placeholder) {
  m_placeholder = std::string(placeholder);
  if (m_value.empty()) {
    updateDisplayText();
    markDirty();
  }
}

void Input::setOnChange(std::function<void(const std::string&)> callback) {
  m_onChange = std::move(callback);
}

void Input::setOnSubmit(std::function<void(const std::string&)> callback) {
  m_onSubmit = std::move(callback);
}

void Input::layout(Renderer& renderer) {
  const float w = width() > 0.0f ? width() : kDefaultWidth;
  const float h = Style::controlHeight;
  setSize(w, h);

  // Measure display text for vertical centering
  const std::string& display = m_value.empty() ? m_placeholder : m_value;
  const auto metrics = renderer.measureText(display, Style::fontSizeBody);
  const float textH = metrics.bottom - metrics.top;

  // TextNode renders with baseline at y=0, so offset by -metrics.top
  const float textNodeY = (h - textH) * 0.5f - metrics.top;
  m_textNode->setPosition(Style::paddingH, textNodeY);
  m_textNode->setSize(metrics.width, textH);

  // Build stop arrays for click-to-position and selection rect
  m_stopByte.clear();
  m_stopX.clear();
  m_stopByte.push_back(0);
  m_stopX.push_back(0.0f);
  if (!m_value.empty()) {
    std::size_t pos = 0;
    while (pos < m_value.size()) {
      pos = nextCharPos(m_value, pos);
      m_stopByte.push_back(pos);
      m_stopX.push_back(renderer.measureText(m_value.substr(0, pos), Style::fontSizeBody).width);
    }
  }

  // Cursor
  const float cursorX = Style::paddingH + stopXForByte(m_cursorPos);
  m_cursor->setPosition(cursorX, kCursorPadV);
  m_cursor->setSize(kCursorWidth, h - kCursorPadV * 2.0f);

  // Selection highlight
  if (hasSelection()) {
    const float selX0 = Style::paddingH + stopXForByte(selectionStart());
    const float selX1 = Style::paddingH + stopXForByte(selectionEnd());
    m_selectionRect->setPosition(selX0, kCursorPadV);
    m_selectionRect->setSize(selX1 - selX0, h - kCursorPadV * 2.0f);
    m_selectionRect->setVisible(true);
  } else {
    m_selectionRect->setVisible(false);
  }

  m_background->setPosition(0.0f, 0.0f);
  m_background->setSize(w, h);

  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setSize(w, h);

  applyVisualState();
}

void Input::handleKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers) {
  bool changed = false;
  const bool shift = (modifiers & kModShift) != 0;
  const bool ctrl  = (modifiers & kModCtrl)  != 0;

  if (ctrl && sym == 'a') {
    // Select all
    m_selectionAnchor = 0;
    m_cursorPos = m_value.size();
  } else if (sym == kKeyBackspace) {
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
  } else if (sym == kKeyDelete) {
    if (hasSelection()) {
      deleteSelection();
      changed = true;
    } else if (m_cursorPos < m_value.size()) {
      const std::size_t next = nextCharPos(m_value, m_cursorPos);
      m_value.erase(m_cursorPos, next - m_cursorPos);
      changed = true;
    }
  } else if (sym == kKeyLeft) {
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
  } else if (sym == kKeyRight) {
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
  } else if (sym == kKeyHome) {
    m_cursorPos = 0;
    if (!shift) {
      m_selectionAnchor = 0;
    }
  } else if (sym == kKeyEnd) {
    m_cursorPos = m_value.size();
    if (!shift) {
      m_selectionAnchor = m_cursorPos;
    }
  } else if (sym == kKeyReturn) {
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
    m_cursorPos += bytes.size();
    m_selectionAnchor = m_cursorPos;
    changed = true;
  }

  updateDisplayText();
  markDirty();

  if (changed && m_onChange) {
    m_onChange(m_value);
  }
}

void Input::applyVisualState() {
  const bool focused = m_inputArea != nullptr && m_inputArea->focused();
  const bool hovered = m_inputArea != nullptr && m_inputArea->hovered();

  const Color fill   = focused ? palette.surface : palette.surfaceVariant;
  const Color border = focused ? palette.primary
                               : (hovered ? brighten(palette.outline, 1.3f) : palette.outline);

  m_background->setStyle(RoundedRectStyle{
      .fill = fill,
      .border = border,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });
}

void Input::updateDisplayText() {
  if (m_value.empty() && !m_placeholder.empty()) {
    m_textNode->setText(m_placeholder);
    m_textNode->setColor(palette.onSurfaceVariant);
  } else {
    m_textNode->setText(m_value);
    m_textNode->setColor(palette.onSurface);
  }
}

float Input::measureCursorX(Renderer& renderer) const {
  if (m_cursorPos == 0 || m_value.empty()) {
    return 0.0f;
  }
  return renderer.measureText(m_value.substr(0, m_cursorPos), Style::fontSizeBody).width;
}

bool Input::hasSelection() const noexcept { return m_selectionAnchor != m_cursorPos; }

std::size_t Input::selectionStart() const noexcept { return std::min(m_selectionAnchor, m_cursorPos); }

std::size_t Input::selectionEnd() const noexcept { return std::max(m_selectionAnchor, m_cursorPos); }

void Input::deleteSelection() {
  const std::size_t start = selectionStart();
  const std::size_t end   = selectionEnd();
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

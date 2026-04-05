#include "ui/controls/input.h"

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

constexpr float kDefaultWidth = 200.0f;
constexpr float kCursorWidth  = 1.5f;
constexpr float kCursorPadV   = 3.0f;

} // namespace

Input::Input() {
  auto bg = std::make_unique<RectNode>();
  m_background = static_cast<RectNode*>(addChild(std::move(bg)));

  auto text = std::make_unique<TextNode>();
  text->setFontSize(Style::fontSizeBody);
  text->setColor(palette.onSurface);
  m_textNode = static_cast<TextNode*>(addChild(std::move(text)));

  auto cursor = std::make_unique<RectNode>();
  cursor->setStyle(RoundedRectStyle{
      .fill = palette.primary,
      .fillMode = FillMode::Solid,
      .radius = 1.0f,
  });
  cursor->setVisible(false);
  m_cursor = static_cast<RectNode*>(addChild(std::move(cursor)));

  auto area = std::make_unique<InputArea>();
  area->setFocusable(true);
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
  area->setOnKeyDown([this](const InputArea::KeyData& k) { handleKey(k.sym, k.utf32, k.modifiers); });
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

  applyVisualState();
}

void Input::setValue(std::string_view value) {
  m_value = std::string(value);
  m_cursorPos = m_value.size();
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

  // textNodeY positions the TextNode so its glyphs are vertically centered in the control.
  // TextNode renders with baseline at y=0, so we offset by -metrics.top (which is positive
  // when metrics.top is negative, i.e. text ascends above the baseline).
  const float textNodeY = (h - textH) * 0.5f - metrics.top;
  m_textNode->setPosition(Style::paddingH, textNodeY);
  m_textNode->setSize(metrics.width, textH);

  // Cursor: measure text up to cursor byte position to find X
  const float cursorX = Style::paddingH + measureCursorX(renderer);
  m_cursor->setPosition(cursorX, kCursorPadV);
  m_cursor->setSize(kCursorWidth, h - kCursorPadV * 2.0f);

  m_background->setPosition(0.0f, 0.0f);
  m_background->setSize(w, h);

  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setSize(w, h);

  applyVisualState();
}

void Input::handleKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t /*modifiers*/) {
  bool changed = false;

  if (sym == kKeyBackspace) {
    if (m_cursorPos > 0) {
      const std::size_t prev = prevCharPos(m_value, m_cursorPos);
      m_value.erase(prev, m_cursorPos - prev);
      m_cursorPos = prev;
      changed = true;
    }
  } else if (sym == kKeyDelete) {
    if (m_cursorPos < m_value.size()) {
      const std::size_t next = nextCharPos(m_value, m_cursorPos);
      m_value.erase(m_cursorPos, next - m_cursorPos);
      changed = true;
    }
  } else if (sym == kKeyLeft) {
    m_cursorPos = prevCharPos(m_value, m_cursorPos);
  } else if (sym == kKeyRight) {
    m_cursorPos = nextCharPos(m_value, m_cursorPos);
  } else if (sym == kKeyHome) {
    m_cursorPos = 0;
  } else if (sym == kKeyEnd) {
    m_cursorPos = m_value.size();
  } else if (sym == kKeyReturn) {
    if (m_onSubmit) {
      m_onSubmit(m_value);
    }
  } else if (utf32 >= 0x20U && utf32 != 0x7FU) {
    // Printable character (skip DEL = 0x7F)
    const auto bytes = utf32ToUtf8(utf32);
    m_value.insert(m_cursorPos, bytes);
    m_cursorPos += bytes.size();
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

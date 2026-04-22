#include "shell/bar/widgets/scripted_widget.h"

#include "core/log.h"
#include "cursor-shape-v1-client-protocol.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "scripting/luau_host.h"
#include "scripting/scripted_widget_bindings.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cstdlib>
#include <fstream>
#include <linux/input-event-codes.h>
#include <sstream>

namespace {
  constexpr Logger kLog("scripted-widget");

  std::string expandPath(const std::string& path) {
    if (path.empty() || path[0] != '~')
      return path;
    const char* home = std::getenv("HOME");
    if (!home)
      return path;
    return std::string(home) + path.substr(1);
  }

  std::string readFile(const std::string& path) {
    std::ifstream f(expandPath(path));
    if (!f)
      return {};
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
  }
} // namespace

ScriptedWidget::ScriptedWidget(std::string scriptPath, const WidgetConfig* config)
    : m_scriptPath(std::move(scriptPath)) {
  if (config)
    m_settings = config->settings;
}
ScriptedWidget::~ScriptedWidget() = default;

void ScriptedWidget::create() {
  m_host = std::make_unique<LuauHost>();

  auto area = std::make_unique<InputArea>();
  area->setAcceptedButtons(BTN_LEFT | BTN_RIGHT | BTN_MIDDLE);
  area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  area->setOnClick([this](const InputArea::PointerData& data) {
    if (!m_host)
      return;
    const char* fn = nullptr;
    switch (data.button) {
    case BTN_LEFT:
      fn = "onClick";
      break;
    case BTN_RIGHT:
      fn = "onRightClick";
      break;
    case BTN_MIDDLE:
      fn = "onMiddleClick";
      break;
    default:
      return;
    }
    m_host->callGlobal(fn);
    requestUpdate();
  });
  area->setOnEnter([this](const InputArea::PointerData&) {
    if (m_host)
      m_host->callGlobalWithBool("onHover", true);
    requestUpdate();
  });
  area->setOnLeave([this]() {
    if (m_host)
      m_host->callGlobalWithBool("onHover", false);
    requestUpdate();
  });

  auto flex = std::make_unique<Flex>();
  flex->setDirection(FlexDirection::Horizontal);
  flex->setAlign(FlexAlign::Center);
  flex->setGap(Style::spaceXs);

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setVisible(false);
  m_glyph = glyph.get();

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setStableBaseline(true);
  m_label = label.get();

  flex->addChild(std::move(glyph));
  flex->addChild(std::move(label));
  m_flex = flex.get();

  area->addChild(std::move(flex));
  m_area = area.get();
  setRoot(std::move(area));

  registerScriptedWidgetBindings(m_host->state(), this);

  if (m_scriptPath.empty()) {
    kLog.warn("scripted widget: no script path");
    return;
  }
  std::string source = readFile(m_scriptPath);
  if (source.empty()) {
    kLog.warn("scripted widget: failed to read '{}'", m_scriptPath);
    return;
  }
  m_host->exec(m_scriptPath, source);
  m_host->callGlobal("update");
}

void ScriptedWidget::onFrameTick(float deltaMs) {
  m_accumMs += deltaMs;
  if (m_accumMs >= 250.0f) {
    m_accumMs = 0.0f;
    if (m_host)
      m_host->callGlobal("update");
    requestRedraw();
  }
}

void ScriptedWidget::doLayout(Renderer& renderer, float, float) {
  if (!m_flex)
    return;

  auto textColor = m_textColorRole ? roleColor(*m_textColorRole) : widgetForegroundOr(roleColor(ColorRole::OnSurface));
  m_label->setColor(textColor);
  m_label->measure(renderer);

  if (m_glyphVisible) {
    auto glyphColor =
        m_glyphColorRole ? roleColor(*m_glyphColorRole) : widgetForegroundOr(roleColor(ColorRole::OnSurface));
    m_glyph->setColor(glyphColor);
    m_glyph->measure(renderer);
  }

  m_flex->layout(renderer);

  if (m_area)
    m_area->setSize(m_flex->width(), m_flex->height());
}

void ScriptedWidget::doUpdate(Renderer&) {}

void ScriptedWidget::luaSetText(std::string_view text) {
  if (m_label)
    m_label->setText(std::string(text));
}

void ScriptedWidget::luaSetGlyph(std::string_view name) {
  if (!m_glyph)
    return;
  m_glyph->setGlyph(name);
  m_glyph->setVisible(true);
  m_glyphVisible = true;
}

void ScriptedWidget::luaSetGlyphCodepoint(char32_t codepoint) {
  if (!m_glyph)
    return;
  m_glyph->setCodepoint(codepoint);
  m_glyph->setVisible(true);
  m_glyphVisible = true;
}

void ScriptedWidget::luaSetColor(std::string_view role) { m_textColorRole = parseColorRole(role); }

void ScriptedWidget::luaSetGlyphColor(std::string_view role) { m_glyphColorRole = parseColorRole(role); }

void ScriptedWidget::luaSetVisible(bool visible) {
  if (auto* node = root(); node)
    node->setVisible(visible);
  requestRedraw();
}

std::optional<ColorRole> ScriptedWidget::parseColorRole(std::string_view name) {
  if (name == "primary")
    return ColorRole::Primary;
  if (name == "on_primary")
    return ColorRole::OnPrimary;
  if (name == "secondary")
    return ColorRole::Secondary;
  if (name == "on_secondary")
    return ColorRole::OnSecondary;
  if (name == "tertiary")
    return ColorRole::Tertiary;
  if (name == "on_tertiary")
    return ColorRole::OnTertiary;
  if (name == "error")
    return ColorRole::Error;
  if (name == "on_error")
    return ColorRole::OnError;
  if (name == "surface")
    return ColorRole::Surface;
  if (name == "on_surface")
    return ColorRole::OnSurface;
  if (name == "surface_variant")
    return ColorRole::SurfaceVariant;
  if (name == "on_surface_variant")
    return ColorRole::OnSurfaceVariant;
  if (name == "outline")
    return ColorRole::Outline;
  if (name == "shadow")
    return ColorRole::Shadow;
  if (name == "hover")
    return ColorRole::Hover;
  if (name == "on_hover")
    return ColorRole::OnHover;
  return std::nullopt;
}

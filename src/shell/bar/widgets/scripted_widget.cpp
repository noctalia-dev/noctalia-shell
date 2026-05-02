#include "shell/bar/widgets/scripted_widget.h"

#include "core/log.h"
#include "core/resource_paths.h"
#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "notification/notifications.h"
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

  std::filesystem::path resolveScriptPath(const std::string& path) {
    if (path.empty())
      return {};
    if (path[0] == '~') {
      const char* home = std::getenv("HOME");
      if (home)
        return std::string(home) + path.substr(1);
      return path;
    }
    if (path[0] == '/')
      return path;
    return paths::assetPath(path);
  }

  std::string readFile(const std::filesystem::path& path) {
    std::ifstream f(path);
    if (!f)
      return {};
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
  }
} // namespace

ScriptedWidget::ScriptedWidget(std::string scriptPath, const WidgetConfig* config, FileWatcher* fileWatcher)
    : m_scriptPath(std::move(scriptPath)), m_fileWatcher(fileWatcher) {
  if (config) {
    m_settings = config->settings;
    m_hotReload = config->getBool("hot_reload", false);
  }
}

ScriptedWidget::~ScriptedWidget() { teardownScriptWatch(); }

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
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setVisible(false);
  m_glyph = glyph.get();

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setStableBaseline(true);
  label->setVisible(false);
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
  m_resolvedPath = resolveScriptPath(m_scriptPath);
  std::string source = readFile(m_resolvedPath);
  if (source.empty()) {
    kLog.warn("scripted widget: failed to read '{}'", m_resolvedPath.string());
    return;
  }
  m_host->exec(m_resolvedPath.string(), source);
  m_host->callGlobal("update");
  startUpdateTimer();

  if (m_hotReload)
    setupScriptWatch();
}

void ScriptedWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  m_isVertical = containerHeight > containerWidth;
  if (!m_flex)
    return;

  auto textColor = m_textColorRole ? colorSpecFromRole(*m_textColorRole)
                                   : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface));
  m_label->setColor(textColor);
  m_label->setVisible(!m_label->text().empty());
  if (m_label->visible()) {
    m_label->measure(renderer);
  }

  if (m_glyphVisible) {
    auto glyphColor = m_glyphColorRole ? colorSpecFromRole(*m_glyphColorRole)
                                       : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface));
    m_glyph->setColor(glyphColor);
    m_glyph->measure(renderer);
  }

  m_flex->layout(renderer);

  if (m_area)
    m_area->setSize(m_flex->width(), m_flex->height());
}

void ScriptedWidget::doUpdate(Renderer&) {}

void ScriptedWidget::luaSetText(std::string_view text) {
  if (!m_label)
    return;
  bool changed = m_label->setText(text);
  bool vis = !text.empty();
  if (m_label->visible() != vis) {
    m_label->setVisible(vis);
    changed = true;
  }
  m_dirty |= changed;
}

void ScriptedWidget::luaSetGlyph(std::string_view name) {
  if (!m_glyph)
    return;
  bool changed = m_glyph->setGlyph(name);
  if (!m_glyphVisible) {
    m_glyph->setVisible(true);
    m_glyphVisible = true;
    changed = true;
  }
  m_dirty |= changed;
}

void ScriptedWidget::luaSetGlyphCodepoint(char32_t codepoint) {
  if (!m_glyph)
    return;
  bool changed = m_glyph->setCodepoint(codepoint);
  if (!m_glyphVisible) {
    m_glyph->setVisible(true);
    m_glyphVisible = true;
    changed = true;
  }
  m_dirty |= changed;
}

void ScriptedWidget::luaSetColor(std::string_view role) {
  auto parsed = colorRoleFromToken(role);
  if (parsed != m_textColorRole) {
    m_textColorRole = parsed;
    m_dirty = true;
  }
}

void ScriptedWidget::luaSetGlyphColor(std::string_view role) {
  auto parsed = colorRoleFromToken(role);
  if (parsed != m_glyphColorRole) {
    m_glyphColorRole = parsed;
    m_dirty = true;
  }
}

void ScriptedWidget::luaSetUpdateInterval(float ms) {
  m_updateIntervalMs = std::max(16, static_cast<int>(ms));
  startUpdateTimer();
}

void ScriptedWidget::luaSetVisible(bool visible) {
  auto* node = root();
  if (!node || node->visible() == visible)
    return;
  node->setVisible(visible);
  m_dirty = true;
}

void ScriptedWidget::startUpdateTimer() {
  m_updateTimer.startRepeating(std::chrono::milliseconds(m_updateIntervalMs), [this] {
    m_dirty = false;
    if (m_host)
      m_host->callGlobal("update");
    if (m_dirty)
      requestUpdate();
  });
}

void ScriptedWidget::setupScriptWatch() {
  if (m_resolvedPath.empty() || !m_fileWatcher)
    return;
  m_watchId = m_fileWatcher->watch(m_resolvedPath, [this] { reloadScript(); });
}

void ScriptedWidget::teardownScriptWatch() {
  if (m_watchId == 0 || !m_fileWatcher)
    return;
  m_fileWatcher->unwatch(m_watchId);
  m_watchId = 0;
}

void ScriptedWidget::reloadScript() {
  m_updateTimer.stop();
  m_glyphVisible = false;
  m_textColorRole = std::nullopt;
  m_glyphColorRole = std::nullopt;
  m_updateIntervalMs = 250;
  if (m_glyph)
    m_glyph->setVisible(false);
  if (m_label) {
    m_label->setText("");
    m_label->setVisible(false);
  }

  m_host = std::make_unique<LuauHost>();
  registerScriptedWidgetBindings(m_host->state(), this);

  std::string source = readFile(m_resolvedPath);
  auto name = m_resolvedPath.filename().string();
  if (source.empty() || !m_host->exec(m_resolvedPath.string(), source)) {
    kLog.warn("hot reload: failed to reload '{}'", name);
    notify::error("Noctalia", i18n::tr("bar.widgets.scripted.reload-failed"), name);
    requestRedraw();
    return;
  }

  m_host->callGlobal("update");
  startUpdateTimer();
  requestRedraw();
  kLog.info("hot reload: reloaded '{}'", name);
  notify::info("Noctalia", i18n::tr("bar.widgets.scripted.reloaded"), name);
}

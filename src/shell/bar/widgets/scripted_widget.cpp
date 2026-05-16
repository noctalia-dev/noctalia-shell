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

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <linux/input-event-codes.h>
#include <sstream>

namespace {
  constexpr Logger kLog("scripted-widget");
  constexpr std::chrono::milliseconds kDeferredUpdateRetry{50};
  constexpr std::chrono::milliseconds kTimerPhaseStep{50};
  constexpr std::chrono::milliseconds kTimerMaxPhase{500};

  std::uint32_t nextTimerPhase() {
    static std::atomic<std::uint32_t> next{0};
    return next.fetch_add(1, std::memory_order_relaxed);
  }

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
    : m_scriptPath(std::move(scriptPath)), m_fileWatcher(fileWatcher), m_timerPhase(nextTimerPhase()) {
  if (config) {
    m_settings = config->settings;
    m_hotReload = config->getBool("hot_reload", false);
  }
}

ScriptedWidget::~ScriptedWidget() { teardownScriptWatch(); }

void ScriptedWidget::create() {
  m_host = std::make_unique<LuauHost>();

  auto area = std::make_unique<InputArea>();
  area->setAcceptedButtons(InputArea::buttonMask({BTN_LEFT, BTN_RIGHT, BTN_MIDDLE}));
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

  m_label->setColor(resolveScriptColor(m_textColor));
  m_label->setVisible(!m_label->text().empty());
  if (m_label->visible()) {
    m_label->measure(renderer);
  }

  if (m_glyphVisible) {
    m_glyph->setColor(resolveScriptColor(m_glyphColor));
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

void ScriptedWidget::luaSetColor(std::string_view role, std::string_view mode) {
  ScriptColorState next{.role = colorRoleFromToken(role), .mode = scriptColorModeFromToken(mode)};
  if (!next.role.has_value()) {
    next.mode = ScriptColorMode::Auto;
  }
  if (next != m_textColor) {
    m_textColor = next;
    m_dirty = true;
  }
}

void ScriptedWidget::luaSetGlyphColor(std::string_view role, std::string_view mode) {
  ScriptColorState next{.role = colorRoleFromToken(role), .mode = scriptColorModeFromToken(mode)};
  if (!next.role.has_value()) {
    next.mode = ScriptColorMode::Auto;
  }
  if (next != m_glyphColor) {
    m_glyphColor = next;
    m_dirty = true;
  }
}

void ScriptedWidget::luaSetUpdateInterval(float ms) {
  m_updateIntervalMs = std::max(16, static_cast<int>(ms));
  startUpdateTimer();
}

void ScriptedWidget::setUpdateDeferralCallback(std::function<bool()> callback) {
  m_updateDeferralCallback = std::move(callback);
}

void ScriptedWidget::luaSetVisible(bool visible) {
  auto* node = root();
  if (!node || node->visible() == visible)
    return;
  node->setVisible(visible);
  m_dirty = true;
}

ScriptedWidget::IpcDispatchResult ScriptedWidget::dispatchIpcEvent(std::string_view event, std::string_view payload) {
  if (!m_host) {
    return IpcDispatchResult::MissingHost;
  }
  if (!m_host->hasGlobal("onIpc")) {
    return IpcDispatchResult::MissingCallback;
  }
  if (!m_host->callGlobalWithStrings("onIpc", event, payload)) {
    return IpcDispatchResult::Failed;
  }
  requestUpdate();
  return IpcDispatchResult::Handled;
}

ColorSpec ScriptedWidget::resolveScriptColor(const ScriptColorState& state) const noexcept {
  if (m_widgetForeground.has_value()) {
    return *m_widgetForeground;
  }
  const ColorSpec fallback = colorSpecFromRole(ColorRole::OnSurface);
  if (!state.role.has_value()) {
    return widgetForegroundOr(fallback);
  }
  if (state.mode == ScriptColorMode::Script || *state.role != ColorRole::OnSurface) {
    return colorSpecFromRole(*state.role);
  }
  return widgetForegroundOr(fallback);
}

ScriptedWidget::ScriptColorMode ScriptedWidget::scriptColorModeFromToken(std::string_view token) noexcept {
  return token == "script" ? ScriptColorMode::Script : ScriptColorMode::Auto;
}

void ScriptedWidget::startUpdateTimer() {
  ++m_updateTimerGeneration;
  m_updateDeferred = false;
  m_deferredUpdateTimer.stop();

  const auto interval = std::chrono::milliseconds(m_updateIntervalMs);
  const auto generation = m_updateTimerGeneration;
  m_updateTimer.start(initialUpdateDelay(interval), [this, generation, interval] {
    if (m_updateTimerGeneration != generation) {
      return;
    }
    handleUpdateTimer();
    if (m_updateTimerGeneration != generation) {
      return;
    }
    m_updateTimer.startRepeating(interval, [this, generation] {
      if (m_updateTimerGeneration == generation) {
        handleUpdateTimer();
      }
    });
  });
}

void ScriptedWidget::handleUpdateTimer() {
  if (shouldDeferUpdate()) {
    scheduleDeferredUpdate();
    return;
  }
  runScriptUpdate();
}

void ScriptedWidget::scheduleDeferredUpdate() {
  m_updateDeferred = true;
  if (m_deferredUpdateTimer.active()) {
    return;
  }
  armDeferredUpdate(m_updateTimerGeneration);
}

void ScriptedWidget::armDeferredUpdate(std::uint64_t generation) {
  m_deferredUpdateTimer.start(kDeferredUpdateRetry, [this, generation] {
    if (m_updateTimerGeneration != generation || !m_updateDeferred) {
      return;
    }
    if (shouldDeferUpdate()) {
      armDeferredUpdate(generation);
      return;
    }

    m_updateDeferred = false;
    runScriptUpdate();
    if (m_updateTimerGeneration == generation) {
      startUpdateTimer();
    }
  });
}

std::chrono::milliseconds ScriptedWidget::initialUpdateDelay(std::chrono::milliseconds interval) const noexcept {
  if (interval <= std::chrono::milliseconds(1)) {
    return interval;
  }

  const auto maxPhase = std::min({interval / 2, kTimerMaxPhase, interval - std::chrono::milliseconds(1)});
  const auto maxPhaseMs = maxPhase.count();
  if (maxPhaseMs <= 0) {
    return interval;
  }

  const auto phaseMs = (static_cast<std::int64_t>(m_timerPhase) * kTimerPhaseStep.count()) % (maxPhaseMs + 1);
  return interval + std::chrono::milliseconds(phaseMs);
}

void ScriptedWidget::runScriptUpdate() {
  m_dirty = false;
  if (m_host) {
    m_host->callGlobal("update");
  }
  if (m_dirty) {
    requestUpdate();
  }
}

bool ScriptedWidget::shouldDeferUpdate() const { return m_updateDeferralCallback && m_updateDeferralCallback(); }

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
  m_textColor = {};
  m_glyphColor = {};
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

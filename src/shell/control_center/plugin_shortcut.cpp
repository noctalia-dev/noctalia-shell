#include "shell/control_center/plugin_shortcut.h"

#include "core/log.h"
#include "shell/panel/panel_manager.h"

#include <algorithm>
#include <chrono>
#include <fstream>
#include <sstream>
#include <utility>

namespace {
  constexpr Logger kLog("plugin-shortcut");

  std::string readFile(const std::filesystem::path& path) {
    std::ifstream file(path);
    if (!file) {
      return {};
    }
    std::stringstream ss;
    ss << file.rdbuf();
    return ss.str();
  }
} // namespace

PluginShortcut::PluginShortcut(
    std::string entryId, std::filesystem::path sourcePath, std::unordered_map<std::string, WidgetSettingValue> settings,
    scripting::ScriptApiContext& scriptApi, HttpClient* httpClient, ClipboardService* clipboard
)
    : m_entryId(std::move(entryId)), m_sourcePath(std::move(sourcePath)), m_pluginDir(m_sourcePath.parent_path()),
      m_scriptApi(scriptApi), m_httpClient(httpClient), m_clipboard(clipboard) {
  start(std::move(settings));
}

PluginShortcut::~PluginShortcut() {
  if (m_alive) {
    *m_alive = false;
  }
  if (m_runtime != nullptr) {
    if (m_subscription != 0) {
      m_runtime->unsubscribe(m_subscription);
    }
    m_runtime->stop();
  }
}

void PluginShortcut::start(std::unordered_map<std::string, WidgetSettingValue> settings) {
  std::string code = readFile(m_sourcePath);
  if (code.empty()) {
    kLog.warn("shortcut '{}': empty or unreadable source {}", m_entryId, m_sourcePath.string());
    return;
  }
  m_runtime = std::make_shared<scripting::ScriptRuntime>(
      m_entryId, std::move(settings), m_scriptApi, m_pluginDir, m_httpClient, m_clipboard
  );

  auto alive = std::weak_ptr<bool>(m_alive);
  m_subscription = m_runtime->subscribe([this, alive](const scripting::ScriptResult& result) {
    auto token = alive.lock();
    if (token == nullptr || !*token) {
      return;
    }
    handleResult(result);
  });

  m_runtime->start(m_sourcePath.string(), std::move(code), {});
  armTimer();
}

void PluginShortcut::handleResult(const scripting::ScriptResult& result) {
  const auto& patch = result.patch;
  bool changed = false;
  if (patch.label.has_value() && *patch.label != m_label) {
    m_label = *patch.label;
    changed = true;
  }
  if (patch.iconOn.has_value() && *patch.iconOn != m_iconOn) {
    m_iconOn = *patch.iconOn;
    changed = true;
  }
  if (patch.iconOff.has_value() && *patch.iconOff != m_iconOff) {
    m_iconOff = *patch.iconOff;
    changed = true;
  }
  if (patch.active.has_value() && *patch.active != m_active) {
    m_active = *patch.active;
    changed = true;
  }
  if (patch.enabled.has_value() && *patch.enabled != m_enabled) {
    m_enabled = *patch.enabled;
    changed = true;
  }
  if (patch.updateIntervalMs.has_value()) {
    const int next = std::max(16, *patch.updateIntervalMs);
    if (next != m_updateIntervalMs) {
      m_updateIntervalMs = next;
      armTimer();
    }
  }
  if (changed) {
    // The control center polls our state each update pass; kick one.
    PanelManager::instance().refresh();
  }
}

void PluginShortcut::armTimer() {
  m_updateTimer.stop();
  auto alive = std::weak_ptr<bool>(m_alive);
  m_updateTimer.startRepeating(std::chrono::milliseconds(m_updateIntervalMs), [this, alive] {
    auto token = alive.lock();
    if (token != nullptr && *token && m_runtime != nullptr) {
      (void)m_runtime->enqueueUpdate({});
    }
  });
}

void PluginShortcut::onClick() {
  if (m_runtime != nullptr) {
    (void)m_runtime->enqueueCall("onClick", {});
  }
}

void PluginShortcut::onRightClick() {
  if (m_runtime != nullptr) {
    (void)m_runtime->enqueueCall("onRightClick", {});
  }
}

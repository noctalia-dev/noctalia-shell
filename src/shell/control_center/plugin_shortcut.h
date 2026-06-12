#pragma once

#include "config/config_types.h"
#include "core/timer_manager.h"
#include "scripting/script_runtime.h"
#include "shell/control_center/shortcut_registry.h"

#include <filesystem>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>

class HttpClient;
class ClipboardService;
namespace scripting {
  class ScriptApiContext;
}

// A control-center shortcut backed by a plugin's [[shortcut]] entry. The native
// Shortcut interface is polled, so the latest label/icon/active/enabled patch is
// cached and a redraw is kicked when it changes. Lives for the panel's open span
// (created in HomeTab::create, destroyed on close), so its runtime restarts each
// time the control center is opened.
class PluginShortcut : public Shortcut {
public:
  PluginShortcut(
      std::string entryId, std::filesystem::path sourcePath,
      std::unordered_map<std::string, WidgetSettingValue> settings, scripting::ScriptApiContext& scriptApi,
      HttpClient* httpClient, ClipboardService* clipboard
  );
  ~PluginShortcut() override;

  [[nodiscard]] std::string_view id() const override { return m_entryId; }
  [[nodiscard]] std::string defaultLabel() const override { return m_label.empty() ? m_entryId : m_label; }
  [[nodiscard]] std::string displayLabel() const override { return m_label.empty() ? m_entryId : m_label; }
  [[nodiscard]] std::string_view iconOn() const override { return m_iconOn; }
  [[nodiscard]] std::string_view iconOff() const override { return m_iconOff; }
  [[nodiscard]] bool isToggle() const override { return true; }
  [[nodiscard]] bool enabled() const override { return m_enabled; }
  [[nodiscard]] bool active() const override { return m_active; }
  void onClick() override;
  void onRightClick() override;

private:
  void start(std::unordered_map<std::string, WidgetSettingValue> settings);
  void handleResult(const scripting::ScriptResult& result);
  void armTimer();

  std::string m_entryId;
  std::filesystem::path m_sourcePath;
  std::filesystem::path m_pluginDir;
  scripting::ScriptApiContext& m_scriptApi;
  HttpClient* m_httpClient = nullptr;
  ClipboardService* m_clipboard = nullptr;
  std::shared_ptr<scripting::ScriptRuntime> m_runtime;
  scripting::ScriptRuntime::SubscriberId m_subscription = 0;
  std::string m_label;
  std::string m_iconOn = "circle";
  std::string m_iconOff = "circle";
  bool m_active = false;
  bool m_enabled = true;
  Timer m_updateTimer;
  int m_updateIntervalMs = 1000;
  std::shared_ptr<bool> m_alive = std::make_shared<bool>(true);
};

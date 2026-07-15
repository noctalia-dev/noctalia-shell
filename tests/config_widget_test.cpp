#include "config/widget_config.h"
#include "core/toml.h"

#include <print>
#include <string>
#include <variant>

namespace {

  bool expect(bool condition, const char* message) {
    if (!condition) {
      std::println(stderr, "config_widget_test: FAIL: {}", message);
      return false;
    }
    return true;
  }

  bool expectStringSetting(const WidgetConfig& widget, const std::string& key, const std::string& expected) {
    const auto it = widget.settings.find(key);
    if (it == widget.settings.end()) {
      std::println(stderr, "config_widget_test: FAIL: missing setting '{}'", key);
      return false;
    }
    const auto* actual = std::get_if<std::string>(&it->second);
    if (actual == nullptr || *actual != expected) {
      std::println(stderr, "config_widget_test: FAIL: setting '{}': expected '{}'", key, expected);
      return false;
    }
    return true;
  }

  bool expectBoolSetting(const WidgetConfig& widget, const std::string& key, bool expected) {
    const auto it = widget.settings.find(key);
    if (it == widget.settings.end()) {
      std::println(stderr, "config_widget_test: FAIL: missing setting '{}'", key);
      return false;
    }
    const auto* actual = std::get_if<bool>(&it->second);
    if (actual == nullptr || *actual != expected) {
      std::println(stderr, "config_widget_test: FAIL: setting '{}': expected {}", key, expected);
      return false;
    }
    return true;
  }

  bool expectStringMapEntry(
      const WidgetConfig& widget, const std::string& tableKey, const std::string& key, const std::string& expected
  ) {
    const auto tableIt = widget.tables.find(tableKey);
    if (tableIt == widget.tables.end()) {
      std::println(stderr, "config_widget_test: FAIL: missing table '{}'", tableKey);
      return false;
    }
    const auto valueIt = tableIt->second.find(key);
    if (valueIt == tableIt->second.end() || valueIt->second != expected) {
      std::println(stderr, "config_widget_test: FAIL: table '{}.{}': expected '{}'", tableKey, key, expected);
      return false;
    }
    return true;
  }

} // namespace

int main() {
  bool ok = true;

  Config base;
  noctalia::config::seedBuiltinWidgets(base);

  const auto parsed = toml::parse("[widget.temp]\nshow_label = false\n");
  const auto* widgetRoot = parsed["widget"].as_table();
  const auto* tempTable = widgetRoot != nullptr ? (*widgetRoot)["temp"].as_table() : nullptr;
  if (!expect(tempTable != nullptr, "parsed widget.temp table")) {
    return 1;
  }

  const WidgetConfig temp = noctalia::config::readBarWidgetConfig("temp", *tempTable, base);
  ok = expect(temp.type == "sysmon", "temp resolves to sysmon") && ok;
  ok = expectStringSetting(temp, "stat", "cpu_temp") && ok;
  ok = expectBoolSetting(temp, "show_label", false) && ok;

  const auto customParsed = toml::parse("[widget.my_clock]\nformat = \"{:%H:%M}\"\n");
  const auto* customRoot = customParsed["widget"].as_table();
  const auto* customTable = customRoot != nullptr ? (*customRoot)["my_clock"].as_table() : nullptr;
  if (!expect(customTable != nullptr, "parsed widget.my_clock table")) {
    return 1;
  }

  const WidgetConfig custom = noctalia::config::readBarWidgetConfig("my_clock", *customTable, base);
  ok = expect(custom.type == "my_clock", "unknown widget name resolves to its own type") && ok;
  ok = expectStringSetting(custom, "format", "{:%H:%M}") && ok;

  const auto layoutParsed = toml::parse(
      "[widget.keyboard_layout]\n"
      "show_label = true\n"
      "[widget.keyboard_layout.custom_labels]\n"
      "\"English (US)\" = \"EN\"\n"
  );
  const auto* layoutRoot = layoutParsed["widget"].as_table();
  const auto* layoutTable = layoutRoot != nullptr ? (*layoutRoot)["keyboard_layout"].as_table() : nullptr;
  if (!expect(layoutTable != nullptr, "parsed widget.keyboard_layout table")) {
    return 1;
  }

  const WidgetConfig layout = noctalia::config::readBarWidgetConfig("keyboard_layout", *layoutTable, base);
  ok = expect(layout.type == "keyboard_layout", "keyboard_layout keeps builtin type") && ok;
  ok = expectBoolSetting(layout, "hide_when_single_layout", false) && ok;
  ok = expectStringMapEntry(layout, "custom_labels", "English (US)", "EN") && ok;

  BarConfig bar;
  bar.widgetCapsuleRadius = 12.0;
  WidgetConfig launcher;
  launcher.settings["capsule"] = true;
  launcher.settings["capsule_radius"] = std::string("auto");
  const WidgetBarCapsuleSpec automaticCapsule = resolveWidgetBarCapsuleSpec(bar, &launcher);
  ok = expect(automaticCapsule.enabled, "launcher capsule is enabled with an automatic radius") && ok;
  ok = expect(
           automaticCapsule.radius.has_value() && *automaticCapsule.radius == 12.0f,
           "automatic widget capsule radius keeps the bar radius"
       )
      && ok;

  launcher.settings["capsule_radius"] = 7.0;
  const WidgetBarCapsuleSpec explicitCapsule = resolveWidgetBarCapsuleSpec(bar, &launcher);
  ok = expect(
           explicitCapsule.radius.has_value() && *explicitCapsule.radius == 7.0f,
           "numeric widget capsule radius overrides the bar radius"
       )
      && ok;

  return ok ? 0 : 1;
}

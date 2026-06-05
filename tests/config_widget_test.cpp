#include "config/widget_config.h"
#include "core/toml.h"

#include <cstdio>
#include <string>
#include <variant>

namespace {

  bool expect(bool condition, const char* message) {
    if (!condition) {
      std::fprintf(stderr, "config_widget_test: FAIL: %s\n", message);
      return false;
    }
    return true;
  }

  bool expectStringSetting(const WidgetConfig& widget, const std::string& key, const std::string& expected) {
    const auto it = widget.settings.find(key);
    if (it == widget.settings.end()) {
      std::fprintf(stderr, "config_widget_test: FAIL: missing setting '%s'\n", key.c_str());
      return false;
    }
    const auto* actual = std::get_if<std::string>(&it->second);
    if (actual == nullptr || *actual != expected) {
      std::fprintf(stderr, "config_widget_test: FAIL: setting '%s': expected '%s'\n", key.c_str(), expected.c_str());
      return false;
    }
    return true;
  }

  bool expectBoolSetting(const WidgetConfig& widget, const std::string& key, bool expected) {
    const auto it = widget.settings.find(key);
    if (it == widget.settings.end()) {
      std::fprintf(stderr, "config_widget_test: FAIL: missing setting '%s'\n", key.c_str());
      return false;
    }
    const auto* actual = std::get_if<bool>(&it->second);
    if (actual == nullptr || *actual != expected) {
      std::fprintf(
          stderr, "config_widget_test: FAIL: setting '%s': expected %s\n", key.c_str(), expected ? "true" : "false"
      );
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

  return ok ? 0 : 1;
}

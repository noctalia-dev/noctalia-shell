#include "shell/settings/widget_settings_registry.h"

#include "i18n/i18n.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <unordered_set>
#include <utility>

namespace settings {
  namespace {

    using i18n::tr;

    const std::vector<WidgetTypeSpec> kWidgetTypeSpecs = {
        {
            .type = "active_window",
            .labelKey = "settings.widget.active-window",
            .categoryKey = "settings.widget-category.window",
        },
        {
            .type = "audio_visualizer",
            .labelKey = "settings.widget.audio-visualizer",
            .categoryKey = "settings.widget-category.media",
        },
        {
            .type = "battery",
            .labelKey = "settings.widget.battery",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "bluetooth",
            .labelKey = "settings.widget.bluetooth",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "brightness",
            .labelKey = "settings.widget.brightness",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "clock",
            .labelKey = "settings.widget.clock",
            .categoryKey = "settings.widget-category.time",
        },
        {
            .type = "idle_inhibitor",
            .labelKey = "settings.widget.idle-inhibitor",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "keyboard_layout",
            .labelKey = "settings.widget.keyboard-layout",
            .categoryKey = "settings.widget-category.input",
        },
        {
            .type = "launcher",
            .labelKey = "settings.widget.launcher",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "lock_keys",
            .labelKey = "settings.widget.lock-keys",
            .categoryKey = "settings.widget-category.input",
        },
        {
            .type = "media",
            .labelKey = "settings.widget.media",
            .categoryKey = "settings.widget-category.media",
        },
        {
            .type = "network",
            .labelKey = "settings.widget.network",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "nightlight",
            .labelKey = "settings.widget.nightlight",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "notifications",
            .labelKey = "settings.widget.notifications",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "power_profiles",
            .labelKey = "settings.widget.power-profiles",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "scripted",
            .labelKey = "settings.widget.scripted",
            .categoryKey = "settings.widget-category.custom",
        },
        {
            .type = "session",
            .labelKey = "settings.widget.session",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "settings",
            .labelKey = "settings.widget.settings",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "spacer",
            .labelKey = "settings.widget.spacer",
            .categoryKey = "settings.widget-category.layout",
        },
        {
            .type = "sysmon",
            .labelKey = "settings.widget.sysmon",
            .categoryKey = "settings.widget-category.system",
        },
        {
            .type = "test",
            .labelKey = "settings.widget.test",
            .categoryKey = "settings.widget-category.custom",
            .visibleInPicker = false,
        },
        {
            .type = "theme_mode",
            .labelKey = "settings.widget.theme-mode",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "tray",
            .labelKey = "settings.widget.tray",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "volume",
            .labelKey = "settings.widget.volume",
            .categoryKey = "settings.widget-category.media",
        },
        {
            .type = "wallpaper",
            .labelKey = "settings.widget.wallpaper",
            .categoryKey = "settings.widget-category.shell",
        },
        {
            .type = "weather",
            .labelKey = "settings.widget.weather",
            .categoryKey = "settings.widget-category.info",
        },
        {
            .type = "workspaces",
            .labelKey = "settings.widget.workspaces",
            .categoryKey = "settings.widget-category.window",
        },
    };

    const WidgetTypeSpec* findWidgetTypeSpec(std::string_view type) {
      for (const auto& spec : kWidgetTypeSpecs) {
        if (spec.type == type) {
          return &spec;
        }
      }
      return nullptr;
    }

    WidgetSettingSpec baseSpec(std::string_view key, WidgetSettingValueType type, WidgetSettingValue defaultValue,
                               bool advanced) {
      WidgetSettingSpec spec;
      spec.key = std::string(key);
      spec.labelKey = std::string("settings.widget-setting.") + std::string(key);
      spec.descriptionKey = std::string("settings.widget-setting-desc.") + std::string(key);
      spec.valueType = type;
      spec.defaultValue = std::move(defaultValue);
      spec.advanced = advanced;
      return spec;
    }

    WidgetSettingSpec boolSpec(std::string_view key, bool defaultValue, bool advanced = false) {
      return baseSpec(key, WidgetSettingValueType::Bool, defaultValue, advanced);
    }

    WidgetSettingSpec intSpec(std::string_view key, std::int64_t defaultValue, double minValue, double maxValue,
                              double step = 1.0, bool advanced = false) {
      auto spec = baseSpec(key, WidgetSettingValueType::Int, defaultValue, advanced);
      spec.minValue = minValue;
      spec.maxValue = maxValue;
      spec.step = step;
      return spec;
    }

    WidgetSettingSpec doubleSpec(std::string_view key, double defaultValue, double minValue, double maxValue,
                                 double step = 1.0, bool advanced = false) {
      auto spec = baseSpec(key, WidgetSettingValueType::Double, defaultValue, advanced);
      spec.minValue = minValue;
      spec.maxValue = maxValue;
      spec.step = step;
      return spec;
    }

    WidgetSettingSpec stringSpec(std::string_view key, std::string defaultValue = {}, bool advanced = false) {
      return baseSpec(key, WidgetSettingValueType::String, std::move(defaultValue), advanced);
    }

    WidgetSettingSpec stringListSpec(std::string_view key, std::vector<std::string> defaultValue = {},
                                     bool advanced = false) {
      return baseSpec(key, WidgetSettingValueType::StringList, std::move(defaultValue), advanced);
    }

    WidgetSettingSpec selectSpec(std::string_view key, std::string defaultValue,
                                 std::vector<WidgetSettingSelectOption> options, bool advanced = false) {
      auto spec = baseSpec(key, WidgetSettingValueType::Select, std::move(defaultValue), advanced);
      spec.options = std::move(options);
      return spec;
    }

    void addPickerEntry(std::vector<WidgetPickerEntry>& entries, std::unordered_set<std::string>& seen,
                        std::string value, std::string label, std::string description, std::string category,
                        WidgetReferenceKind kind) {
      if (!seen.insert(value).second) {
        return;
      }
      entries.push_back(WidgetPickerEntry{.value = std::move(value),
                                          .label = std::move(label),
                                          .description = std::move(description),
                                          .category = std::move(category),
                                          .kind = kind});
    }

    void collectLaneUnknowns(const std::vector<std::string>& widgets, std::vector<WidgetPickerEntry>& entries,
                             std::unordered_set<std::string>& seen, const Config& cfg) {
      for (const auto& name : widgets) {
        if (isBuiltInWidgetType(name) || cfg.widgets.contains(name)) {
          continue;
        }
        addPickerEntry(entries, seen, name, name, name, tr("settings.widget-kind-unknown"),
                       WidgetReferenceKind::Unknown);
      }
    }

  } // namespace

  const std::vector<WidgetTypeSpec>& widgetTypeSpecs() { return kWidgetTypeSpecs; }

  bool isBuiltInWidgetType(std::string_view type) { return findWidgetTypeSpec(type) != nullptr; }

  std::string widgetTypeForReference(const Config& cfg, std::string_view name) {
    if (const auto it = cfg.widgets.find(std::string(name)); it != cfg.widgets.end() && !it->second.type.empty()) {
      return it->second.type;
    }
    if (isBuiltInWidgetType(name)) {
      return std::string(name);
    }
    return {};
  }

  std::string titleFromWidgetKey(std::string_view key) {
    std::string out;
    out.reserve(key.size());
    bool upperNext = true;
    for (const char c : key) {
      if (c == '_' || c == '-') {
        out.push_back(' ');
        upperNext = true;
      } else if (upperNext) {
        out.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
        upperNext = false;
      } else {
        out.push_back(c);
      }
    }
    return out;
  }

  WidgetReferenceInfo widgetReferenceInfo(const Config& cfg, std::string_view name) {
    if (const auto* spec = findWidgetTypeSpec(name)) {
      if (const auto it = cfg.widgets.find(std::string(name));
          it != cfg.widgets.end() && !it->second.type.empty() && it->second.type != name) {
        return WidgetReferenceInfo{
            .title = std::string(name),
            .detail = "type: " + it->second.type,
            .badge = tr("settings.widget-kind-named"),
            .kind = WidgetReferenceKind::Named,
        };
      }
      return WidgetReferenceInfo{
          .title = tr(spec->labelKey),
          .detail = std::string(name),
          .badge = tr("settings.widget-kind-builtin"),
          .kind = WidgetReferenceKind::BuiltIn,
      };
    }

    if (const auto it = cfg.widgets.find(std::string(name)); it != cfg.widgets.end()) {
      return WidgetReferenceInfo{
          .title = std::string(name),
          .detail = it->second.type.empty() ? std::string("custom widget") : ("type: " + it->second.type),
          .badge = tr("settings.widget-kind-named"),
          .kind = WidgetReferenceKind::Named,
      };
    }

    return WidgetReferenceInfo{
        .title = std::string(name),
        .detail = std::string(name),
        .badge = tr("settings.widget-kind-unknown"),
        .kind = WidgetReferenceKind::Unknown,
    };
  }

  std::vector<WidgetPickerEntry> widgetPickerEntries(const Config& cfg) {
    std::vector<WidgetPickerEntry> entries;
    std::unordered_set<std::string> seen;

    for (const auto& spec : kWidgetTypeSpecs) {
      if (!spec.visibleInPicker) {
        continue;
      }
      addPickerEntry(entries, seen, std::string(spec.type), tr(spec.labelKey), std::string(spec.type),
                     tr(spec.categoryKey), WidgetReferenceKind::BuiltIn);
    }

    for (const auto& [name, widget] : cfg.widgets) {
      if (isBuiltInWidgetType(name)) {
        continue;
      }
      addPickerEntry(entries, seen, name, name,
                     widget.type.empty() ? std::string("custom widget") : ("type: " + widget.type),
                     tr("settings.widget-kind-named"), WidgetReferenceKind::Named);
    }

    for (const auto& bar : cfg.bars) {
      collectLaneUnknowns(bar.startWidgets, entries, seen, cfg);
      collectLaneUnknowns(bar.centerWidgets, entries, seen, cfg);
      collectLaneUnknowns(bar.endWidgets, entries, seen, cfg);
      for (const auto& ovr : bar.monitorOverrides) {
        if (ovr.startWidgets.has_value()) {
          collectLaneUnknowns(*ovr.startWidgets, entries, seen, cfg);
        }
        if (ovr.centerWidgets.has_value()) {
          collectLaneUnknowns(*ovr.centerWidgets, entries, seen, cfg);
        }
        if (ovr.endWidgets.has_value()) {
          collectLaneUnknowns(*ovr.endWidgets, entries, seen, cfg);
        }
      }
    }

    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
      if (a.category == b.category) {
        return a.label < b.label;
      }
      return a.category < b.category;
    });
    return entries;
  }

  std::vector<WidgetSettingSpec> commonWidgetSettingSpecs() {
    return {
        boolSpec("anchor", false, true),
        stringSpec("color", {}, true),
        boolSpec("capsule", false),
        stringSpec("capsule_fill", "surface_variant"),
        stringSpec("capsule_border", {}, true),
        stringSpec("capsule_foreground", {}, true),
        doubleSpec("capsule_padding", static_cast<double>(Style::barCapsulePadding), 0.0, 48.0, 1.0),
        doubleSpec("capsule_opacity", 1.0, 0.0, 1.0, 0.01),
    };
  }

  std::vector<WidgetSettingSpec> widgetSettingSpecs(std::string_view type) {
    std::vector<WidgetSettingSpec> specs = commonWidgetSettingSpecs();

    auto add = [&](WidgetSettingSpec spec) { specs.push_back(std::move(spec)); };
    const std::vector<WidgetSettingSelectOption> shortFull = {
        {"short", "settings.widget-option.short"},
        {"full", "settings.widget-option.full"},
    };
    const std::vector<WidgetSettingSelectOption> sysmonStats = {
        {"cpu_usage", "settings.widget-option.cpu-usage"},   {"cpu_temp", "settings.widget-option.cpu-temp"},
        {"ram_used", "settings.widget-option.ram-used"},     {"ram_pct", "settings.widget-option.ram-percent"},
        {"swap_pct", "settings.widget-option.swap-percent"}, {"disk_pct", "settings.widget-option.disk-percent"},
    };
    const std::vector<WidgetSettingSelectOption> sysmonDisplay = {
        {"gauge", "settings.widget-option.gauge"},
        {"graph", "settings.widget-option.graph"},
        {"text", "settings.widget-option.text"},
    };
    const std::vector<WidgetSettingSelectOption> workspaceDisplay = {
        {"id", "settings.widget-option.id"},
        {"name", "settings.widget-option.name"},
        {"none", "settings.widget-option.none"},
    };

    if (type == "active_window") {
      add(doubleSpec("max_length", 260.0, 40.0, 800.0, 1.0));
      add(doubleSpec("icon_size", static_cast<double>(Style::fontSizeBody), 8.0, 64.0, 1.0));
    } else if (type == "audio_visualizer") {
      add(doubleSpec("width", 56.0, 8.0, 400.0, 1.0));
      add(doubleSpec("height", 16.0, 4.0, 120.0, 1.0));
      add(intSpec("bands", 16, 2.0, 128.0, 1.0));
      add(boolSpec("mirrored", false));
      add(stringSpec("low_color", "primary"));
      add(stringSpec("high_color", "primary"));
    } else if (type == "bluetooth") {
      add(boolSpec("show_label", false));
    } else if (type == "clock") {
      add(stringSpec("format", "{:%H:%M}"));
      add(stringSpec("vertical_format"));
    } else if (type == "keyboard_layout") {
      add(stringSpec("cycle_command"));
      add(selectSpec("display", "short", shortFull));
    } else if (type == "launcher") {
      add(stringSpec("glyph", "search"));
    } else if (type == "lock_keys") {
      add(boolSpec("show_caps_lock", true));
      add(boolSpec("show_num_lock", true));
      add(boolSpec("show_scroll_lock", false));
      add(boolSpec("hide_when_off", false));
      add(selectSpec("display", "short", shortFull));
    } else if (type == "media") {
      add(doubleSpec("max_length", 220.0, 40.0, 800.0, 1.0));
      add(doubleSpec("art_size", 16.0, 8.0, 96.0, 1.0));
    } else if (type == "network") {
      add(boolSpec("show_label", true));
    } else if (type == "scripted") {
      add(stringSpec("script"));
      add(boolSpec("hot_reload", false, true));
    } else if (type == "session") {
      add(stringSpec("glyph", "shutdown"));
    } else if (type == "settings") {
      add(stringSpec("glyph", "settings"));
    } else if (type == "spacer") {
      add(doubleSpec("length", 8.0, 0.0, 400.0, 1.0));
    } else if (type == "sysmon") {
      add(selectSpec("stat", "cpu_usage", sysmonStats));
      add(stringSpec("path", "/"));
      add(selectSpec("display", "gauge", sysmonDisplay));
      add(boolSpec("show_label", true));
    } else if (type == "tray") {
      add(stringListSpec("hidden"));
    } else if (type == "wallpaper") {
      add(stringSpec("glyph", "wallpaper-selector"));
    } else if (type == "weather") {
      add(doubleSpec("max_length", 160.0, 40.0, 800.0, 1.0));
      add(boolSpec("show_condition", true));
    } else if (type == "workspaces") {
      add(selectSpec("display", "id", workspaceDisplay));
    }

    return specs;
  }

} // namespace settings

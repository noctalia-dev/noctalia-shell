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
            .labelKey = "settings.widgets.types.active-window",
            .categoryKey = "settings.widgets.categories.window",
        },
        {
            .type = "audio_visualizer",
            .labelKey = "settings.widgets.types.audio-visualizer",
            .categoryKey = "settings.widgets.categories.media",
        },
        {
            .type = "battery",
            .labelKey = "settings.widgets.types.battery",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "bluetooth",
            .labelKey = "settings.widgets.types.bluetooth",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "brightness",
            .labelKey = "settings.widgets.types.brightness",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "clock",
            .labelKey = "settings.widgets.types.clock",
            .categoryKey = "settings.widgets.categories.time",
        },
        {
            .type = "control-center",
            .labelKey = "settings.widgets.types.control-center",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "clipboard",
            .labelKey = "settings.widgets.types.clipboard",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "caffeine",
            .labelKey = "settings.widgets.types.caffeine",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "keyboard_layout",
            .labelKey = "settings.widgets.types.keyboard-layout",
            .categoryKey = "settings.widgets.categories.input",
        },
        {
            .type = "launcher",
            .labelKey = "settings.widgets.types.launcher",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "lock_keys",
            .labelKey = "settings.widgets.types.lock-keys",
            .categoryKey = "settings.widgets.categories.input",
        },
        {
            .type = "media",
            .labelKey = "settings.widgets.types.media",
            .categoryKey = "settings.widgets.categories.media",
        },
        {
            .type = "network",
            .labelKey = "settings.widgets.types.network",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "nightlight",
            .labelKey = "settings.widgets.types.nightlight",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "notifications",
            .labelKey = "settings.widgets.types.notifications",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "power_profiles",
            .labelKey = "settings.widgets.types.power-profiles",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "scripted",
            .labelKey = "settings.widgets.types.scripted",
            .categoryKey = "settings.widgets.categories.custom",
        },
        {
            .type = "session",
            .labelKey = "settings.widgets.types.session",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "settings",
            .labelKey = "settings.widgets.types.settings",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "spacer",
            .labelKey = "settings.widgets.types.spacer",
            .categoryKey = "settings.widgets.categories.layout",
        },
        {
            .type = "sysmon",
            .labelKey = "settings.widgets.types.sysmon",
            .categoryKey = "settings.widgets.categories.system",
        },
        {
            .type = "taskbar",
            .labelKey = "settings.widgets.types.taskbar",
            .categoryKey = "settings.widgets.categories.window",
        },
        {
            .type = "test",
            .labelKey = "settings.widgets.types.test",
            .categoryKey = "settings.widgets.categories.custom",
            .visibleInPicker = false,
        },
        {
            .type = "theme_mode",
            .labelKey = "settings.widgets.types.theme-mode",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "tray",
            .labelKey = "settings.widgets.types.tray",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "volume",
            .labelKey = "settings.widgets.types.volume",
            .categoryKey = "settings.widgets.categories.media",
        },
        {
            .type = "wallpaper",
            .labelKey = "settings.widgets.types.wallpaper",
            .categoryKey = "settings.widgets.categories.shell",
        },
        {
            .type = "weather",
            .labelKey = "settings.widgets.types.weather",
            .categoryKey = "settings.widgets.categories.info",
        },
        {
            .type = "workspaces",
            .labelKey = "settings.widgets.types.workspaces",
            .categoryKey = "settings.widgets.categories.window",
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
      spec.labelKey = std::string("settings.widgets.settings.") + std::string(key) + ".label";
      spec.descriptionKey = std::string("settings.widgets.settings.") + std::string(key) + ".description";
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

    WidgetSettingSpec colorRoleSpec(std::string_view key, std::string defaultValue = {}, bool advanced = false) {
      return baseSpec(key, WidgetSettingValueType::ColorRole, std::move(defaultValue), advanced);
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

    WidgetSettingSpec segmentedSpec(std::string_view key, std::string defaultValue,
                                    std::vector<WidgetSettingSelectOption> options, bool advanced = false) {
      auto spec = selectSpec(key, std::move(defaultValue), std::move(options), advanced);
      spec.segmented = true;
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
        addPickerEntry(entries, seen, name, name, name, tr("settings.entities.widget.kinds.unknown"),
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
            .detail = tr("settings.entities.widget.detail.type", "type", it->second.type),
            .badge = tr("settings.entities.widget.kinds.named"),
            .kind = WidgetReferenceKind::Named,
        };
      }
      return WidgetReferenceInfo{
          .title = tr(spec->labelKey),
          .detail = std::string(name),
          .badge = tr("settings.entities.widget.kinds.built-in"),
          .kind = WidgetReferenceKind::BuiltIn,
      };
    }

    if (const auto it = cfg.widgets.find(std::string(name)); it != cfg.widgets.end()) {
      return WidgetReferenceInfo{
          .title = std::string(name),
          .detail = it->second.type.empty() ? tr("settings.entities.widget.detail.custom")
                                            : tr("settings.entities.widget.detail.type", "type", it->second.type),
          .badge = tr("settings.entities.widget.kinds.named"),
          .kind = WidgetReferenceKind::Named,
      };
    }

    return WidgetReferenceInfo{
        .title = std::string(name),
        .detail = std::string(name),
        .badge = tr("settings.entities.widget.kinds.unknown"),
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
                     widget.type.empty() ? tr("settings.entities.widget.detail.custom")
                                         : tr("settings.entities.widget.detail.type", "type", widget.type),
                     tr("settings.entities.widget.kinds.named"), WidgetReferenceKind::Named);
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
        colorRoleSpec("color", {}, true),
        boolSpec("capsule", false),
        colorRoleSpec("capsule_fill", "surface_variant"),
        colorRoleSpec("capsule_border", {}, true),
        colorRoleSpec("capsule_foreground", {}, true),
        doubleSpec("capsule_padding", static_cast<double>(Style::barCapsulePadding), 0.0, 48.0, 1.0),
        doubleSpec("capsule_opacity", 1.0, 0.0, 1.0, 0.01),
    };
  }

  std::vector<WidgetSettingSpec> widgetSettingSpecs(std::string_view type) {
    std::vector<WidgetSettingSpec> specs = commonWidgetSettingSpecs();

    auto add = [&](WidgetSettingSpec spec) { specs.push_back(std::move(spec)); };
    const std::vector<WidgetSettingSelectOption> shortFull = {
        {"short", "settings.widgets.options.short"},
        {"full", "settings.widgets.options.full"},
    };
    const std::vector<WidgetSettingSelectOption> sysmonStats = {
        {"cpu_usage", "settings.widgets.options.cpu-usage"},   {"cpu_temp", "settings.widgets.options.cpu-temp"},
        {"ram_used", "settings.widgets.options.ram-used"},     {"ram_pct", "settings.widgets.options.ram-percent"},
        {"swap_pct", "settings.widgets.options.swap-percent"}, {"disk_pct", "settings.widgets.options.disk-percent"},
    };
    const std::vector<WidgetSettingSelectOption> sysmonDisplay = {
        {"gauge", "settings.widgets.options.gauge"},
        {"graph", "settings.widgets.options.graph"},
        {"text", "settings.widgets.options.text"},
    };
    const std::vector<WidgetSettingSelectOption> workspaceDisplay = {
        {"id", "settings.widgets.options.id"},
        {"name", "settings.widgets.options.name"},
        {"none", "settings.widgets.options.none"},
    };

    if (type == "active_window") {
      add(doubleSpec("max_length", 260.0, 40.0, 800.0, 1.0));
      add(doubleSpec("icon_size", static_cast<double>(Style::fontSizeBody), 8.0, 64.0, 1.0));
    } else if (type == "audio_visualizer") {
      add(doubleSpec("width", 56.0, 8.0, 400.0, 1.0));
      add(intSpec("bands", 16, 2.0, 128.0, 1.0));
      add(boolSpec("mirrored", true));
      add(boolSpec("show_when_idle", false));
      add(colorRoleSpec("low_color", "primary"));
      add(colorRoleSpec("high_color", "primary"));
    } else if (type == "bluetooth") {
      add(boolSpec("show_label", false));
    } else if (type == "brightness") {
      add(boolSpec("show_label", true));
    } else if (type == "clock") {
      add(stringSpec("format", "{:%H:%M}"));
      add(stringSpec("vertical_format"));
    } else if (type == "clipboard") {
      add(stringSpec("glyph", "clipboard"));
    } else if (type == "keyboard_layout") {
      add(stringSpec("cycle_command"));
      add(segmentedSpec("display", "short", shortFull));
    } else if (type == "launcher") {
      add(stringSpec("glyph", "search"));
      add(boolSpec("use_distro_logo", false));
    } else if (type == "control-center") {
      add(stringSpec("glyph", "noctalia"));
      add(boolSpec("use_distro_logo", false));
    } else if (type == "lock_keys") {
      add(boolSpec("show_caps_lock", true));
      add(boolSpec("show_num_lock", true));
      add(boolSpec("show_scroll_lock", false));
      add(boolSpec("hide_when_off", false));
      add(segmentedSpec("display", "short", shortFull));
    } else if (type == "media") {
      add(doubleSpec("min_length", 80.0, 0.0, 800.0, 1.0));
      add(doubleSpec("max_length", 220.0, 40.0, 800.0, 1.0));
      add(doubleSpec("art_size", 16.0, 8.0, 96.0, 1.0));
    } else if (type == "network") {
      add(boolSpec("show_label", true));
    } else if (type == "notifications") {
      add(boolSpec("hide_when_no_unread", false));
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
      add(segmentedSpec("display", "gauge", sysmonDisplay));
      add(boolSpec("show_label", true));
    } else if (type == "taskbar") {
      add(boolSpec("group_by_workspace", false));
    } else if (type == "tray") {
      add(stringListSpec("hidden"));
    } else if (type == "volume") {
      add(boolSpec("show_label", true));
    } else if (type == "wallpaper") {
      add(stringSpec("glyph", "wallpaper-selector"));
    } else if (type == "weather") {
      add(doubleSpec("max_length", 160.0, 40.0, 800.0, 1.0));
      add(boolSpec("show_condition", true));
    } else if (type == "workspaces") {
      add(segmentedSpec("display", "id", workspaceDisplay));
    }

    return specs;
  }

} // namespace settings

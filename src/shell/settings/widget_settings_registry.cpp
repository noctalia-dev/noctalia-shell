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
        {.type = "active_window", .labelKey = "settings.widgets.types.active-window"},
        {.type = "audio_visualizer", .labelKey = "settings.widgets.types.audio-visualizer"},
        {.type = "battery", .labelKey = "settings.widgets.types.battery"},
        {.type = "bluetooth", .labelKey = "settings.widgets.types.bluetooth"},
        {.type = "brightness", .labelKey = "settings.widgets.types.brightness"},
        {.type = "clock", .labelKey = "settings.widgets.types.clock"},
        {.type = "control-center", .labelKey = "settings.widgets.types.control-center"},
        {.type = "clipboard", .labelKey = "settings.widgets.types.clipboard"},
        {.type = "caffeine", .labelKey = "settings.widgets.types.caffeine"},
        {.type = "keyboard_layout", .labelKey = "settings.widgets.types.keyboard-layout"},
        {.type = "launcher", .labelKey = "settings.widgets.types.launcher"},
        {.type = "lock_keys", .labelKey = "settings.widgets.types.lock-keys"},
        {.type = "media", .labelKey = "settings.widgets.types.media"},
        {.type = "network", .labelKey = "settings.widgets.types.network"},
        {.type = "nightlight", .labelKey = "settings.widgets.types.nightlight"},
        {.type = "notifications", .labelKey = "settings.widgets.types.notifications"},
        {.type = "power_profiles", .labelKey = "settings.widgets.types.power-profiles"},
        {.type = "scripted", .labelKey = "settings.widgets.types.scripted"},
        {.type = "session", .labelKey = "settings.widgets.types.session"},
        {.type = "settings", .labelKey = "settings.widgets.types.settings"},
        {.type = "spacer", .labelKey = "settings.widgets.types.spacer"},
        {.type = "sysmon", .labelKey = "settings.widgets.types.sysmon"},
        {.type = "taskbar", .labelKey = "settings.widgets.types.taskbar"},
        {.type = "test", .labelKey = "settings.widgets.types.test", .visibleInPicker = false},
        {.type = "theme_mode", .labelKey = "settings.widgets.types.theme-mode"},
        {.type = "tray", .labelKey = "settings.widgets.types.tray"},
        {.type = "volume", .labelKey = "settings.widgets.types.volume"},
        {.type = "wallpaper", .labelKey = "settings.widgets.types.wallpaper"},
        {.type = "weather", .labelKey = "settings.widgets.types.weather"},
        {.type = "workspaces", .labelKey = "settings.widgets.types.workspaces"},
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

    WidgetSettingSpec optionalDoubleSpec(std::string_view key, double minValue, double maxValue,
                                         bool advanced = false) {
      auto spec = baseSpec(key, WidgetSettingValueType::OptionalDouble, 0.0, advanced);
      spec.minValue = minValue;
      spec.maxValue = maxValue;
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

    const std::vector<WidgetSettingSelectOption> kAccentColorRoleOptions = {
        {"on_surface", ""},   {"primary", ""},  {"on_primary", ""},  {"secondary", ""},
        {"on_secondary", ""}, {"tertiary", ""}, {"on_tertiary", ""}, {"error", ""},
    };

    void applyAccentColorRolePicker(WidgetSettingSpec& spec) {
      spec.options = kAccentColorRoleOptions;
      spec.allowCustomColor = true;
    }

    std::string widgetInstanceDisplayLabel(std::string_view name) {
      if (name == "cpu") {
        return tr("settings.widgets.instances.cpu");
      }
      if (name == "temp") {
        return tr("settings.widgets.instances.temp");
      }
      if (name == "ram") {
        return tr("settings.widgets.instances.ram");
      }
      if (name == "date") {
        return tr("settings.widgets.instances.date");
      }
      if (name == "output_volume") {
        return tr("settings.widgets.instances.output-volume");
      }
      if (name == "input_volume") {
        return tr("settings.widgets.instances.input-volume");
      }
      return std::string(name);
    }

    void addPickerEntry(std::vector<WidgetPickerEntry>& entries, std::unordered_set<std::string>& seen,
                        std::string value, std::string label, std::string description, WidgetReferenceKind kind) {
      if (!seen.insert(value).second) {
        return;
      }
      entries.push_back(WidgetPickerEntry{
          .value = std::move(value), .label = std::move(label), .description = std::move(description), .kind = kind});
    }

    void collectLaneUnknowns(const std::vector<std::string>& widgets, std::vector<WidgetPickerEntry>& entries,
                             std::unordered_set<std::string>& seen, const Config& cfg) {
      for (const auto& name : widgets) {
        if (isBuiltInWidgetType(name) || cfg.widgets.contains(name)) {
          continue;
        }
        addPickerEntry(entries, seen, name, name, name, WidgetReferenceKind::Unknown);
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
            .detail = it->second.type,
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
          .title = widgetInstanceDisplayLabel(name),
          .detail = it->second.type.empty() ? tr("settings.entities.widget.detail.custom") : it->second.type,
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
                     WidgetReferenceKind::BuiltIn);
    }

    for (const auto& [name, widget] : cfg.widgets) {
      if (isBuiltInWidgetType(name)) {
        continue;
      }
      addPickerEntry(entries, seen, name, widgetInstanceDisplayLabel(name),
                     widget.type.empty() ? tr("settings.entities.widget.detail.custom") : widget.type,
                     WidgetReferenceKind::Named);
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
      if (a.label == b.label) {
        return a.value < b.value;
      }
      return a.label < b.label;
    });
    return entries;
  }

  std::vector<WidgetSettingSpec> commonWidgetSettingSpecs() {
    const WidgetSettingVisibility capsuleOn{"capsule", {"true"}};

    auto anchor = boolSpec("anchor", false, true);
    auto widgetColor = colorRoleSpec("color", {}, true);
    applyAccentColorRolePicker(widgetColor);

    auto capsuleToggle = boolSpec("capsule", false);
    auto capsuleGroup = stringSpec("capsule_group");
    capsuleGroup.visibleWhen = capsuleOn;

    auto capsuleFill = colorRoleSpec("capsule_fill", "", true);
    capsuleFill.visibleWhen = capsuleOn;
    applyAccentColorRolePicker(capsuleFill);

    auto capsuleBorder = colorRoleSpec("capsule_border", {}, true);
    capsuleBorder.visibleWhen = capsuleOn;
    applyAccentColorRolePicker(capsuleBorder);

    auto capsuleForeground = colorRoleSpec("capsule_foreground", {}, true);
    capsuleForeground.visibleWhen = capsuleOn;
    applyAccentColorRolePicker(capsuleForeground);

    auto capsulePadding = doubleSpec("capsule_padding", static_cast<double>(Style::barCapsulePadding), 0.0, 48.0, 1.0);
    capsulePadding.visibleWhen = capsuleOn;
    auto capsuleRadius = optionalDoubleSpec("capsule_radius", 0.0, 80.0);
    capsuleRadius.visibleWhen = capsuleOn;
    auto capsuleOpacity = doubleSpec("capsule_opacity", 1.0, 0.0, 1.0, 0.01);
    capsuleOpacity.visibleWhen = capsuleOn;
    return {
        std::move(anchor),         std::move(widgetColor),    std::move(capsuleToggle), std::move(capsuleRadius),
        std::move(capsuleGroup),   std::move(capsuleFill),    std::move(capsuleBorder), std::move(capsuleForeground),
        std::move(capsulePadding), std::move(capsuleOpacity),
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
        {"gpu_temp", "settings.widgets.options.gpu-temp"},     {"gpu_vram", "settings.widgets.options.gpu-vram"},
        {"ram_used", "settings.widgets.options.ram-used"},     {"ram_pct", "settings.widgets.options.ram-percent"},
        {"swap_pct", "settings.widgets.options.swap-percent"}, {"disk_pct", "settings.widgets.options.disk-percent"},
        {"net_rx", "settings.widgets.options.net-rx"},         {"net_tx", "settings.widgets.options.net-tx"},
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
    const std::vector<WidgetSettingSelectOption> mediaTitleScroll = {
        {"none", "settings.widgets.options.none"},
        {"always", "settings.widgets.options.always"},
        {"on_hover", "settings.widgets.options.on-hover"},
    };
    const std::vector<WidgetSettingSelectOption> volumeDeviceOptions = {
        {"output", "settings.widgets.options.output"},
        {"input", "settings.widgets.options.input"},
    };
    if (type == "active_window") {
      add(doubleSpec("min_length", 80.0, 0.0, 800.0, 1.0));
      add(doubleSpec("max_length", 260.0, 40.0, 800.0, 1.0));
      add(doubleSpec("icon_size", static_cast<double>(Style::fontSizeBody), 8.0, 64.0, 1.0));
      add(selectSpec("title_scroll", "none", mediaTitleScroll));
    } else if (type == "audio_visualizer") {
      add(doubleSpec("width", 56.0, 8.0, 400.0, 1.0));
      add(intSpec("bands", 16, 2.0, 128.0, 1.0));
      add(boolSpec("mirrored", true));
      add(boolSpec("show_when_idle", false));
      {
        auto low = colorRoleSpec("low_color", "primary");
        applyAccentColorRolePicker(low);
        add(std::move(low));
      }
      {
        auto high = colorRoleSpec("high_color", "primary");
        applyAccentColorRolePicker(high);
        add(std::move(high));
      }
    } else if (type == "battery") {
      add(selectSpec("device", "auto", {{"auto", "common.states.auto"}}));
      add(intSpec("warning_threshold", 20, 0.0, 100.0, 1.0));
      {
        auto warn = colorRoleSpec("warning_color", "error");
        applyAccentColorRolePicker(warn);
        add(std::move(warn));
      }
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
      add(stringSpec("custom_image", ""));
    } else if (type == "control-center") {
      add(stringSpec("glyph", "noctalia"));
      add(stringSpec("custom_image", ""));
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
      add(selectSpec("title_scroll", "none", mediaTitleScroll));
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
      {
        auto path = stringSpec("path", "/");
        path.visibleWhen = WidgetSettingVisibility{"stat", {"disk_pct"}};
        add(std::move(path));
      }
      add(segmentedSpec("display", "gauge", sysmonDisplay));
      add(boolSpec("show_label", true));
      {
        auto minW = doubleSpec("label_min_width", 0.0, 0.0, 200.0, 1.0);
        minW.visibleWhen = WidgetSettingVisibility{"show_label", {"true"}};
        add(std::move(minW));
      }
    } else if (type == "taskbar") {
      add(boolSpec("group_by_workspace", false));
      add(boolSpec("show_all_outputs", false));
      add(boolSpec("only_active_workspace", false));
      {
        auto showWsLabel = boolSpec("show_workspace_label", true);
        showWsLabel.visibleWhen =
            WidgetSettingVisibility{WidgetSettingVisibilityCondition{"group_by_workspace", {"true"}}};
        add(std::move(showWsLabel));
      }
      {
        auto hideEmpty = boolSpec("hide_empty_workspaces", false);
        hideEmpty.visibleWhen =
            WidgetSettingVisibility{WidgetSettingVisibilityCondition{"group_by_workspace", {"true"}}};
        add(std::move(hideEmpty));
      }
      for (auto& spec : specs) {
        if (spec.key == "capsule_radius") {
          spec.descriptionKey = "settings.widgets.settings.capsule_radius.taskbar-description";
          spec.visibleWhen = WidgetSettingVisibility{
              WidgetSettingVisibilityCondition{"capsule", {"true"}},
              WidgetSettingVisibilityCondition{"group_by_workspace", {"true"}},
          };
          break;
        }
      }
    } else if (type == "tray") {
      add(stringListSpec("hidden"));
      add(stringListSpec("pinned"));
      add(boolSpec("drawer", false));
      {
        auto cols = intSpec("drawer_columns", 3, 1.0, 5.0, 1.0);
        cols.visibleWhen = WidgetSettingVisibility{"drawer", {"true"}};
        add(std::move(cols));
      }
    } else if (type == "volume") {
      add(segmentedSpec("device", "output", volumeDeviceOptions));
      add(boolSpec("show_label", true));
    } else if (type == "wallpaper") {
      add(stringSpec("glyph", "wallpaper-selector"));
    } else if (type == "weather") {
      add(doubleSpec("max_length", 160.0, 40.0, 800.0, 1.0));
      add(boolSpec("show_condition", true));
    } else if (type == "workspaces") {
      for (auto& spec : specs) {
        if (spec.key == "capsule_radius") {
          spec.descriptionKey = "settings.widgets.settings.capsule_radius.workspaces-description";
          spec.visibleWhen.reset();
          break;
        }
      }
      add(segmentedSpec("display", "id", workspaceDisplay));
      {
        auto maxLabelChars = intSpec("max_label_chars", 1, 1.0, 20.0, 1.0);
        maxLabelChars.descriptionKey = "settings.widgets.settings.max_label_chars.workspaces-description";
        add(std::move(maxLabelChars));
      }
      {
        auto focusedColor = colorRoleSpec("focused_color", "primary");
        applyAccentColorRolePicker(focusedColor);
        add(std::move(focusedColor));
      }
      {
        auto occupiedColor = colorRoleSpec("occupied_color", "secondary");
        applyAccentColorRolePicker(occupiedColor);
        add(std::move(occupiedColor));
      }
      {
        auto emptyColor = colorRoleSpec("empty_color", "secondary");
        applyAccentColorRolePicker(emptyColor);
        add(std::move(emptyColor));
      }
    }

    return specs;
  }

} // namespace settings

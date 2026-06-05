#include "shell/desktop/desktop_widget_settings_registry.h"

#include "util/string_utils.h"

namespace desktop_settings {
  namespace {

    using settings::WidgetControlKind;
    using settings::WidgetSettingSelectOption;
    using settings::WidgetSettingSpec;
    using settings::WidgetSettingVisibility;

    const std::vector<DesktopWidgetTypeSpec> kDesktopWidgetTypeSpecs = {
        {.type = "audio_visualizer", .labelKey = "desktop-widgets.editor.types.audio-visualizer"},
        {.type = "clock", .labelKey = "desktop-widgets.editor.types.clock"},
        {.type = "fancy_audio_visualizer", .labelKey = "desktop-widgets.editor.types.fancy-audio-visualizer"},
        {.type = "label", .labelKey = "desktop-widgets.editor.types.label"},
        {.type = "media_player", .labelKey = "desktop-widgets.editor.types.media-player"},
        {.type = "sticker", .labelKey = "desktop-widgets.editor.types.sticker"},
        {.type = "sysmon", .labelKey = "desktop-widgets.editor.types.system-monitor"},
        {.type = "weather", .labelKey = "desktop-widgets.editor.types.weather"},
    };

    WidgetSettingSpec baseSpec(std::string_view key, WidgetControlKind control, WidgetSettingValue defaultValue) {
      WidgetSettingSpec spec;
      spec.schema.key = std::string(key);
      spec.schema.type = settings::schemaTypeForControl(control);
      spec.schema.defaultValue = std::move(defaultValue);
      spec.control = control;
      spec.labelKey = "desktop-widgets.editor.settings." + StringUtils::snakeToKebab(key);
      return spec;
    }

    WidgetSettingSpec boolSpec(std::string_view key, bool defaultValue) {
      return baseSpec(key, WidgetControlKind::Bool, defaultValue);
    }

    WidgetSettingSpec
    doubleSpec(std::string_view key, double defaultValue, double minValue, double maxValue, double step = 1.0) {
      auto spec = baseSpec(key, WidgetControlKind::Double, defaultValue);
      spec.schema.minValue = minValue;
      spec.schema.maxValue = maxValue;
      spec.schema.step = step;
      return spec;
    }

    WidgetSettingSpec stringSpec(std::string_view key, std::string defaultValue = {}) {
      return baseSpec(key, WidgetControlKind::String, std::move(defaultValue));
    }

    WidgetSettingSpec colorSpec(std::string_view key, std::string defaultValue = {}) {
      return baseSpec(key, WidgetControlKind::ColorSpec, std::move(defaultValue));
    }

    WidgetSettingSpec
    selectSpec(std::string_view key, std::string defaultValue, std::vector<WidgetSettingSelectOption> options) {
      auto spec = baseSpec(key, WidgetControlKind::Select, std::move(defaultValue));
      for (const auto& option : options) {
        spec.schema.enumValues.push_back(option.value);
      }
      spec.options = std::move(options);
      return spec;
    }

    WidgetSettingSpec
    segmentedSpec(std::string_view key, std::string defaultValue, std::vector<WidgetSettingSelectOption> options) {
      auto spec = selectSpec(key, std::move(defaultValue), std::move(options));
      spec.segmented = true;
      return spec;
    }

  } // namespace

  const std::vector<DesktopWidgetTypeSpec>& desktopWidgetTypeSpecs() { return kDesktopWidgetTypeSpecs; }

  std::vector<WidgetSettingSpec> commonDesktopWidgetSettingSpecs(std::string_view type) {
    const WidgetSettingVisibility backgroundOn{"background", {"true"}};
    const bool backgroundDefault = type != "fancy_audio_visualizer";

    auto bgColor = colorSpec("background_color", "surface");
    bgColor.visibleWhen = backgroundOn;

    auto bgRadius = doubleSpec("background_radius", 12.0, 0.0, 32.0, 1.0);
    bgRadius.visibleWhen = backgroundOn;

    auto bgPadding = doubleSpec("background_padding", 10.0, 0.0, 32.0, 1.0);
    bgPadding.visibleWhen = backgroundOn;

    auto bgOpacity = doubleSpec("background_opacity", 0.8, 0.0, 1.0, 0.01);
    bgOpacity.visibleWhen = backgroundOn;

    return {
        boolSpec("background", backgroundDefault),
        std::move(bgColor),
        std::move(bgOpacity),
        std::move(bgRadius),
        std::move(bgPadding),
    };
  }

  std::vector<WidgetSettingSpec> desktopWidgetSettingSpecs(std::string_view type) {
    const std::vector<WidgetSettingSelectOption> sysmonStats = {
        {"cpu_usage", "desktop-widgets.editor.settings.stat-cpu-usage"},
        {"cpu_temp", "desktop-widgets.editor.settings.stat-cpu-temp"},
        {"gpu_temp", "desktop-widgets.editor.settings.stat-gpu-temp"},
        {"gpu_usage", "desktop-widgets.editor.settings.stat-gpu-usage"},
        {"gpu_vram", "desktop-widgets.editor.settings.stat-gpu-vram"},
        {"ram_pct", "desktop-widgets.editor.settings.stat-ram-pct"},
        {"swap_pct", "desktop-widgets.editor.settings.stat-swap-pct"},
        {"net_rx", "desktop-widgets.editor.settings.stat-net-rx"},
        {"net_tx", "desktop-widgets.editor.settings.stat-net-tx"},
    };

    std::vector<WidgetSettingSelectOption> sysmonStatsWithNone = {
        {"", "desktop-widgets.editor.settings.stat-none"},
    };
    sysmonStatsWithNone.insert(sysmonStatsWithNone.end(), sysmonStats.begin(), sysmonStats.end());

    std::vector<WidgetSettingSpec> specs;
    auto add = [&](WidgetSettingSpec spec) { specs.push_back(std::move(spec)); };

    if (type == "clock") {
      add(stringSpec("format", "{:%H:%M}"));
      add(colorSpec("color", "on_surface"));
      add(boolSpec("shadow", true));
    } else if (type == "audio_visualizer") {
      add(doubleSpec("aspect_ratio", 2.5, 0.5, 6.0, 0.1));
      add(doubleSpec("bands", 32.0, 4.0, 128.0, 4.0));
      add(boolSpec("mirrored", true));
      add(boolSpec("centered", true));
      add(boolSpec("show_when_idle", true));
      add(colorSpec("low_color", "primary"));
      add(colorSpec("high_color", "primary"));
    } else if (type == "fancy_audio_visualizer") {
      const WidgetSettingVisibility barsVisible{"visualization_mode", {"bars", "bars_rings", "all"}};
      const WidgetSettingVisibility waveVisible{"visualization_mode", {"wave", "wave_rings", "all"}};
      const WidgetSettingVisibility ringsVisible{"visualization_mode", {"rings", "bars_rings", "wave_rings", "all"}};

      add(selectSpec(
          "visualization_mode", "bars_rings",
          {{"bars", "desktop-widgets.editor.settings.visualization-mode-bars"},
           {"wave", "desktop-widgets.editor.settings.visualization-mode-wave"},
           {"rings", "desktop-widgets.editor.settings.visualization-mode-rings"},
           {"bars_rings", "desktop-widgets.editor.settings.visualization-mode-bars-rings"},
           {"wave_rings", "desktop-widgets.editor.settings.visualization-mode-wave-rings"},
           {"all", "desktop-widgets.editor.settings.visualization-mode-all"}}
      ));
      add(doubleSpec("sensitivity", 1.5, 0.5, 3.0, 0.1));
      add(doubleSpec("rotation_speed", 0.5, 0.0, 2.0, 0.1));
      auto barWidth = doubleSpec("bar_width", 0.6, 0.2, 1.0, 0.1);
      barWidth.visibleWhen = barsVisible;
      add(std::move(barWidth));
      auto waveThickness = doubleSpec("wave_thickness", 1.0, 0.3, 2.0, 0.1);
      waveThickness.visibleWhen = waveVisible;
      add(std::move(waveThickness));
      auto ringOpacity = doubleSpec("ring_opacity", 0.8, 0.0, 1.0, 0.1);
      ringOpacity.visibleWhen = ringsVisible;
      add(std::move(ringOpacity));
      add(doubleSpec("inner_diameter", 0.7, 0.0, 1.0, 0.05));
      add(doubleSpec("bloom_intensity", 0.5, 0.0, 1.0, 0.05));
      add(boolSpec("fade_when_idle", false));
      add(colorSpec("primary_color", "primary"));
      add(colorSpec("secondary_color", "secondary"));
    } else if (type == "sticker") {
      add(stringSpec("image_path"));
      add(doubleSpec("opacity", 1.0, 0.0, 1.0, 0.01));
    } else if (type == "weather") {
      add(colorSpec("color", "on_surface"));
      add(boolSpec("shadow", true));
    } else if (type == "media_player") {
      add(segmentedSpec(
          "layout", "horizontal",
          {{"horizontal", "desktop-widgets.editor.settings.horizontal"},
           {"vertical", "desktop-widgets.editor.settings.vertical"}}
      ));
      add(colorSpec("color", "on_surface"));
      add(boolSpec("shadow", true));
      add(boolSpec("hide_when_no_media", false));
    } else if (type == "label") {
      add(stringSpec("title", "Title"));
      add(stringSpec("description"));
      add(colorSpec("color", "on_surface"));
      add(boolSpec("shadow", true));
    } else if (type == "sysmon") {
      add(selectSpec("stat", "cpu_usage", sysmonStats));
      add(selectSpec("stat2", "", sysmonStatsWithNone));
      add(colorSpec("color", "primary"));
      add(colorSpec("color2", "secondary"));
      add(boolSpec("show_label", true));
      add(boolSpec("shadow", true));
    }

    return specs;
  }

  noctalia::config::schema::WidgetSettingSchema desktopWidgetSettingSchema(std::string_view type) {
    noctalia::config::schema::WidgetSettingSchema out;
    for (const auto& spec : desktopWidgetSettingSpecs(type)) {
      out.push_back(spec.schema);
    }
    for (const auto& spec : commonDesktopWidgetSettingSpecs(type)) {
      out.push_back(spec.schema);
    }
    return out;
  }

} // namespace desktop_settings

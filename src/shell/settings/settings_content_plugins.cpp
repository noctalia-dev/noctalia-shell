#include "shell/settings/settings_content_plugins.h"

#include "config/config_types.h"
#include "i18n/i18n.h"
#include "scripting/plugin_registry.h"
#include "shell/settings/settings_control_factory.h"
#include "shell/settings/settings_registry.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/builders.h"
#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

namespace settings {

  namespace {
    std::unique_ptr<Label>
    makeLabel(std::string_view text, float fontSize, ColorRole role, FontWeight weight = FontWeight::Normal) {
      return ui::label({
          .text = std::string(text),
          .fontSize = fontSize,
          .color = colorSpecFromRole(role),
          .fontWeight = weight,
      });
    }

    bool pluginEnabled(const scripting::PluginStatus& plugin, const SettingsPluginsContext& ctx) {
      if (ctx.config == nullptr) {
        return plugin.enabled;
      }
      return std::find(ctx.config->plugins.enabled.begin(), ctx.config->plugins.enabled.end(), plugin.id)
          != ctx.config->plugins.enabled.end();
    }

    std::string_view pluginDisplayName(const scripting::PluginStatus& plugin) { return plugin.name; }

    std::string pluginSourceDisplayName(std::string_view source) {
      if (source == "official") {
        return "Official";
      }
      if (source == "community") {
        return "Community";
      }
      return std::string(source);
    }

    std::unique_ptr<Flex> sourceRow(const PluginSourceConfig& source, const SettingsPluginsContext& ctx, float scale) {
      auto row = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true});
      Flex* r = row.get();

      auto info = ui::column({.align = FlexAlign::Start, .gap = 2.0F * scale, .flexGrow = 1.0F});
      info->addChild(makeLabel(
          pluginSourceDisplayName(source.name), Style::fontSizeBody * scale, ColorRole::OnSurface, FontWeight::Medium
      ));
      const std::string kind = source.kind == PluginSourceKind::Git ? i18n::tr("settings.plugins.sources.kind.git")
                                                                    : i18n::tr("settings.plugins.sources.kind.path");
      info->addChild(
          makeLabel(kind + " · " + source.location, Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant)
      );
      r->addChild(std::move(info));

      if (source.kind == PluginSourceKind::Git) {
        auto autoUpdate = ui::row({.align = FlexAlign::Center, .gap = Style::spaceXs * scale});
        autoUpdate->addChild(makeLabel(
            i18n::tr("settings.plugins.sources.update-on-startup"), Style::fontSizeCaption * scale,
            ColorRole::OnSurfaceVariant, FontWeight::Medium
        ));
        autoUpdate->addChild(
            ui::toggle({
                .checked = source.autoUpdate,
                .toggleSize = ToggleSize::Small,
                .scale = scale,
                .onChange = [cb = ctx.setSourceAutoUpdate, source](bool on) {
                  if (cb) {
                    cb(source, on);
                  }
                },
            })
        );
        r->addChild(std::move(autoUpdate));
        r->addChild(
            ui::button({
                .text = i18n::tr("settings.plugins.sources.update"),
                .fontSize = Style::fontSizeCaption * scale,
                .variant = ButtonVariant::Outline,
                .onClick = [cb = ctx.updateSource, name = source.name]() {
                  if (cb) {
                    cb(name);
                  }
                },
            })
        );
      }
      if (!isDefaultPluginSourceName(source.name)) {
        r->addChild(
            ui::button({
                .glyph = "trash",
                .glyphSize = Style::fontSizeBody * scale,
                .variant = ButtonVariant::Ghost,
                .tooltip = i18n::tr("settings.plugins.sources.remove"),
                .onClick = [cb = ctx.removeSource, name = source.name]() {
                  if (cb) {
                    cb(name);
                  }
                },
            })
        );
      }
      return row;
    }

    std::unique_ptr<Flex>
    pluginRow(const scripting::PluginStatus& plugin, const SettingsPluginsContext& ctx, float scale) {
      auto row = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true});
      Flex* r = row.get();
      const bool enabled = pluginEnabled(plugin, ctx);

      r->addChild(
          ui::glyph({
              .glyph = plugin.icon.empty() ? std::string("apps") : plugin.icon,
              .glyphSize = Style::fontSizeHeader * scale,
              .color = colorSpecFromRole(ColorRole::Primary),
              .width = Style::controlHeightSm * scale,
              .height = Style::controlHeightSm * scale,
          })
      );

      auto info = ui::column({.align = FlexAlign::Start, .gap = 2.0F * scale, .flexGrow = 1.0F});
      auto title = ui::row({.align = FlexAlign::Center, .gap = Style::spaceXs * scale});
      const std::string version = plugin.version.empty() ? std::string("?") : plugin.version;
      title->addChild(
          makeLabel(pluginDisplayName(plugin), Style::fontSizeBody * scale, ColorRole::OnSurface, FontWeight::Medium)
      );
      title->addChild(
          makeLabel(pluginSourceDisplayName(plugin.source), Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant)
      );
      title->addChild(makeLabel("v" + version, Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant));
      if (!plugin.compatible) {
        title->addChild(makeLabel(
            i18n::tr("settings.plugins.plugins.requires-newer-noctalia"), Style::fontSizeMini * scale, ColorRole::Error,
            FontWeight::Bold
        ));
      }
      if (plugin.deprecated) {
        title->addChild(makeLabel(
            i18n::tr("settings.plugins.plugins.deprecated"), Style::fontSizeMini * scale, ColorRole::Secondary,
            FontWeight::Bold
        ));
      }
      info->addChild(std::move(title));
      if (!plugin.description.empty()) {
        info->addChild(makeLabel(plugin.description, Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant));
      }
      r->addChild(std::move(info));

      const auto* manifest = scripting::PluginRegistry::instance().findManifest(plugin.id);
      if (enabled && manifest != nullptr && !manifest->settings.empty() && ctx.onConfigure) {
        r->addChild(
            ui::button({
                .glyph = "settings",
                .glyphSize = Style::fontSizeBody * scale,
                .variant = ButtonVariant::Ghost,
                .tooltip = i18n::tr("settings.plugins.plugins.configure"),
                .onClick = [cb = ctx.onConfigure, id = plugin.id]() {
                  if (cb) {
                    cb(id);
                  }
                },
            })
        );
      }

      r->addChild(
          ui::toggle({
              .checked = enabled,
              .enabled = enabled || plugin.compatible,
              .scale = scale,
              .onChange = [cb = ctx.setEnabled, id = plugin.id](bool on) {
                if (cb) {
                  cb(id, on);
                }
              },
          })
      );
      return row;
    }

    // ── Per-plugin settings editor ─────────────────────────────────────────

    std::string valueAsString(const WidgetSettingValue& value) {
      if (const auto* s = std::get_if<std::string>(&value)) {
        return *s;
      }
      if (const auto* b = std::get_if<bool>(&value)) {
        return *b ? "true" : "false";
      }
      if (const auto* i = std::get_if<std::int64_t>(&value)) {
        return std::to_string(*i);
      }
      if (const auto* d = std::get_if<double>(&value)) {
        return std::to_string(*d);
      }
      return {};
    }

    bool valueAsBool(const WidgetSettingValue& value) {
      if (const auto* b = std::get_if<bool>(&value)) {
        return *b;
      }
      if (const auto* i = std::get_if<std::int64_t>(&value)) {
        return *i != 0;
      }
      return false;
    }

    std::int64_t valueAsInt(const WidgetSettingValue& value) {
      if (const auto* i = std::get_if<std::int64_t>(&value)) {
        return *i;
      }
      if (const auto* d = std::get_if<double>(&value)) {
        return static_cast<std::int64_t>(std::llround(*d));
      }
      return 0;
    }

    double valueAsDouble(const WidgetSettingValue& value) {
      if (const auto* d = std::get_if<double>(&value)) {
        return *d;
      }
      if (const auto* i = std::get_if<std::int64_t>(&value)) {
        return static_cast<double>(*i);
      }
      return 0.0;
    }

    // Current value for a plugin setting: the override if present, else the manifest default.
    WidgetSettingValue
    pluginSettingValue(const Config& cfg, const std::string& pluginId, const WidgetSettingSpec& spec) {
      const auto pluginIt = cfg.plugins.pluginSettings.find(pluginId);
      if (pluginIt != cfg.plugins.pluginSettings.end()) {
        const auto keyIt = pluginIt->second.find(spec.schema.key);
        if (keyIt != pluginIt->second.end()) {
          return keyIt->second;
        }
      }
      return spec.schema.defaultValue;
    }

    bool pluginSettingVisible(
        const Config& cfg, const std::string& pluginId, const WidgetSettingSpec& spec,
        const std::vector<WidgetSettingSpec>& allSpecs
    ) {
      if (!spec.visibleWhen.has_value()) {
        return true;
      }
      const auto currentString = [&](const std::string& key) -> std::string {
        const auto depIt = std::find_if(allSpecs.begin(), allSpecs.end(), [&](const WidgetSettingSpec& s) {
          return s.schema.key == key;
        });
        if (depIt == allSpecs.end()) {
          return {};
        }
        return valueAsString(pluginSettingValue(cfg, pluginId, *depIt));
      };
      const auto matches = [&](const WidgetSettingVisibilityCondition& cond) {
        const std::string value = currentString(cond.key);
        return std::find(cond.values.begin(), cond.values.end(), value) != cond.values.end();
      };
      // Visible when any `any` alternative matches (or none declared) AND every `all` condition matches.
      const auto& vis = *spec.visibleWhen;
      const bool anyOk = vis.any.empty() || std::any_of(vis.any.begin(), vis.any.end(), matches);
      const bool allOk = std::all_of(vis.all.begin(), vis.all.end(), matches);
      return anyOk && allOk;
    }

    std::unique_ptr<Node> pluginSettingControl(
        SettingsControlFactory& factory, const WidgetSettingSpec& spec, const WidgetSettingValue& value,
        const std::vector<std::string>& path
    ) {
      switch (spec.control) {
      case WidgetControlKind::Bool: {
        std::optional<bool> clearWhenValue;
        if (const auto* defaultBool = std::get_if<bool>(&spec.schema.defaultValue)) {
          clearWhenValue = *defaultBool;
        }
        return factory.makeToggle(valueAsBool(value), true, path, clearWhenValue);
      }
      case WidgetControlKind::Int: {
        const double minValue = spec.schema.minValue.value_or(0.0);
        const double maxValue = spec.schema.maxValue.value_or(100.0);
        return factory.makeSlider(
            static_cast<double>(valueAsInt(value)), minValue, maxValue, spec.schema.step.value_or(1.0), path,
            /*integerValue=*/true
        );
      }
      case WidgetControlKind::Double: {
        const double minValue = spec.schema.minValue.value_or(0.0);
        const double maxValue = spec.schema.maxValue.value_or(1.0);
        return factory.makeSlider(
            valueAsDouble(value), minValue, maxValue, spec.schema.step.value_or(1.0), path, false
        );
      }
      case WidgetControlKind::Select: {
        std::vector<SelectOption> options;
        options.reserve(spec.options.size());
        for (const auto& option : spec.options) {
          options.push_back(
              SelectOption{option.value, spec.literalLabels ? option.labelKey : i18n::tr(option.labelKey)}
          );
        }
        SelectSetting selectSetting{std::move(options), valueAsString(value)};
        if (const auto* defaultString = std::get_if<std::string>(&spec.schema.defaultValue)) {
          selectSetting.clearOnEmpty = defaultString->empty();
        }
        return factory.makeSelect(selectSetting, path);
      }
      case WidgetControlKind::ColorSpec: {
        ColorSpecPickerSetting pickerSetting;
        pickerSetting.selectedValue = valueAsString(value);
        pickerSetting.allowNone = spec.advanced;
        pickerSetting.allowCustomColor = spec.allowCustomColor;
        return factory.makeColorSpecPicker(pickerSetting, path);
      }
      case WidgetControlKind::String:
      case WidgetControlKind::File:
      case WidgetControlKind::Folder:
      case WidgetControlKind::Glyph:
      default:
        return factory.makeText(valueAsString(value), {}, path);
      }
    }

  } // namespace

  void buildPluginSettingsEditor(
      Flex& body, const Config& cfg, SettingsControlFactory& factory, const std::string& pluginId,
      const scripting::PluginManifest& manifest, bool showAdvanced, float scale
  ) {
    const auto specs = settings::manifestSettingSpecs(manifest.settings);
    bool rendered = false;
    for (const auto& spec : specs) {
      if (spec.advanced && !showAdvanced) {
        continue;
      }
      if (!pluginSettingVisible(cfg, pluginId, spec, specs)) {
        continue;
      }
      const std::vector<std::string> path = {"plugin_settings", pluginId, spec.schema.key};
      const WidgetSettingValue value = pluginSettingValue(cfg, pluginId, spec);
      SettingEntry entry{
          .section = SettingsSection::Bar,
          .group = "plugin-settings",
          .title = spec.literalLabel,
          .subtitle = spec.literalDescription,
          .path = path,
          .control = TextSetting{},
          .advanced = spec.advanced,
          .searchText = {},
          .visibleWhen = std::nullopt,
      };
      factory.makeRow(body, entry, pluginSettingControl(factory, spec, value, path));
      rendered = true;
    }
    if (!rendered) {
      body.addChild(makeLabel(
          i18n::tr("settings.plugins.settings.empty"), Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant
      ));
    }
  }

  void addSettingsPlugins(Flex& content, SettingsPluginsContext ctx) {
    if (ctx.selectedSection != "plugins") {
      return;
    }
    const float scale = ctx.scale;

    auto sectionCol = ui::column({
        .align = FlexAlign::Stretch,
        .gap = Style::spaceSm * scale,
        .padding = Style::spaceLg * scale,
        .fill = clearColorSpec(),
        .fillWidth = true,
    });
    Flex* section = sectionCol.get();
    content.addChild(std::move(sectionCol));

    section->addChild(
        ui::row(
            {.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true},
            ui::glyph({
                .glyph = "puzzle",
                .glyphSize = Style::fontSizeHeader * scale,
                .color = colorSpecFromRole(ColorRole::Primary),
            }),
            makeLabel(
                i18n::tr("settings.navigation.sections.plugins"), Style::fontSizeHeader * scale, ColorRole::Primary,
                FontWeight::Bold
            )
        )
    );

    // ── Sources ──────────────────────────────────────────────────────────
    auto sourcesHeader = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true});
    sourcesHeader->addChild(makeLabel(
        i18n::tr("settings.plugins.sources.title"), Style::fontSizeBody * scale, ColorRole::Secondary, FontWeight::Bold
    ));
    sourcesHeader->addChild(ui::spacer());
    sourcesHeader->addChild(
        ui::button({
            .text = i18n::tr("settings.plugins.sources.add"),
            .glyph = "add",
            .fontSize = Style::fontSizeCaption * scale,
            .glyphSize = Style::fontSizeBody * scale,
            .variant = ButtonVariant::Outline,
            .onClick = [cb = ctx.addSource]() {
              if (cb) {
                cb();
              }
            },
        })
    );
    section->addChild(std::move(sourcesHeader));
    if (ctx.sources.empty()) {
      section->addChild(makeLabel(
          i18n::tr("settings.plugins.sources.empty"), Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant
      ));
    }
    for (const auto& source : ctx.sources) {
      section->addChild(sourceRow(source, ctx, scale));
    }

    section->addChild(ui::separator({.spacing = Style::spaceSm * scale}));

    // ── Plugins ──────────────────────────────────────────────────────────
    section->addChild(makeLabel(
        i18n::tr("settings.plugins.plugins.title"), Style::fontSizeBody * scale, ColorRole::Secondary, FontWeight::Bold
    ));
    if (ctx.pluginsLoading) {
      section->addChild(makeLabel(
          ctx.plugins.empty() ? i18n::tr("settings.plugins.plugins.loading")
                              : i18n::tr("settings.plugins.plugins.refreshing"),
          Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant
      ));
    } else if (ctx.plugins.empty()) {
      section->addChild(makeLabel(
          i18n::tr("settings.plugins.plugins.empty"), Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant
      ));
    }
    std::vector<scripting::PluginStatus> plugins = ctx.plugins;
    std::sort(plugins.begin(), plugins.end(), [&](const auto& a, const auto& b) {
      const bool aEnabled = pluginEnabled(a, ctx);
      const bool bEnabled = pluginEnabled(b, ctx);
      if (aEnabled != bEnabled) {
        return aEnabled;
      }
      const std::string_view aName = pluginDisplayName(a);
      const std::string_view bName = pluginDisplayName(b);
      if (aName != bName) {
        return aName < bName;
      }
      if (a.source != b.source) {
        return a.source < b.source;
      }
      return a.id < b.id;
    });
    for (const auto& plugin : plugins) {
      section->addChild(pluginRow(plugin, ctx, scale));
    }
  }

} // namespace settings

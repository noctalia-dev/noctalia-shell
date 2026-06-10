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

    std::unique_ptr<Flex> sourceRow(const PluginSourceConfig& source, const SettingsPluginsContext& ctx, float scale) {
      auto row = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true});
      Flex* r = row.get();

      auto info = ui::column({.align = FlexAlign::Start, .gap = 2.0F * scale, .flexGrow = 1.0F});
      info->addChild(makeLabel(source.name, Style::fontSizeBody * scale, ColorRole::OnSurface, FontWeight::Medium));
      const std::string kind = source.kind == PluginSourceKind::Git ? "git" : "path";
      info->addChild(
          makeLabel(kind + " · " + source.location, Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant)
      );
      r->addChild(std::move(info));

      if (source.kind == PluginSourceKind::Git) {
        r->addChild(
            ui::button({
                .text = "Update",
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
      r->addChild(
          ui::button({
              .glyph = "trash",
              .glyphSize = Style::fontSizeBody * scale,
              .variant = ButtonVariant::Ghost,
              .tooltip = "Remove source",
              .onClick = [cb = ctx.removeSource, name = source.name]() {
                if (cb) {
                  cb(name);
                }
              },
          })
      );
      return row;
    }

    std::unique_ptr<Flex>
    pluginRow(const scripting::PluginStatus& plugin, const SettingsPluginsContext& ctx, float scale) {
      auto row = ui::row({.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .fillWidth = true});
      Flex* r = row.get();

      auto info = ui::column({.align = FlexAlign::Start, .gap = 2.0F * scale, .flexGrow = 1.0F});
      auto title = ui::row({.align = FlexAlign::Center, .gap = Style::spaceXs * scale});
      title->addChild(makeLabel(plugin.id, Style::fontSizeBody * scale, ColorRole::OnSurface, FontWeight::Medium));
      if (!plugin.compatible) {
        title->addChild(
            makeLabel("requires newer noctalia", Style::fontSizeMini * scale, ColorRole::Error, FontWeight::Bold)
        );
      }
      info->addChild(std::move(title));
      const std::string version = plugin.version.empty() ? std::string("?") : plugin.version;
      info->addChild(
          makeLabel("v" + version + " · " + plugin.source, Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant)
      );
      r->addChild(std::move(info));

      const auto* manifest = scripting::PluginRegistry::instance().findManifest(plugin.id);
      if (plugin.enabled && manifest != nullptr && !manifest->settings.empty() && ctx.controlFactory != nullptr) {
        const bool open = ctx.configurePluginId == plugin.id;
        r->addChild(
            ui::button({
                .glyph = "settings",
                .glyphSize = Style::fontSizeBody * scale,
                .variant = open ? ButtonVariant::Primary : ButtonVariant::Ghost,
                .tooltip = "Configure",
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
              .checked = plugin.enabled,
              .enabled = plugin.compatible,
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

    void addPluginSettingsPanel(
        Flex& section, const std::string& pluginId, const scripting::PluginManifest& manifest,
        const SettingsPluginsContext& ctx
    ) {
      const auto specs = settings::manifestSettingSpecs(manifest.settings);
      auto panel = ui::column({
          .align = FlexAlign::Stretch,
          .gap = Style::spaceXs * ctx.scale,
          .padding = Style::spaceSm * ctx.scale,
          .fillWidth = true,
      });
      Flex* p = panel.get();

      for (const auto& spec : specs) {
        if (spec.advanced && !ctx.showAdvanced) {
          continue;
        }
        if (ctx.config == nullptr || !pluginSettingVisible(*ctx.config, pluginId, spec, specs)) {
          continue;
        }
        const std::vector<std::string> path = {"plugin_settings", pluginId, spec.schema.key};
        const WidgetSettingValue value = pluginSettingValue(*ctx.config, pluginId, spec);
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
        ctx.controlFactory->makeRow(*p, entry, pluginSettingControl(*ctx.controlFactory, spec, value, path));
      }

      section.addChild(std::move(panel));
    }
  } // namespace

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
    section->addChild(makeLabel("Sources", Style::fontSizeBody * scale, ColorRole::Secondary, FontWeight::Bold));
    if (ctx.sources.empty()) {
      section->addChild(
          makeLabel("No sources configured.", Style::fontSizeCaption * scale, ColorRole::OnSurfaceVariant)
      );
    }
    for (const auto& source : ctx.sources) {
      section->addChild(sourceRow(source, ctx, scale));
    }

    section->addChild(ui::separator());

    // ── Plugins ──────────────────────────────────────────────────────────
    section->addChild(makeLabel("Plugins", Style::fontSizeBody * scale, ColorRole::Secondary, FontWeight::Bold));
    if (ctx.plugins.empty()) {
      section->addChild(makeLabel(
          "No plugins found. Add a source, or check your network.", Style::fontSizeCaption * scale,
          ColorRole::OnSurfaceVariant
      ));
    }
    for (const auto& plugin : ctx.plugins) {
      section->addChild(pluginRow(plugin, ctx, scale));
      if (ctx.configurePluginId == plugin.id && ctx.controlFactory != nullptr) {
        if (const auto* manifest = scripting::PluginRegistry::instance().findManifest(plugin.id);
            manifest != nullptr && !manifest->settings.empty()) {
          addPluginSettingsPanel(*section, plugin.id, *manifest, ctx);
        }
      }
    }
  }

} // namespace settings

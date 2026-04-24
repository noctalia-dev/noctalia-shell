#include "shell/settings/bar_widget_editor.h"

#include "i18n/i18n.h"
#include "render/scene/node.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/search_picker.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

namespace settings {
  namespace {

    constexpr std::string_view kCreateInstancePrefix = "create-instance:";

    std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ThemeColor& color,
                                     bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

    std::string pathKey(const std::vector<std::string>& path) {
      std::string out;
      for (const auto& part : path) {
        if (!out.empty()) {
          out.push_back('.');
        }
        out += part;
      }
      return out;
    }

    std::vector<std::string> pathWithLastSegment(std::vector<std::string> path, std::string segment) {
      if (!path.empty()) {
        path.back() = std::move(segment);
      }
      return path;
    }

    std::string laneLabel(std::string_view lane) {
      if (lane == "start") {
        return i18n::tr("settings.widget-lane-start");
      }
      if (lane == "center") {
        return i18n::tr("settings.widget-lane-center");
      }
      if (lane == "end") {
        return i18n::tr("settings.widget-lane-end");
      }
      return std::string(lane);
    }

    std::vector<std::string> barWidgetItemsForPath(const Config& cfg, const std::vector<std::string>& path) {
      if (!isBarWidgetListPath(path) || path.size() < 3) {
        return {};
      }

      const auto* bar = findBar(cfg, path[1]);
      if (bar == nullptr) {
        return {};
      }

      const auto& lane = path.back();
      if (path.size() >= 5 && path[2] == "monitor") {
        const auto* ovr = findMonitorOverride(*bar, path[3]);
        if (ovr != nullptr) {
          if (lane == "start") {
            return ovr->startWidgets.value_or(bar->startWidgets);
          }
          if (lane == "center") {
            return ovr->centerWidgets.value_or(bar->centerWidgets);
          }
          if (lane == "end") {
            return ovr->endWidgets.value_or(bar->endWidgets);
          }
        }
      }

      if (lane == "start") {
        return bar->startWidgets;
      }
      if (lane == "center") {
        return bar->centerWidgets;
      }
      if (lane == "end") {
        return bar->endWidgets;
      }
      return {};
    }

    ThemeColor widgetBadgeColor(WidgetReferenceKind kind) {
      switch (kind) {
      case WidgetReferenceKind::BuiltIn:
        return roleColor(ColorRole::Primary, 0.16f);
      case WidgetReferenceKind::Named:
        return roleColor(ColorRole::Secondary, 0.18f);
      case WidgetReferenceKind::Unknown:
        return roleColor(ColorRole::Error, 0.16f);
      }
      return roleColor(ColorRole::OnSurfaceVariant, 0.12f);
    }

    const WidgetTypeSpec* widgetTypeSpecForType(std::string_view type) {
      for (const auto& spec : widgetTypeSpecs()) {
        if (spec.type == type) {
          return &spec;
        }
      }
      return nullptr;
    }

    bool isCreateInstanceValue(std::string_view value) { return value.starts_with(kCreateInstancePrefix); }

    std::string createInstanceTypeFromValue(std::string_view value) {
      if (!isCreateInstanceValue(value)) {
        return {};
      }
      value.remove_prefix(kCreateInstancePrefix.size());
      return std::string(value);
    }

    std::vector<SearchPickerOption> widgetPickerOptions(const Config& cfg) {
      std::vector<SearchPickerOption> options;
      const auto entries = widgetPickerEntries(cfg);
      options.reserve(entries.size() * 2);
      for (const auto& entry : entries) {
        options.push_back(SearchPickerOption{.value = entry.value,
                                             .label = entry.label,
                                             .description = entry.description,
                                             .category = entry.category,
                                             .enabled = true});
        if (entry.kind != WidgetReferenceKind::BuiltIn) {
          continue;
        }
        const auto* spec = widgetTypeSpecForType(entry.value);
        if (spec == nullptr || !spec->supportsMultipleInstances) {
          continue;
        }
        options.push_back(SearchPickerOption{
            .value = std::string(kCreateInstancePrefix) + entry.value,
            .label = i18n::tr("settings.widget-picker-create-label", "label", entry.label),
            .description = i18n::tr("settings.widget-picker-create-desc", "type", entry.value),
            .category = i18n::tr("settings.widget-kind-new-instance"),
            .enabled = true,
        });
      }
      return options;
    }

    void collectWidgetReferenceNames(const std::vector<std::string>& widgets, std::unordered_set<std::string>& seen) {
      for (const auto& widget : widgets) {
        seen.insert(widget);
      }
    }

    bool widgetReferenceNameExists(const Config& cfg, std::string_view name) {
      const std::string key(name);
      if (isBuiltInWidgetType(name) || cfg.widgets.contains(key)) {
        return true;
      }

      std::unordered_set<std::string> seen;
      for (const auto& bar : cfg.bars) {
        collectWidgetReferenceNames(bar.startWidgets, seen);
        collectWidgetReferenceNames(bar.centerWidgets, seen);
        collectWidgetReferenceNames(bar.endWidgets, seen);
        for (const auto& ovr : bar.monitorOverrides) {
          if (ovr.startWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.startWidgets, seen);
          }
          if (ovr.centerWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.centerWidgets, seen);
          }
          if (ovr.endWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.endWidgets, seen);
          }
        }
      }
      return seen.contains(key);
    }

    std::string normalizedWidgetInstanceBase(std::string_view type) {
      std::string out;
      out.reserve(type.size());
      bool lastUnderscore = false;
      for (const unsigned char c : type) {
        if (std::isalnum(c)) {
          out.push_back(static_cast<char>(std::tolower(c)));
          lastUnderscore = false;
        } else if (!lastUnderscore && !out.empty()) {
          out.push_back('_');
          lastUnderscore = true;
        }
      }
      while (!out.empty() && out.back() == '_') {
        out.pop_back();
      }
      return out.empty() ? std::string("widget") : out;
    }

    std::string nextWidgetInstanceId(const Config& cfg, std::string_view type) {
      const std::string base = normalizedWidgetInstanceBase(type);
      for (std::size_t index = 2; index < 10000; ++index) {
        const std::string candidate = base + "_" + std::to_string(index);
        if (!widgetReferenceNameExists(cfg, candidate)) {
          return candidate;
        }
      }
      return base + "_custom";
    }

    bool removeWidgetReference(std::vector<std::string>& items, std::string_view widgetName) {
      const auto oldSize = items.size();
      const std::string key(widgetName);
      items.erase(std::remove(items.begin(), items.end(), key), items.end());
      return items.size() != oldSize;
    }

    void appendReferenceRemoval(std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>& overrides,
                                std::vector<std::string> path, std::vector<std::string> items,
                                std::string_view widgetName) {
      if (removeWidgetReference(items, widgetName)) {
        overrides.push_back({std::move(path), std::move(items)});
      }
    }

    std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>
    widgetReferenceRemovalOverrides(const Config& cfg, std::string_view widgetName) {
      std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides;
      for (const auto& bar : cfg.bars) {
        appendReferenceRemoval(overrides, {"bar", bar.name, "start"}, bar.startWidgets, widgetName);
        appendReferenceRemoval(overrides, {"bar", bar.name, "center"}, bar.centerWidgets, widgetName);
        appendReferenceRemoval(overrides, {"bar", bar.name, "end"}, bar.endWidgets, widgetName);

        for (const auto& ovr : bar.monitorOverrides) {
          const std::vector<std::string> prefix = {"bar", bar.name, "monitor", ovr.match};
          if (ovr.startWidgets.has_value()) {
            appendReferenceRemoval(overrides, {prefix[0], prefix[1], prefix[2], prefix[3], "start"}, *ovr.startWidgets,
                                   widgetName);
          }
          if (ovr.centerWidgets.has_value()) {
            appendReferenceRemoval(overrides, {prefix[0], prefix[1], prefix[2], prefix[3], "center"},
                                   *ovr.centerWidgets, widgetName);
          }
          if (ovr.endWidgets.has_value()) {
            appendReferenceRemoval(overrides, {prefix[0], prefix[1], prefix[2], prefix[3], "end"}, *ovr.endWidgets,
                                   widgetName);
          }
        }
      }
      return overrides;
    }

    std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>
    widgetReferenceRenameOverrides(const Config& cfg, std::string_view oldName, std::string_view newName) {
      std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides;
      for (const auto& bar : cfg.bars) {
        auto appendRename = [&](std::vector<std::string> path, std::vector<std::string> items) {
          bool changed = false;
          for (auto& item : items) {
            if (item == oldName) {
              item = std::string(newName);
              changed = true;
            }
          }
          if (changed) {
            overrides.push_back({std::move(path), std::move(items)});
          }
        };

        appendRename({"bar", bar.name, "start"}, bar.startWidgets);
        appendRename({"bar", bar.name, "center"}, bar.centerWidgets);
        appendRename({"bar", bar.name, "end"}, bar.endWidgets);

        for (const auto& ovr : bar.monitorOverrides) {
          const std::vector<std::string> prefix = {"bar", bar.name, "monitor", ovr.match};
          if (ovr.startWidgets.has_value()) {
            appendRename({prefix[0], prefix[1], prefix[2], prefix[3], "start"}, *ovr.startWidgets);
          }
          if (ovr.centerWidgets.has_value()) {
            appendRename({prefix[0], prefix[1], prefix[2], prefix[3], "center"}, *ovr.centerWidgets);
          }
          if (ovr.endWidgets.has_value()) {
            appendRename({prefix[0], prefix[1], prefix[2], prefix[3], "end"}, *ovr.endWidgets);
          }
        }
      }
      return overrides;
    }

    bool isNamedWidgetInstance(const Config& cfg, std::string_view widgetName) {
      return cfg.widgets.contains(std::string(widgetName)) && !isBuiltInWidgetType(widgetName);
    }

    bool isGuiManagedNamedWidgetInstance(const BarWidgetEditorContext& ctx, std::string_view widgetName) {
      return isNamedWidgetInstance(ctx.config, widgetName) && ctx.configService != nullptr &&
             ctx.configService->hasOverride({"widget", std::string(widgetName)});
    }

    bool isValidWidgetInstanceId(std::string_view id) {
      if (id.empty()) {
        return false;
      }
      for (const unsigned char c : id) {
        if (!std::isalnum(c) && c != '_' && c != '-') {
          return false;
        }
      }
      return true;
    }

    bool canRenameWidgetInstance(const Config& cfg, std::string_view oldName, std::string_view newName) {
      return isValidWidgetInstanceId(newName) && oldName != newName && !widgetReferenceNameExists(cfg, newName);
    }

    bool canCreateWidgetInstance(const Config& cfg, std::string_view name) {
      return isValidWidgetInstanceId(name) && !widgetReferenceNameExists(cfg, name);
    }

    std::vector<std::string> widgetSettingPath(std::string widgetName, std::string settingKey) {
      return {"widget", std::move(widgetName), std::move(settingKey)};
    }

    WidgetSettingValue widgetSettingValue(const Config& cfg, std::string_view widgetName,
                                          const WidgetSettingSpec& spec) {
      if (const auto it = cfg.widgets.find(std::string(widgetName)); it != cfg.widgets.end()) {
        if (const auto settingIt = it->second.settings.find(spec.key); settingIt != it->second.settings.end()) {
          return settingIt->second;
        }
      }
      return spec.defaultValue;
    }

    bool settingValueAsBool(const WidgetSettingValue& value) {
      if (const auto* v = std::get_if<bool>(&value)) {
        return *v;
      }
      return false;
    }

    std::int64_t settingValueAsInt(const WidgetSettingValue& value) {
      if (const auto* v = std::get_if<std::int64_t>(&value)) {
        return *v;
      }
      if (const auto* v = std::get_if<double>(&value)) {
        return static_cast<std::int64_t>(std::llround(*v));
      }
      return std::int64_t{0};
    }

    double settingValueAsDouble(const WidgetSettingValue& value) {
      if (const auto* v = std::get_if<double>(&value)) {
        return *v;
      }
      if (const auto* v = std::get_if<std::int64_t>(&value)) {
        return static_cast<double>(*v);
      }
      return 0.0;
    }

    std::string settingValueAsString(const WidgetSettingValue& value) {
      if (const auto* v = std::get_if<std::string>(&value)) {
        return *v;
      }
      return {};
    }

    std::vector<std::string> settingValueAsStringList(const WidgetSettingValue& value) {
      if (const auto* v = std::get_if<std::vector<std::string>>(&value)) {
        return *v;
      }
      return {};
    }

    void addWidgetSettingsPanel(Flex& item, std::string widgetName, const BarWidgetEditorContext& ctx) {
      const auto widgetType = widgetTypeForReference(ctx.config, widgetName);
      if (widgetType.empty()) {
        return;
      }

      auto specs = widgetSettingSpecs(widgetType);
      if (specs.empty()) {
        return;
      }

      auto panel = std::make_unique<Flex>();
      panel->setDirection(FlexDirection::Vertical);
      panel->setAlign(FlexAlign::Stretch);
      panel->setGap(Style::spaceXs * ctx.scale);
      panel->setPadding(Style::spaceSm * ctx.scale);
      panel->setRadius(Style::radiusSm * ctx.scale);
      panel->setBackground(roleColor(ColorRole::SurfaceVariant, 0.55f));
      panel->setBorderColor(roleColor(ColorRole::Outline, 0.22f));
      panel->setBorderWidth(Style::borderWidth);

      auto panelHeader = std::make_unique<Flex>();
      panelHeader->setDirection(FlexDirection::Horizontal);
      panelHeader->setAlign(FlexAlign::Center);
      panelHeader->setGap(Style::spaceXs * ctx.scale);
      panelHeader->addChild(makeLabel(i18n::tr("settings.widget-settings"), Style::fontSizeCaption * ctx.scale,
                                      roleColor(ColorRole::OnSurface), true));
      panelHeader->addChild(
          makeLabel(widgetType, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant), false));
      panel->addChild(std::move(panelHeader));

      std::size_t visibleSpecs = 0;
      for (const auto& spec : specs) {
        if (spec.advanced && !ctx.showAdvanced) {
          continue;
        }
        const auto path = widgetSettingPath(widgetName, spec.key);
        const bool overridden = ctx.configService != nullptr && ctx.configService->hasOverride(path);
        if (ctx.showOverriddenOnly && !overridden) {
          continue;
        }

        const auto value = widgetSettingValue(ctx.config, widgetName, spec);
        SettingEntry entry{
            .section = "bar",
            .group = "widget-settings",
            .title = i18n::tr(spec.labelKey),
            .subtitle = i18n::tr(spec.descriptionKey),
            .path = path,
            .control = TextSetting{},
            .advanced = spec.advanced,
            .searchText = {},
        };

        switch (spec.valueType) {
        case WidgetSettingValueType::Bool:
          ctx.makeRow(*panel, entry, ctx.makeToggle(settingValueAsBool(value), path));
          break;
        case WidgetSettingValueType::Int: {
          const auto minValue = static_cast<float>(spec.minValue.value_or(0.0));
          const auto maxValue = static_cast<float>(spec.maxValue.value_or(100.0));
          ctx.makeRow(*panel, entry,
                      ctx.makeSlider(static_cast<float>(settingValueAsInt(value)), minValue, maxValue,
                                     static_cast<float>(spec.step), path, true));
          break;
        }
        case WidgetSettingValueType::Double: {
          const auto minValue = static_cast<float>(spec.minValue.value_or(0.0));
          const auto maxValue = static_cast<float>(spec.maxValue.value_or(1.0));
          ctx.makeRow(*panel, entry,
                      ctx.makeSlider(static_cast<float>(settingValueAsDouble(value)), minValue, maxValue,
                                     static_cast<float>(spec.step), path, false));
          break;
        }
        case WidgetSettingValueType::String:
          ctx.makeRow(*panel, entry, ctx.makeText(settingValueAsString(value), {}, path));
          break;
        case WidgetSettingValueType::StringList:
          ctx.makeListBlock(*panel, entry, ListSetting{settingValueAsStringList(value)});
          break;
        case WidgetSettingValueType::Select: {
          std::vector<SelectOption> options;
          options.reserve(spec.options.size());
          for (const auto& option : spec.options) {
            options.push_back(SelectOption{std::string(option.value), i18n::tr(option.labelKey)});
          }
          ctx.makeRow(*panel, entry,
                      ctx.makeSelect(SelectSetting{std::move(options), settingValueAsString(value)}, path));
          break;
        }
        }
        ++visibleSpecs;
      }

      if (visibleSpecs == 0) {
        panel->addChild(makeLabel(i18n::tr("settings.widget-settings-empty"), Style::fontSizeCaption * ctx.scale,
                                  roleColor(ColorRole::OnSurfaceVariant), false));
      }

      item.addChild(std::move(panel));
    }

  } // namespace

  bool isBarWidgetListPath(const std::vector<std::string>& path) {
    if (path.size() < 3 || path.front() != "bar") {
      return false;
    }
    const auto& key = path.back();
    return key == "start" || key == "center" || key == "end";
  }

  bool isFirstBarWidgetListPath(const std::vector<std::string>& path) {
    return isBarWidgetListPath(path) && path.back() == "start";
  }

  void addBarWidgetLaneEditor(Flex& section, const SettingEntry& entry, const BarWidgetEditorContext& ctx) {
    if (!isFirstBarWidgetListPath(entry.path)) {
      return;
    }

    auto block = std::make_unique<Flex>();
    block->setDirection(FlexDirection::Vertical);
    block->setAlign(FlexAlign::Stretch);
    block->setGap(Style::spaceSm * ctx.scale);
    block->setPadding(2.0f * ctx.scale, 0.0f);

    auto titleRow = std::make_unique<Flex>();
    titleRow->setDirection(FlexDirection::Horizontal);
    titleRow->setAlign(FlexAlign::Center);
    titleRow->setGap(Style::spaceSm * ctx.scale);
    titleRow->addChild(makeLabel(i18n::tr("settings.bar-widget-editor"), Style::fontSizeBody * ctx.scale,
                                 roleColor(ColorRole::OnSurface), false));
    block->addChild(std::move(titleRow));

    block->addChild(makeLabel(i18n::tr("settings.bar-widget-editor-desc"), Style::fontSizeCaption * ctx.scale,
                              roleColor(ColorRole::OnSurfaceVariant), false));

    auto lanes = std::make_unique<Flex>();
    lanes->setDirection(FlexDirection::Horizontal);
    lanes->setAlign(FlexAlign::Stretch);
    lanes->setGap(Style::spaceSm * ctx.scale);
    lanes->setFillParentMainAxis(true);

    static constexpr std::string_view kLaneKeys[] = {"start", "center", "end"};
    for (const auto laneKey : kLaneKeys) {
      auto lanePath = pathWithLastSegment(entry.path, std::string(laneKey));
      const auto laneItems = barWidgetItemsForPath(ctx.config, lanePath);
      const bool overridden = ctx.configService != nullptr && ctx.configService->hasOverride(lanePath);

      auto lane = std::make_unique<Flex>();
      lane->setDirection(FlexDirection::Vertical);
      lane->setAlign(FlexAlign::Stretch);
      lane->setGap(Style::spaceXs * ctx.scale);
      lane->setPadding(Style::spaceSm * ctx.scale);
      lane->setRadius(Style::radiusMd * ctx.scale);
      lane->setBackground(roleColor(ColorRole::SurfaceVariant, 0.45f));
      lane->setBorderColor(roleColor(ColorRole::Outline, 0.35f));
      lane->setBorderWidth(Style::borderWidth);
      lane->setFlexGrow(1.0f);
      lane->setMinWidth(180.0f * ctx.scale);

      auto laneHeader = std::make_unique<Flex>();
      laneHeader->setDirection(FlexDirection::Horizontal);
      laneHeader->setAlign(FlexAlign::Center);
      laneHeader->setGap(Style::spaceXs * ctx.scale);
      laneHeader->addChild(
          makeLabel(laneLabel(laneKey), Style::fontSizeBody * ctx.scale, roleColor(ColorRole::OnSurface), true));
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * ctx.scale, Style::spaceXs * ctx.scale);
        badge->setRadius(Style::radiusSm * ctx.scale);
        badge->setBackground(roleColor(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * ctx.scale,
                                  roleColor(ColorRole::Primary), true));
        laneHeader->addChild(std::move(badge));
      }
      auto laneSpacer = std::make_unique<Flex>();
      laneSpacer->setFlexGrow(1.0f);
      laneHeader->addChild(std::move(laneSpacer));
      if (overridden) {
        laneHeader->addChild(ctx.makeResetButton(lanePath));
      }
      lane->addChild(std::move(laneHeader));

      for (std::size_t i = 0; i < laneItems.size(); ++i) {
        const auto info = widgetReferenceInfo(ctx.config, laneItems[i]);
        auto item = std::make_unique<Flex>();
        item->setDirection(FlexDirection::Vertical);
        item->setAlign(FlexAlign::Stretch);
        item->setGap(Style::spaceXs * ctx.scale);
        item->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
        item->setRadius(Style::radiusSm * ctx.scale);
        item->setBackground(roleColor(ColorRole::Surface, 0.72f));
        item->setBorderColor(roleColor(ColorRole::Outline, 0.22f));
        item->setBorderWidth(Style::borderWidth);

        auto itemTop = std::make_unique<Flex>();
        itemTop->setDirection(FlexDirection::Horizontal);
        itemTop->setAlign(FlexAlign::Center);
        itemTop->setGap(Style::spaceXs * ctx.scale);
        itemTop->addChild(
            makeLabel(info.title, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurface), true));
        auto itemSpacer = std::make_unique<Flex>();
        itemSpacer->setFlexGrow(1.0f);
        itemTop->addChild(std::move(itemSpacer));
        auto kindBadge = std::make_unique<Flex>();
        kindBadge->setAlign(FlexAlign::Center);
        kindBadge->setPadding(1.0f * ctx.scale, Style::spaceXs * ctx.scale);
        kindBadge->setRadius(Style::radiusSm * ctx.scale);
        kindBadge->setBackground(widgetBadgeColor(info.kind));
        kindBadge->addChild(
            makeLabel(info.badge, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurface), true));
        itemTop->addChild(std::move(kindBadge));
        item->addChild(std::move(itemTop));

        item->addChild(
            makeLabel(info.detail, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant), false));

        auto actions = std::make_unique<Flex>();
        actions->setDirection(FlexDirection::Horizontal);
        actions->setAlign(FlexAlign::Center);
        actions->setGap(Style::spaceXs * ctx.scale);

        const auto widgetName = laneItems[i];
        const bool editableWidget = !widgetTypeForReference(ctx.config, widgetName).empty();
        if (editableWidget) {
          auto editBtn = std::make_unique<Button>();
          editBtn->setGlyph("settings");
          editBtn->setVariant(ctx.editingWidgetName == widgetName ? ButtonVariant::Default : ButtonVariant::Ghost);
          editBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          editBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          editBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          editBtn->setPadding(Style::spaceXs * ctx.scale);
          editBtn->setRadius(Style::radiusSm * ctx.scale);
          editBtn->setOnClick(
              [&editingWidgetName = ctx.editingWidgetName, &openWidgetPickerPath = ctx.openWidgetPickerPath, widgetName,
               &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, &renamingWidgetName = ctx.renamingWidgetName,
               &creatingWidgetType = ctx.creatingWidgetType, requestRebuild = ctx.requestRebuild]() {
                editingWidgetName = editingWidgetName == widgetName ? std::string{} : widgetName;
                openWidgetPickerPath.clear();
                pendingDeleteWidgetName.clear();
                renamingWidgetName.clear();
                creatingWidgetType.clear();
                requestRebuild();
              });
          actions->addChild(std::move(editBtn));
        }

        if (isGuiManagedNamedWidgetInstance(ctx, widgetName)) {
          auto renameBtn = std::make_unique<Button>();
          renameBtn->setText(i18n::tr("settings.rename-widget-instance"));
          renameBtn->setVariant(ctx.renamingWidgetName == widgetName ? ButtonVariant::Default : ButtonVariant::Ghost);
          renameBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          renameBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          renameBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          renameBtn->setRadius(Style::radiusSm * ctx.scale);
          renameBtn->setOnClick(
              [&renamingWidgetName = ctx.renamingWidgetName, &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
               &openWidgetPickerPath = ctx.openWidgetPickerPath, &creatingWidgetType = ctx.creatingWidgetType,
               widgetName, requestRebuild = ctx.requestRebuild]() {
                renamingWidgetName = renamingWidgetName == widgetName ? std::string{} : widgetName;
                pendingDeleteWidgetName.clear();
                openWidgetPickerPath.clear();
                creatingWidgetType.clear();
                requestRebuild();
              });
          actions->addChild(std::move(renameBtn));

          const bool pendingDelete = ctx.pendingDeleteWidgetName == widgetName;
          auto deleteBtn = std::make_unique<Button>();
          deleteBtn->setGlyph("trash");
          deleteBtn->setVariant(pendingDelete ? ButtonVariant::Default : ButtonVariant::Ghost);
          if (pendingDelete) {
            deleteBtn->setText(i18n::tr("settings.delete-widget-instance"));
            deleteBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          }
          deleteBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          deleteBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          deleteBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          deleteBtn->setPadding(Style::spaceXs * ctx.scale);
          deleteBtn->setRadius(Style::radiusSm * ctx.scale);
          deleteBtn->setOnClick([&editingWidgetName = ctx.editingWidgetName,
                                 &openWidgetPickerPath = ctx.openWidgetPickerPath, config = ctx.config, widgetName,
                                 &renamingWidgetName = ctx.renamingWidgetName,
                                 &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
                                 &creatingWidgetType = ctx.creatingWidgetType, clearOverride = ctx.clearOverride,
                                 requestRebuild = ctx.requestRebuild, setOverrides = ctx.setOverrides]() {
            openWidgetPickerPath.clear();
            renamingWidgetName.clear();
            creatingWidgetType.clear();
            if (pendingDeleteWidgetName != widgetName) {
              pendingDeleteWidgetName = widgetName;
              requestRebuild();
              return;
            }

            pendingDeleteWidgetName.clear();
            if (editingWidgetName == widgetName) {
              editingWidgetName.clear();
            }

            auto referenceRemovals = widgetReferenceRemovalOverrides(config, widgetName);
            if (!referenceRemovals.empty()) {
              setOverrides(std::move(referenceRemovals));
            }
            clearOverride({"widget", widgetName});
          });
          actions->addChild(std::move(deleteBtn));
        }

        if (i > 0) {
          auto upBtn = std::make_unique<Button>();
          upBtn->setGlyph("chevron-up");
          upBtn->setVariant(ButtonVariant::Ghost);
          upBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          upBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          upBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          upBtn->setPadding(Style::spaceXs * ctx.scale);
          upBtn->setRadius(Style::radiusSm * ctx.scale);
          auto items = laneItems;
          auto path = lanePath;
          upBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i - 1]);
            setOverride(path, items);
          });
          actions->addChild(std::move(upBtn));
        }
        if (i + 1 < laneItems.size()) {
          auto downBtn = std::make_unique<Button>();
          downBtn->setGlyph("chevron-down");
          downBtn->setVariant(ButtonVariant::Ghost);
          downBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          downBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          downBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          downBtn->setPadding(Style::spaceXs * ctx.scale);
          downBtn->setRadius(Style::radiusSm * ctx.scale);
          auto items = laneItems;
          auto path = lanePath;
          downBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i + 1]);
            setOverride(path, items);
          });
          actions->addChild(std::move(downBtn));
        }

        for (const auto targetLane : kLaneKeys) {
          if (targetLane == laneKey) {
            continue;
          }
          auto moveBtn = std::make_unique<Button>();
          moveBtn->setText(laneLabel(targetLane));
          moveBtn->setVariant(ButtonVariant::Ghost);
          moveBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          moveBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          moveBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          moveBtn->setRadius(Style::radiusSm * ctx.scale);
          auto sourceItems = laneItems;
          auto sourcePath = lanePath;
          auto targetPath = pathWithLastSegment(entry.path, std::string(targetLane));
          auto targetItems = barWidgetItemsForPath(ctx.config, targetPath);
          moveBtn->setOnClick(
              [setOverrides = ctx.setOverrides, sourceItems, sourcePath, targetItems, targetPath, i]() mutable {
                if (i >= sourceItems.size()) {
                  return;
                }
                auto widget = sourceItems[i];
                sourceItems.erase(sourceItems.begin() + static_cast<std::ptrdiff_t>(i));
                targetItems.push_back(std::move(widget));
                setOverrides({{sourcePath, sourceItems}, {targetPath, targetItems}});
              });
          actions->addChild(std::move(moveBtn));
        }

        auto removeBtn = std::make_unique<Button>();
        removeBtn->setGlyph("close");
        removeBtn->setVariant(ButtonVariant::Ghost);
        removeBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
        removeBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
        removeBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
        removeBtn->setPadding(Style::spaceXs * ctx.scale);
        removeBtn->setRadius(Style::radiusSm * ctx.scale);
        auto items = laneItems;
        auto path = lanePath;
        removeBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
          items.erase(items.begin() + static_cast<std::ptrdiff_t>(i));
          setOverride(path, items);
        });
        actions->addChild(std::move(removeBtn));

        item->addChild(std::move(actions));
        if (ctx.renamingWidgetName == widgetName) {
          auto renameRow = std::make_unique<Flex>();
          renameRow->setDirection(FlexDirection::Horizontal);
          renameRow->setAlign(FlexAlign::Center);
          renameRow->setGap(Style::spaceXs * ctx.scale);

          auto input = std::make_unique<Input>();
          input->setValue(widgetName);
          input->setPlaceholder(i18n::tr("settings.rename-widget-placeholder"));
          input->setFontSize(Style::fontSizeCaption * ctx.scale);
          input->setControlHeight(Style::controlHeightSm * ctx.scale);
          input->setHorizontalPadding(Style::spaceXs * ctx.scale);
          input->setSize(140.0f * ctx.scale, Style::controlHeightSm * ctx.scale);
          input->setFlexGrow(1.0f);
          auto* inputPtr = input.get();

          auto doRename = [&editingWidgetName = ctx.editingWidgetName, &renamingWidgetName = ctx.renamingWidgetName,
                           config = ctx.config, renameWidgetInstance = ctx.renameWidgetInstance,
                           widgetName](std::string newName) mutable {
            if (!canRenameWidgetInstance(config, widgetName, newName)) {
              return;
            }
            auto referenceRenames = widgetReferenceRenameOverrides(config, widgetName, newName);
            renamingWidgetName.clear();
            if (editingWidgetName == widgetName) {
              editingWidgetName = newName;
            }
            renameWidgetInstance(widgetName, std::move(newName), std::move(referenceRenames));
          };

          input->setOnSubmit([doRename](const std::string& text) mutable { doRename(text); });

          auto saveBtn = std::make_unique<Button>();
          saveBtn->setText(i18n::tr("settings.rename-widget-save"));
          saveBtn->setVariant(ButtonVariant::Default);
          saveBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          saveBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          saveBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          saveBtn->setRadius(Style::radiusSm * ctx.scale);
          saveBtn->setOnClick([doRename, inputPtr]() mutable { doRename(inputPtr->value()); });

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setGlyph("close");
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&renamingWidgetName = ctx.renamingWidgetName, requestRebuild = ctx.requestRebuild]() {
            renamingWidgetName.clear();
            requestRebuild();
          });

          renameRow->addChild(std::move(input));
          renameRow->addChild(std::move(saveBtn));
          renameRow->addChild(std::move(cancelBtn));
          item->addChild(std::move(renameRow));
        }
        if (ctx.editingWidgetName == widgetName) {
          addWidgetSettingsPanel(*item, widgetName, ctx);
        }
        lane->addChild(std::move(item));
      }

      const std::string pickerKey = pathKey(lanePath);
      auto addBtn = std::make_unique<Button>();
      addBtn->setText(i18n::tr("settings.add-widget"));
      addBtn->setGlyph("add");
      addBtn->setVariant(ButtonVariant::Ghost);
      addBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
      addBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
      addBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
      addBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
      addBtn->setRadius(Style::radiusSm * ctx.scale);
      addBtn->setOnClick([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                          &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, pickerKey,
                          &creatingWidgetType = ctx.creatingWidgetType, requestRebuild = ctx.requestRebuild]() {
        openWidgetPickerPath = openWidgetPickerPath == pickerKey ? std::string{} : pickerKey;
        pendingDeleteWidgetName.clear();
        creatingWidgetType.clear();
        requestRebuild();
      });
      lane->addChild(std::move(addBtn));

      if (ctx.openWidgetPickerPath == pickerKey) {
        if (!ctx.creatingWidgetType.empty()) {
          const std::string widgetType = ctx.creatingWidgetType;
          auto createPanel = std::make_unique<Flex>();
          createPanel->setDirection(FlexDirection::Vertical);
          createPanel->setAlign(FlexAlign::Stretch);
          createPanel->setGap(Style::spaceXs * ctx.scale);
          createPanel->setPadding(Style::spaceSm * ctx.scale);
          createPanel->setRadius(Style::radiusSm * ctx.scale);
          createPanel->setBackground(roleColor(ColorRole::Surface, 0.72f));
          createPanel->setBorderColor(roleColor(ColorRole::Outline, 0.22f));
          createPanel->setBorderWidth(Style::borderWidth);

          createPanel->addChild(makeLabel(i18n::tr("settings.create-widget-instance-title", "type", widgetType),
                                          Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurface), true));

          auto createRow = std::make_unique<Flex>();
          createRow->setDirection(FlexDirection::Horizontal);
          createRow->setAlign(FlexAlign::Center);
          createRow->setGap(Style::spaceXs * ctx.scale);

          auto input = std::make_unique<Input>();
          input->setValue(nextWidgetInstanceId(ctx.config, widgetType));
          input->setPlaceholder(i18n::tr("settings.rename-widget-placeholder"));
          input->setFontSize(Style::fontSizeCaption * ctx.scale);
          input->setControlHeight(Style::controlHeightSm * ctx.scale);
          input->setHorizontalPadding(Style::spaceXs * ctx.scale);
          input->setSize(140.0f * ctx.scale, Style::controlHeightSm * ctx.scale);
          input->setFlexGrow(1.0f);
          auto* inputPtr = input.get();

          auto items = laneItems;
          auto path = lanePath;
          auto doCreate = [&openWidgetPickerPath = ctx.openWidgetPickerPath, &editingWidgetName = ctx.editingWidgetName,
                           &creatingWidgetType = ctx.creatingWidgetType, config = ctx.config,
                           setOverrides = ctx.setOverrides, items, path, widgetType](std::string instanceId) mutable {
            if (!canCreateWidgetInstance(config, instanceId)) {
              return;
            }
            items.push_back(instanceId);
            openWidgetPickerPath.clear();
            creatingWidgetType.clear();
            editingWidgetName = instanceId;
            setOverrides({{{"widget", instanceId, "type"}, widgetType}, {path, items}});
          };

          input->setOnSubmit([doCreate](const std::string& text) mutable { doCreate(text); });

          auto createBtn = std::make_unique<Button>();
          createBtn->setText(i18n::tr("settings.create-widget-instance-save"));
          createBtn->setVariant(ButtonVariant::Default);
          createBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          createBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          createBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          createBtn->setRadius(Style::radiusSm * ctx.scale);
          createBtn->setOnClick([doCreate, inputPtr]() mutable { doCreate(inputPtr->value()); });

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setGlyph("close");
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&creatingWidgetType = ctx.creatingWidgetType, requestRebuild = ctx.requestRebuild]() {
            creatingWidgetType.clear();
            requestRebuild();
          });

          createRow->addChild(std::move(input));
          createRow->addChild(std::move(createBtn));
          createRow->addChild(std::move(cancelBtn));
          createPanel->addChild(std::move(createRow));
          lane->addChild(std::move(createPanel));
          lanes->addChild(std::move(lane));
          continue;
        }

        auto picker = std::make_unique<SearchPicker>();
        picker->setPlaceholder(i18n::tr("settings.widget-picker-placeholder"));
        picker->setEmptyText(i18n::tr("settings.widget-picker-empty"));
        picker->setOptions(widgetPickerOptions(ctx.config));
        picker->setSize(320.0f * ctx.scale, 250.0f * ctx.scale);
        auto items = laneItems;
        auto path = lanePath;
        picker->setOnActivated(
            [&openWidgetPickerPath = ctx.openWidgetPickerPath, &editingWidgetName = ctx.editingWidgetName,
             &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, &creatingWidgetType = ctx.creatingWidgetType,
             setOverride = ctx.setOverride, requestRebuild = ctx.requestRebuild, items,
             path](const SearchPickerOption& option) mutable {
              if (!option.value.empty()) {
                pendingDeleteWidgetName.clear();
                if (const auto type = createInstanceTypeFromValue(option.value); !type.empty()) {
                  creatingWidgetType = type;
                  editingWidgetName.clear();
                  requestRebuild();
                  return;
                }

                creatingWidgetType.clear();
                items.push_back(option.value);
                openWidgetPickerPath.clear();
                setOverride(path, items);
              }
            });
        picker->setOnCancel([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                             &creatingWidgetType = ctx.creatingWidgetType, requestRebuild = ctx.requestRebuild]() {
          openWidgetPickerPath.clear();
          creatingWidgetType.clear();
          requestRebuild();
        });
        lane->addChild(std::move(picker));
      }

      lanes->addChild(std::move(lane));
    }

    block->addChild(std::move(lanes));
    section.addChild(std::move(block));
  }

} // namespace settings

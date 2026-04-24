#include "shell/settings/bar_widget_editor.h"

#include "i18n/i18n.h"
#include "render/scene/node.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
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
          editBtn->setOnClick([&editingWidgetName = ctx.editingWidgetName,
                               &openWidgetPickerPath = ctx.openWidgetPickerPath, widgetName,
                               requestRebuild = ctx.requestRebuild]() {
            editingWidgetName = editingWidgetName == widgetName ? std::string{} : widgetName;
            openWidgetPickerPath.clear();
            requestRebuild();
          });
          actions->addChild(std::move(editBtn));
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
      addBtn->setOnClick(
          [&openWidgetPickerPath = ctx.openWidgetPickerPath, pickerKey, requestRebuild = ctx.requestRebuild]() {
            openWidgetPickerPath = openWidgetPickerPath == pickerKey ? std::string{} : pickerKey;
            requestRebuild();
          });
      lane->addChild(std::move(addBtn));

      if (ctx.openWidgetPickerPath == pickerKey) {
        auto picker = std::make_unique<SearchPicker>();
        picker->setPlaceholder(i18n::tr("settings.widget-picker-placeholder"));
        picker->setEmptyText(i18n::tr("settings.widget-picker-empty"));
        picker->setOptions(widgetPickerOptions(ctx.config));
        picker->setSize(320.0f * ctx.scale, 250.0f * ctx.scale);
        auto items = laneItems;
        auto path = lanePath;
        picker->setOnActivated([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                                &editingWidgetName = ctx.editingWidgetName, config = ctx.config,
                                setOverride = ctx.setOverride, setOverrides = ctx.setOverrides, items,
                                path](const SearchPickerOption& option) mutable {
          if (!option.value.empty()) {
            if (const auto type = createInstanceTypeFromValue(option.value); !type.empty()) {
              const auto instanceId = nextWidgetInstanceId(config, type);
              items.push_back(instanceId);
              openWidgetPickerPath.clear();
              editingWidgetName = instanceId;
              setOverrides({{{"widget", instanceId, "type"}, type}, {path, items}});
              return;
            }

            items.push_back(option.value);
            openWidgetPickerPath.clear();
            setOverride(path, items);
          }
        });
        picker->setOnCancel([&openWidgetPickerPath = ctx.openWidgetPickerPath, requestRebuild = ctx.requestRebuild]() {
          openWidgetPickerPath.clear();
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

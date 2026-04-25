#include "shell/settings/bar_widget_editor.h"

#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "render/scene/node.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/controls/box.h"
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
#include <format>
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
    constexpr float kDragStartThresholdPx = 6.0f;

    struct LaneWidgetDragState {
      bool active = false;
      bool moved = false;
      float startLocalY = 0.0f;
      float lastLocalY = 0.0f;
    };

    std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ThemeColor& color,
                                     bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

    void closeInspector(std::string& openWidgetPickerPath, std::string& editingWidgetName,
                        std::string& renamingWidgetName, std::string& pendingDeleteWidgetName,
                        std::string& pendingDeleteWidgetSettingPath, std::string& creatingWidgetType,
                        const std::function<void()>& resetContentScroll, const std::function<void()>& requestRebuild) {
      openWidgetPickerPath.clear();
      editingWidgetName.clear();
      renamingWidgetName.clear();
      pendingDeleteWidgetName.clear();
      pendingDeleteWidgetSettingPath.clear();
      creatingWidgetType.clear();
      if (resetContentScroll) {
        resetContentScroll();
      }
      requestRebuild();
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

    bool isMonitorWidgetListPath(const std::vector<std::string>& path) {
      return isBarWidgetListPath(path) && path.size() >= 5 && path[2] == "monitor";
    }

    bool monitorWidgetListHasExplicitValue(const Config& cfg, const std::vector<std::string>& path) {
      if (!isMonitorWidgetListPath(path)) {
        return true;
      }

      const auto* bar = findBar(cfg, path[1]);
      if (bar == nullptr) {
        return true;
      }
      const auto* ovr = findMonitorOverride(*bar, path[3]);
      if (ovr == nullptr) {
        return false;
      }

      const auto& lane = path.back();
      if (lane == "start") {
        return ovr->startWidgets.has_value();
      }
      if (lane == "center") {
        return ovr->centerWidgets.has_value();
      }
      if (lane == "end") {
        return ovr->endWidgets.has_value();
      }
      return true;
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

    std::vector<std::string> reorderedItems(std::vector<std::string> items, std::size_t fromIndex,
                                            std::size_t toIndex) {
      if (fromIndex >= items.size() || toIndex >= items.size() || fromIndex == toIndex) {
        return items;
      }
      auto item = std::move(items[fromIndex]);
      items.erase(items.begin() + static_cast<std::ptrdiff_t>(fromIndex));
      items.insert(items.begin() + static_cast<std::ptrdiff_t>(toIndex), std::move(item));
      return items;
    }

    std::optional<std::size_t> dragTargetIndex(float delta, float rowStep, std::size_t fromIndex, std::size_t itemCount,
                                               float scale) {
      if (itemCount < 2 || std::abs(delta) < kDragStartThresholdPx * scale) {
        return std::nullopt;
      }
      const auto offset = static_cast<int>(std::lround(delta / std::max(1.0f, rowStep)));
      if (offset == 0) {
        return std::nullopt;
      }

      const auto from = static_cast<int>(fromIndex);
      const auto maxIndex = static_cast<int>(itemCount - 1);
      const auto target = static_cast<std::size_t>(std::clamp(from + offset, 0, maxIndex));
      if (target == fromIndex) {
        return std::nullopt;
      }
      return target;
    }

    void updateDropIndicator(Box& indicator, const Flex& lane, const std::vector<Flex*>& itemNodes,
                             std::size_t fromIndex, std::size_t targetIndex, float scale) {
      if (targetIndex >= itemNodes.size() || fromIndex >= itemNodes.size()) {
        indicator.setVisible(false);
        return;
      }

      const auto* target = itemNodes[targetIndex];
      if (target == nullptr) {
        indicator.setVisible(false);
        return;
      }

      const float x = Style::spaceSm * scale;
      const float width = std::max(1.0f, lane.width() - Style::spaceSm * scale * 2.0f);
      const float gapHalf = Style::spaceXs * scale * 0.5f;
      const float y = targetIndex > fromIndex ? target->y() + target->height() + gapHalf : target->y() - gapHalf;

      indicator.setPosition(x, y);
      indicator.setFrameSize(width, std::max(2.0f, 3.0f * scale));
      indicator.setVisible(true);
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

    std::string settingValueAsDisplayString(const WidgetSettingValue& value) {
      return std::visit(
          [](const auto& concrete) -> std::string {
            using T = std::decay_t<decltype(concrete)>;
            if constexpr (std::is_same_v<T, bool>) {
              return concrete ? "true" : "false";
            } else if constexpr (std::is_same_v<T, std::int64_t>) {
              return std::to_string(concrete);
            } else if constexpr (std::is_same_v<T, double>) {
              return std::format("{}", concrete);
            } else if constexpr (std::is_same_v<T, std::string>) {
              return "\"" + concrete + "\"";
            } else if constexpr (std::is_same_v<T, std::vector<std::string>>) {
              std::string out = "[";
              for (std::size_t i = 0; i < concrete.size(); ++i) {
                if (i > 0) {
                  out += ", ";
                }
                out += "\"" + concrete[i] + "\"";
              }
              out += "]";
              return out;
            }
          },
          value);
    }

    void addRawWidgetSettings(Flex& panel, std::string_view widgetName, const std::vector<WidgetSettingSpec>& specs,
                              std::size_t& visibleSpecs, const BarWidgetEditorContext& ctx) {
      if (!ctx.showAdvanced) {
        return;
      }

      const auto widgetIt = ctx.config.widgets.find(std::string(widgetName));
      if (widgetIt == ctx.config.widgets.end()) {
        return;
      }

      std::unordered_set<std::string> knownKeys;
      knownKeys.reserve(specs.size());
      for (const auto& spec : specs) {
        knownKeys.insert(spec.key);
      }

      std::vector<std::string> rawKeys;
      for (const auto& [key, value] : widgetIt->second.settings) {
        if (knownKeys.contains(key)) {
          continue;
        }
        const auto path = widgetSettingPath(std::string(widgetName), key);
        const bool overridden = ctx.configService != nullptr && ctx.configService->hasOverride(path);
        if (ctx.showOverriddenOnly && !overridden) {
          continue;
        }
        rawKeys.push_back(key);
      }

      if (rawKeys.empty()) {
        return;
      }
      std::sort(rawKeys.begin(), rawKeys.end());

      auto header = std::make_unique<Flex>();
      header->setDirection(FlexDirection::Vertical);
      header->setAlign(FlexAlign::Stretch);
      header->setGap(1.0f * ctx.scale);
      header->setPadding(Style::spaceXs * ctx.scale, 0.0f);
      header->addChild(makeLabel(i18n::tr("settings.widget-raw-settings"), Style::fontSizeCaption * ctx.scale,
                                 roleColor(ColorRole::OnSurface), true));
      header->addChild(makeLabel(i18n::tr("settings.widget-raw-settings-desc"), Style::fontSizeCaption * ctx.scale,
                                 roleColor(ColorRole::OnSurfaceVariant), false));
      panel.addChild(std::move(header));

      for (const auto& key : rawKeys) {
        const auto valueIt = widgetIt->second.settings.find(key);
        if (valueIt == widgetIt->second.settings.end()) {
          continue;
        }
        const auto path = widgetSettingPath(std::string(widgetName), key);
        const std::string deleteKey = pathKey(path);
        const bool overridden = ctx.configService != nullptr && ctx.configService->hasOverride(path);
        const bool pendingDelete = ctx.pendingDeleteWidgetSettingPath == deleteKey;

        auto row = std::make_unique<Flex>();
        row->setDirection(FlexDirection::Horizontal);
        row->setAlign(FlexAlign::Center);
        row->setGap(Style::spaceSm * ctx.scale);
        row->setPadding(Style::spaceXs * ctx.scale, 0.0f);
        row->setMinHeight(Style::controlHeightSm * ctx.scale);

        row->addChild(makeLabel(key, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurface), true));

        auto spacer = std::make_unique<Flex>();
        spacer->setFlexGrow(1.0f);
        row->addChild(std::move(spacer));

        row->addChild(makeLabel(settingValueAsDisplayString(valueIt->second), Style::fontSizeCaption * ctx.scale,
                                roleColor(ColorRole::OnSurfaceVariant), false));

        if (overridden) {
          auto deleteBtn = std::make_unique<Button>();
          deleteBtn->setGlyph("trash");
          deleteBtn->setVariant(pendingDelete ? ButtonVariant::Default : ButtonVariant::Ghost);
          if (pendingDelete) {
            deleteBtn->setText(i18n::tr("settings.delete-widget-raw-setting"));
            deleteBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          }
          deleteBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          deleteBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          deleteBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          deleteBtn->setPadding(Style::spaceXs * ctx.scale);
          deleteBtn->setRadius(Style::radiusSm * ctx.scale);
          deleteBtn->setOnClick([&pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath, deleteKey, path,
                                 clearOverride = ctx.clearOverride, requestRebuild = ctx.requestRebuild]() {
            if (pendingDeleteWidgetSettingPath != deleteKey) {
              pendingDeleteWidgetSettingPath = deleteKey;
              requestRebuild();
              return;
            }

            pendingDeleteWidgetSettingPath.clear();
            clearOverride(path);
          });
          row->addChild(std::move(deleteBtn));
        }

        panel.addChild(std::move(row));
        ++visibleSpecs;
      }
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
      panel->setFill(roleColor(ColorRole::SurfaceVariant, 0.55f));
      panel->setBorder(roleColor(ColorRole::Outline, 0.22f), Style::borderWidth);

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

      addRawWidgetSettings(*panel, widgetName, specs, visibleSpecs, ctx);

      if (visibleSpecs == 0) {
        panel->addChild(makeLabel(i18n::tr("settings.widget-settings-empty"), Style::fontSizeCaption * ctx.scale,
                                  roleColor(ColorRole::OnSurfaceVariant), false));
      }

      item.addChild(std::move(panel));
    }

    void addInspectorPane(Flex& block, const SettingEntry& entry, const BarWidgetEditorContext& ctx) {
      static constexpr std::string_view kLaneKeys[] = {"start", "center", "end"};

      const bool hasEdit = !ctx.editingWidgetName.empty();

      auto inspector = std::make_unique<Flex>();
      inspector->setDirection(FlexDirection::Vertical);
      inspector->setAlign(FlexAlign::Stretch);
      inspector->setGap(Style::spaceSm * ctx.scale);
      inspector->setPadding(Style::spaceMd * ctx.scale);
      inspector->setRadius(Style::radiusMd * ctx.scale);
      inspector->setFill(roleColor(ColorRole::Surface, 0.85f));
      inspector->setBorder(roleColor(ColorRole::Outline, 0.35f), Style::borderWidth);

      if (hasEdit) {
        const std::string widgetName = ctx.editingWidgetName;
        const auto info = widgetReferenceInfo(ctx.config, widgetName);
        const bool guiManaged = isGuiManagedNamedWidgetInstance(ctx, widgetName);

        std::string currentLaneKey;
        std::vector<std::string> currentLanePath;
        std::vector<std::string> currentLaneItems;
        bool currentLaneInherited = false;
        for (const auto laneKey : kLaneKeys) {
          auto p = pathWithLastSegment(entry.path, std::string(laneKey));
          auto items = barWidgetItemsForPath(ctx.config, p);
          if (std::find(items.begin(), items.end(), widgetName) != items.end()) {
            currentLaneKey = std::string(laneKey);
            currentLanePath = std::move(p);
            currentLaneItems = std::move(items);
            currentLaneInherited = isMonitorWidgetListPath(currentLanePath) &&
                                   !monitorWidgetListHasExplicitValue(ctx.config, currentLanePath);
            break;
          }
        }

        auto headerRow = std::make_unique<Flex>();
        headerRow->setDirection(FlexDirection::Horizontal);
        headerRow->setAlign(FlexAlign::Center);
        headerRow->setGap(Style::spaceSm * ctx.scale);
        headerRow->addChild(makeLabel(i18n::tr("settings.inspector-edit-title"), Style::fontSizeCaption * ctx.scale,
                                      roleColor(ColorRole::OnSurfaceVariant), true));
        headerRow->addChild(
            makeLabel(info.title, Style::fontSizeBody * ctx.scale, roleColor(ColorRole::OnSurface), true));

        auto kindBadge = std::make_unique<Flex>();
        kindBadge->setAlign(FlexAlign::Center);
        kindBadge->setPadding(1.0f * ctx.scale, Style::spaceXs * ctx.scale);
        kindBadge->setRadius(Style::radiusSm * ctx.scale);
        kindBadge->setFill(widgetBadgeColor(info.kind));
        kindBadge->addChild(
            makeLabel(info.badge, Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurface), true));
        headerRow->addChild(std::move(kindBadge));

        auto headerSpacer = std::make_unique<Flex>();
        headerSpacer->setFlexGrow(1.0f);
        headerRow->addChild(std::move(headerSpacer));

        auto closeBtn = std::make_unique<Button>();
        closeBtn->setGlyph("close");
        closeBtn->setVariant(ButtonVariant::Ghost);
        closeBtn->setGlyphSize(Style::fontSizeBody * ctx.scale);
        closeBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
        closeBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
        closeBtn->setPadding(Style::spaceXs * ctx.scale);
        closeBtn->setRadius(Style::radiusSm * ctx.scale);
        closeBtn->setOnClick([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                              &editingWidgetName = ctx.editingWidgetName, &renamingWidgetName = ctx.renamingWidgetName,
                              &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
                              &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
                              &creatingWidgetType = ctx.creatingWidgetType, resetContentScroll = ctx.resetContentScroll,
                              requestRebuild = ctx.requestRebuild]() {
          closeInspector(openWidgetPickerPath, editingWidgetName, renamingWidgetName, pendingDeleteWidgetName,
                         pendingDeleteWidgetSettingPath, creatingWidgetType, resetContentScroll, requestRebuild);
        });
        headerRow->addChild(std::move(closeBtn));
        inspector->addChild(std::move(headerRow));

        addWidgetSettingsPanel(*inspector, widgetName, ctx);

        const bool pendingDelete = guiManaged && ctx.pendingDeleteWidgetName == widgetName;
        const bool renaming = guiManaged && ctx.renamingWidgetName == widgetName;

        if (renaming) {
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
                           config = ctx.config, renameWidgetInstance = ctx.renameWidgetInstance, widgetName,
                           inputPtr](std::string newName) mutable {
            if (!canRenameWidgetInstance(config, widgetName, newName)) {
              inputPtr->setInvalid(true);
              return;
            }
            inputPtr->setInvalid(false);
            auto referenceRenames = widgetReferenceRenameOverrides(config, widgetName, newName);
            renamingWidgetName.clear();
            if (editingWidgetName == widgetName) {
              editingWidgetName = newName;
            }
            renameWidgetInstance(widgetName, std::move(newName), std::move(referenceRenames));
          };

          input->setOnChange([inputPtr](const std::string& /*text*/) { inputPtr->setInvalid(false); });
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
          cancelBtn->setText(i18n::tr("common.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&renamingWidgetName = ctx.renamingWidgetName, requestRebuild = ctx.requestRebuild]() {
            renamingWidgetName.clear();
            requestRebuild();
          });

          renameRow->addChild(std::move(input));
          renameRow->addChild(std::move(saveBtn));
          renameRow->addChild(std::move(cancelBtn));
          inspector->addChild(std::move(renameRow));
        }

        if (pendingDelete) {
          auto confirmPanel = std::make_unique<Flex>();
          confirmPanel->setDirection(FlexDirection::Vertical);
          confirmPanel->setAlign(FlexAlign::Stretch);
          confirmPanel->setGap(Style::spaceXs * ctx.scale);
          confirmPanel->setPadding(Style::spaceSm * ctx.scale);
          confirmPanel->setRadius(Style::radiusSm * ctx.scale);
          confirmPanel->setFill(roleColor(ColorRole::Error, 0.10f));
          confirmPanel->setBorder(roleColor(ColorRole::Error, 0.35f), Style::borderWidth);

          confirmPanel->addChild(makeLabel(i18n::tr("settings.delete-widget-confirm-title", "name", widgetName),
                                           Style::fontSizeBody * ctx.scale, roleColor(ColorRole::Error), true));
          confirmPanel->addChild(makeLabel(i18n::tr("settings.delete-widget-confirm-desc"),
                                           Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant),
                                           false));

          auto confirmRow = std::make_unique<Flex>();
          confirmRow->setDirection(FlexDirection::Horizontal);
          confirmRow->setAlign(FlexAlign::Center);
          confirmRow->setGap(Style::spaceSm * ctx.scale);

          auto confirmSpacer = std::make_unique<Flex>();
          confirmSpacer->setFlexGrow(1.0f);
          confirmRow->addChild(std::move(confirmSpacer));

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setText(i18n::tr("common.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick(
              [&pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, requestRebuild = ctx.requestRebuild]() {
                pendingDeleteWidgetName.clear();
                requestRebuild();
              });
          confirmRow->addChild(std::move(cancelBtn));

          auto confirmBtn = std::make_unique<Button>();
          confirmBtn->setText(i18n::tr("settings.delete-widget-instance"));
          confirmBtn->setGlyph("trash");
          confirmBtn->setVariant(ButtonVariant::Destructive);
          confirmBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          confirmBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          confirmBtn->setRadius(Style::radiusSm * ctx.scale);
          confirmBtn->setOnClick([&editingWidgetName = ctx.editingWidgetName,
                                  &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, config = ctx.config,
                                  widgetName, clearOverride = ctx.clearOverride, setOverrides = ctx.setOverrides]() {
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
          confirmRow->addChild(std::move(confirmBtn));

          confirmPanel->addChild(std::move(confirmRow));
          inspector->addChild(std::move(confirmPanel));
        } else if (!currentLaneInherited && !currentLaneKey.empty()) {
          auto actionRow = std::make_unique<Flex>();
          actionRow->setDirection(FlexDirection::Horizontal);
          actionRow->setAlign(FlexAlign::Center);
          actionRow->setGap(Style::spaceXs * ctx.scale);

          for (const auto targetLane : kLaneKeys) {
            if (targetLane == currentLaneKey) {
              continue;
            }
            auto moveBtn = std::make_unique<Button>();
            moveBtn->setText(i18n::tr("settings.move-to-lane", "lane", laneLabel(targetLane)));
            moveBtn->setVariant(ButtonVariant::Ghost);
            moveBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            moveBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            moveBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            moveBtn->setRadius(Style::radiusSm * ctx.scale);
            auto sourceItems = currentLaneItems;
            auto sourcePath = currentLanePath;
            auto targetPath = pathWithLastSegment(entry.path, std::string(targetLane));
            auto targetItems = barWidgetItemsForPath(ctx.config, targetPath);
            moveBtn->setOnClick([setOverrides = ctx.setOverrides, sourceItems, sourcePath, targetItems, targetPath,
                                 widgetName]() mutable {
              auto it = std::find(sourceItems.begin(), sourceItems.end(), widgetName);
              if (it == sourceItems.end()) {
                return;
              }
              sourceItems.erase(it);
              targetItems.push_back(widgetName);
              setOverrides({{sourcePath, sourceItems}, {targetPath, targetItems}});
            });
            actionRow->addChild(std::move(moveBtn));
          }

          auto actionSpacer = std::make_unique<Flex>();
          actionSpacer->setFlexGrow(1.0f);
          actionRow->addChild(std::move(actionSpacer));

          if (guiManaged && !renaming) {
            auto renameBtn = std::make_unique<Button>();
            renameBtn->setText(i18n::tr("settings.rename-widget-instance"));
            renameBtn->setVariant(ButtonVariant::Ghost);
            renameBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            renameBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            renameBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            renameBtn->setRadius(Style::radiusSm * ctx.scale);
            renameBtn->setOnClick(
                [&renamingWidgetName = ctx.renamingWidgetName, widgetName, requestRebuild = ctx.requestRebuild]() {
                  renamingWidgetName = widgetName;
                  requestRebuild();
                });
            actionRow->addChild(std::move(renameBtn));
          }

          if (guiManaged) {
            auto deleteBtn = std::make_unique<Button>();
            deleteBtn->setGlyph("trash");
            deleteBtn->setText(i18n::tr("settings.delete-widget-instance"));
            deleteBtn->setVariant(ButtonVariant::Ghost);
            deleteBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            deleteBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
            deleteBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            deleteBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            deleteBtn->setRadius(Style::radiusSm * ctx.scale);
            deleteBtn->setOnClick([&pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
                                   &renamingWidgetName = ctx.renamingWidgetName, widgetName,
                                   requestRebuild = ctx.requestRebuild]() {
              pendingDeleteWidgetName = widgetName;
              renamingWidgetName.clear();
              requestRebuild();
            });
            actionRow->addChild(std::move(deleteBtn));
          }

          if (actionRow->children().empty()) {
            // nothing to add — leave inspector without action row
          } else {
            inspector->addChild(std::move(actionRow));
          }
        }
      } else {
        std::string targetLaneKey;
        std::vector<std::string> targetLanePath;
        std::vector<std::string> targetLaneItems;
        for (const auto laneKey : kLaneKeys) {
          auto p = pathWithLastSegment(entry.path, std::string(laneKey));
          if (pathKey(p) == ctx.openWidgetPickerPath) {
            targetLaneKey = std::string(laneKey);
            targetLanePath = std::move(p);
            targetLaneItems = barWidgetItemsForPath(ctx.config, targetLanePath);
            break;
          }
        }
        if (targetLaneKey.empty()) {
          return;
        }

        auto headerRow = std::make_unique<Flex>();
        headerRow->setDirection(FlexDirection::Horizontal);
        headerRow->setAlign(FlexAlign::Center);
        headerRow->setGap(Style::spaceSm * ctx.scale);
        headerRow->addChild(makeLabel(i18n::tr("settings.inspector-add-title", "lane", laneLabel(targetLaneKey)),
                                      Style::fontSizeBody * ctx.scale, roleColor(ColorRole::OnSurface), true));

        auto headerSpacer = std::make_unique<Flex>();
        headerSpacer->setFlexGrow(1.0f);
        headerRow->addChild(std::move(headerSpacer));

        auto closeBtn = std::make_unique<Button>();
        closeBtn->setGlyph("close");
        closeBtn->setVariant(ButtonVariant::Ghost);
        closeBtn->setGlyphSize(Style::fontSizeBody * ctx.scale);
        closeBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
        closeBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
        closeBtn->setPadding(Style::spaceXs * ctx.scale);
        closeBtn->setRadius(Style::radiusSm * ctx.scale);
        closeBtn->setOnClick([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                              &editingWidgetName = ctx.editingWidgetName, &renamingWidgetName = ctx.renamingWidgetName,
                              &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
                              &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
                              &creatingWidgetType = ctx.creatingWidgetType, resetContentScroll = ctx.resetContentScroll,
                              requestRebuild = ctx.requestRebuild]() {
          closeInspector(openWidgetPickerPath, editingWidgetName, renamingWidgetName, pendingDeleteWidgetName,
                         pendingDeleteWidgetSettingPath, creatingWidgetType, resetContentScroll, requestRebuild);
        });
        headerRow->addChild(std::move(closeBtn));
        inspector->addChild(std::move(headerRow));

        if (!ctx.creatingWidgetType.empty()) {
          const std::string widgetType = ctx.creatingWidgetType;
          inspector->addChild(makeLabel(i18n::tr("settings.create-widget-instance-title", "type", widgetType),
                                        Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant),
                                        false));

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

          auto items = targetLaneItems;
          auto path = targetLanePath;
          auto doCreate = [&openWidgetPickerPath = ctx.openWidgetPickerPath, &editingWidgetName = ctx.editingWidgetName,
                           &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
                           &creatingWidgetType = ctx.creatingWidgetType, config = ctx.config,
                           setOverrides = ctx.setOverrides, items, path, widgetType,
                           inputPtr](std::string instanceId) mutable {
            if (!canCreateWidgetInstance(config, instanceId)) {
              inputPtr->setInvalid(true);
              return;
            }
            inputPtr->setInvalid(false);
            items.push_back(instanceId);
            openWidgetPickerPath.clear();
            pendingDeleteWidgetSettingPath.clear();
            creatingWidgetType.clear();
            editingWidgetName = instanceId;
            setOverrides({{{"widget", instanceId, "type"}, widgetType}, {path, items}});
          };

          input->setOnChange([inputPtr](const std::string& /*text*/) { inputPtr->setInvalid(false); });
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
          cancelBtn->setText(i18n::tr("common.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&creatingWidgetType = ctx.creatingWidgetType, requestRebuild = ctx.requestRebuild]() {
            creatingWidgetType.clear();
            requestRebuild();
          });

          createRow->addChild(std::move(input));
          createRow->addChild(std::move(createBtn));
          createRow->addChild(std::move(cancelBtn));
          inspector->addChild(std::move(createRow));
        } else {
          auto picker = std::make_unique<SearchPicker>();
          picker->setPlaceholder(i18n::tr("settings.widget-picker-placeholder"));
          picker->setEmptyText(i18n::tr("settings.widget-picker-empty"));
          picker->setOptions(widgetPickerOptions(ctx.config));
          picker->setSize(420.0f * ctx.scale, 280.0f * ctx.scale);
          auto items = targetLaneItems;
          auto path = targetLanePath;
          picker->setOnActivated(
              [&openWidgetPickerPath = ctx.openWidgetPickerPath, &editingWidgetName = ctx.editingWidgetName,
               &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, &creatingWidgetType = ctx.creatingWidgetType,
               &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath, setOverride = ctx.setOverride,
               requestRebuild = ctx.requestRebuild, items, path](const SearchPickerOption& option) mutable {
                if (option.value.empty()) {
                  return;
                }
                pendingDeleteWidgetName.clear();
                pendingDeleteWidgetSettingPath.clear();
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
              });
          picker->setOnCancel([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                               &creatingWidgetType = ctx.creatingWidgetType,
                               &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
                               requestRebuild = ctx.requestRebuild]() {
            openWidgetPickerPath.clear();
            creatingWidgetType.clear();
            pendingDeleteWidgetSettingPath.clear();
            requestRebuild();
          });
          inspector->addChild(std::move(picker));
        }
      }

      block.addChild(std::move(inspector));
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

    const bool inspectorActive = !ctx.editingWidgetName.empty() || !ctx.openWidgetPickerPath.empty();
    if (inspectorActive) {
      addInspectorPane(*block, entry, ctx);
      section.addChild(std::move(block));
      return;
    }

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
      const bool inherited =
          isMonitorWidgetListPath(lanePath) && !monitorWidgetListHasExplicitValue(ctx.config, lanePath);

      auto lane = std::make_unique<Flex>();
      lane->setDirection(FlexDirection::Vertical);
      lane->setAlign(FlexAlign::Stretch);
      lane->setGap(Style::spaceXs * ctx.scale);
      lane->setPadding(Style::spaceSm * ctx.scale);
      lane->setRadius(Style::radiusMd * ctx.scale);
      lane->setFill(roleColor(ColorRole::SurfaceVariant, 0.45f));
      lane->setBorder(roleColor(ColorRole::Outline, 0.35f), Style::borderWidth);
      lane->setFlexGrow(1.0f);
      lane->setMinWidth(160.0f * ctx.scale);
      auto* lanePtr = lane.get();

      auto dropIndicator = std::make_unique<Box>();
      dropIndicator->setFill(roleColor(ColorRole::Primary));
      dropIndicator->setRadius(std::max(1.0f, 1.5f * ctx.scale));
      dropIndicator->setVisible(false);
      dropIndicator->setParticipatesInLayout(false);
      dropIndicator->setZIndex(10);
      auto* dropIndicatorPtr = dropIndicator.get();
      lane->addChild(std::move(dropIndicator));

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
        badge->setFill(roleColor(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * ctx.scale,
                                  roleColor(ColorRole::Primary), true));
        laneHeader->addChild(std::move(badge));
      }
      if (inherited) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * ctx.scale, Style::spaceXs * ctx.scale);
        badge->setRadius(Style::radiusSm * ctx.scale);
        badge->setFill(roleColor(ColorRole::OnSurfaceVariant, 0.14f));
        badge->addChild(makeLabel(i18n::tr("settings.badge-base-bar"), Style::fontSizeCaption * ctx.scale,
                                  roleColor(ColorRole::OnSurfaceVariant), true));
        laneHeader->addChild(std::move(badge));
      }
      auto laneSpacer = std::make_unique<Flex>();
      laneSpacer->setFlexGrow(1.0f);
      laneHeader->addChild(std::move(laneSpacer));
      if (inherited) {
        auto customizeBtn = std::make_unique<Button>();
        customizeBtn->setText(i18n::tr("settings.customize-lane"));
        customizeBtn->setVariant(ButtonVariant::Ghost);
        customizeBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
        customizeBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
        customizeBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
        customizeBtn->setRadius(Style::radiusSm * ctx.scale);
        auto items = laneItems;
        auto path = lanePath;
        customizeBtn->setOnClick([setOverride = ctx.setOverride, items, path]() { setOverride(path, items); });
        laneHeader->addChild(std::move(customizeBtn));
      }
      if (overridden) {
        laneHeader->addChild(ctx.makeResetButton(lanePath));
      }
      lane->addChild(std::move(laneHeader));

      auto itemNodes = std::make_shared<std::vector<Flex*>>();
      itemNodes->reserve(laneItems.size());
      for (std::size_t i = 0; i < laneItems.size(); ++i) {
        const auto info = widgetReferenceInfo(ctx.config, laneItems[i]);
        auto item = std::make_unique<Flex>();
        item->setDirection(FlexDirection::Vertical);
        item->setAlign(FlexAlign::Stretch);
        item->setGap(Style::spaceXs * ctx.scale);
        item->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
        item->setRadius(Style::radiusSm * ctx.scale);
        item->setFill(roleColor(ColorRole::Surface, 0.72f));
        item->setBorder(roleColor(ColorRole::Outline, 0.22f), Style::borderWidth);
        auto* itemPtr = item.get();
        itemNodes->push_back(itemPtr);

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
        kindBadge->setFill(widgetBadgeColor(info.kind));
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
        if (!inherited && laneItems.size() > 1) {
          auto dragBtn = std::make_unique<Button>();
          dragBtn->setGlyph("menu");
          dragBtn->setVariant(ButtonVariant::Ghost);
          dragBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          dragBtn->setMinWidth(Style::controlHeightSm * ctx.scale);
          dragBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          dragBtn->setPadding(Style::spaceXs * ctx.scale);
          dragBtn->setRadius(Style::radiusSm * ctx.scale);
          dragBtn->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE);

          auto dragState = std::make_shared<LaneWidgetDragState>();
          auto items = laneItems;
          auto path = lanePath;
          dragBtn->setOnPress([dragState, itemPtr, lanePtr, dropIndicatorPtr, itemNodes, setOverride = ctx.setOverride,
                               items, path, i,
                               scale = ctx.scale](float /*localX*/, float localY, bool pressed) mutable {
            if (pressed) {
              dragState->active = true;
              dragState->moved = false;
              dragState->startLocalY = localY;
              dragState->lastLocalY = localY;
              itemPtr->setOpacity(0.72f);
              dropIndicatorPtr->setVisible(false);
              return;
            }

            if (!dragState->active) {
              return;
            }
            dragState->active = false;
            itemPtr->setOpacity(1.0f);
            dropIndicatorPtr->setVisible(false);
            const float delta = dragState->lastLocalY - dragState->startLocalY;
            if (!dragState->moved || std::abs(delta) < kDragStartThresholdPx * scale || items.size() < 2) {
              return;
            }

            const float rowStep = std::clamp(itemPtr->height() + Style::spaceXs * scale, 44.0f * scale, 96.0f * scale);
            const auto toIndex = dragTargetIndex(delta, rowStep, i, items.size(), scale);
            if (!toIndex.has_value()) {
              return;
            }
            setOverride(path, reorderedItems(std::move(items), i, *toIndex));
          });
          dragBtn->setOnPointerMotion([dragState, itemPtr, lanePtr, dropIndicatorPtr, itemNodes, i,
                                       scale = ctx.scale](float /*localX*/, float localY) {
            if (!dragState->active) {
              return;
            }
            dragState->lastLocalY = localY;
            if (std::abs(dragState->lastLocalY - dragState->startLocalY) >= kDragStartThresholdPx * scale) {
              dragState->moved = true;
            }
            const float rowStep = std::clamp(itemPtr->height() + Style::spaceXs * scale, 44.0f * scale, 96.0f * scale);
            const auto target =
                dragTargetIndex(dragState->lastLocalY - dragState->startLocalY, rowStep, i, itemNodes->size(), scale);
            if (target.has_value()) {
              updateDropIndicator(*dropIndicatorPtr, *lanePtr, *itemNodes, i, *target, scale);
            } else {
              dropIndicatorPtr->setVisible(false);
            }
          });
          actions->addChild(std::move(dragBtn));
        }
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
               &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
               &creatingWidgetType = ctx.creatingWidgetType, resetContentScroll = ctx.resetContentScroll,
               requestRebuild = ctx.requestRebuild]() {
                editingWidgetName = editingWidgetName == widgetName ? std::string{} : widgetName;
                openWidgetPickerPath.clear();
                pendingDeleteWidgetName.clear();
                pendingDeleteWidgetSettingPath.clear();
                renamingWidgetName.clear();
                creatingWidgetType.clear();
                if (resetContentScroll) {
                  resetContentScroll();
                }
                requestRebuild();
              });
          actions->addChild(std::move(editBtn));
        }

        if (!inherited) {
          auto actionsSpacer = std::make_unique<Flex>();
          actionsSpacer->setFlexGrow(1.0f);
          actions->addChild(std::move(actionsSpacer));

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
        }

        item->addChild(std::move(actions));
        lane->addChild(std::move(item));
      }

      if (laneItems.empty() && !inherited) {
        auto emptyState = std::make_unique<Flex>();
        emptyState->setDirection(FlexDirection::Vertical);
        emptyState->setAlign(FlexAlign::Center);
        emptyState->setGap(2.0f * ctx.scale);
        emptyState->setPadding(Style::spaceMd * ctx.scale, Style::spaceSm * ctx.scale);
        emptyState->setRadius(Style::radiusSm * ctx.scale);
        emptyState->setFill(roleColor(ColorRole::SurfaceVariant, 0.25f));
        emptyState->setBorder(roleColor(ColorRole::Outline, 0.18f), Style::borderWidth);
        emptyState->addChild(makeLabel(i18n::tr("settings.lane-empty"), Style::fontSizeCaption * ctx.scale,
                                       roleColor(ColorRole::OnSurfaceVariant), true));
        emptyState->addChild(makeLabel(i18n::tr("settings.lane-empty-hint"), Style::fontSizeCaption * ctx.scale,
                                       roleColor(ColorRole::OnSurfaceVariant), false));
        lane->addChild(std::move(emptyState));
      }

      const std::string pickerKey = pathKey(lanePath);
      if (!inherited) {
        const bool pickerOpenForLane = ctx.openWidgetPickerPath == pickerKey;
        auto addBtn = std::make_unique<Button>();
        addBtn->setText(i18n::tr("settings.add-widget"));
        addBtn->setGlyph("add");
        addBtn->setVariant(pickerOpenForLane ? ButtonVariant::Default : ButtonVariant::Ghost);
        addBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
        addBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
        addBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
        addBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
        addBtn->setRadius(Style::radiusSm * ctx.scale);
        addBtn->setOnClick([&openWidgetPickerPath = ctx.openWidgetPickerPath,
                            &editingWidgetName = ctx.editingWidgetName, &renamingWidgetName = ctx.renamingWidgetName,
                            &pendingDeleteWidgetName = ctx.pendingDeleteWidgetName, pickerKey,
                            &pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
                            &creatingWidgetType = ctx.creatingWidgetType, resetContentScroll = ctx.resetContentScroll,
                            requestRebuild = ctx.requestRebuild]() {
          openWidgetPickerPath = openWidgetPickerPath == pickerKey ? std::string{} : pickerKey;
          editingWidgetName.clear();
          renamingWidgetName.clear();
          pendingDeleteWidgetName.clear();
          pendingDeleteWidgetSettingPath.clear();
          creatingWidgetType.clear();
          if (resetContentScroll) {
            resetContentScroll();
          }
          requestRebuild();
        });
        lane->addChild(std::move(addBtn));
      }

      lanes->addChild(std::move(lane));
    }

    block->addChild(std::move(lanes));
    section.addChild(std::move(block));
  }

} // namespace settings

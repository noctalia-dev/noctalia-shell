#include "shell/settings/settings_content.h"

#include "config/config_types.h"
#include "i18n/i18n.h"
#include "render/core/color.h"
#include "shell/settings/bar_widget_editor.h"
#include "shell/settings/color_spec_picker.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/checkbox.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/input.h"
#include "ui/controls/keybind_recorder.h"
#include "ui/controls/label.h"
#include "ui/controls/list_editor.h"
#include "ui/controls/segmented.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/slider.h"
#include "ui/controls/stepper.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/dialogs/glyph_picker_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <format>
#include <functional>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

namespace settings {
  namespace {

    std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ColorSpec& color, bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

    std::optional<std::size_t> optionIndex(const std::vector<SelectOption>& options, std::string_view value) {
      for (std::size_t i = 0; i < options.size(); ++i) {
        if (options[i].value == value) {
          return i;
        }
      }
      return std::nullopt;
    }

    std::string optionLabel(const std::vector<SelectOption>& options, std::string_view value) {
      for (const auto& opt : options) {
        if (opt.value == value) {
          return opt.label;
        }
      }
      return std::string(value);
    }

    std::vector<std::string> optionLabels(const std::vector<SelectOption>& options) {
      std::vector<std::string> labels;
      labels.reserve(options.size());
      for (const auto& opt : options) {
        labels.push_back(opt.label);
      }
      return labels;
    }

    std::vector<SelectOption> sessionActionVariantOptions() {
      std::vector<SelectOption> options;
      for (const auto& variant : kSessionActionButtonVariants) {
        options.push_back(SelectOption{std::string(variant.key), i18n::tr(variant.labelKey), {}});
      }
      return options;
    }

    const char* sessionActionDefaultGlyphName(std::string_view action) {
      if (action == "lock") {
        return "lock";
      }
      if (action == "logout") {
        return "logout";
      }
      if (action == "suspend") {
        return "suspend";
      }
      if (action == "reboot") {
        return "reboot";
      }
      if (action == "shutdown") {
        return "shutdown";
      }
      return "terminal";
    }

    bool isBlankInput(std::string_view text) { return StringUtils::trim(text).empty(); }

    std::string formatSliderValue(float value, bool integerValue) {
      if (integerValue) {
        return std::format("{}", static_cast<int>(std::lround(value)));
      }
      return StringUtils::formatFixedDotDecimal(value, 2);
    }

    template <typename T> std::optional<T> parseDotDecimalInput(std::string_view text) {
      return StringUtils::parseDotDecimal<T>(text);
    }

    std::optional<float> parseFloatInput(std::string_view text) {
      const auto parsed = parseDotDecimalInput<double>(text);
      if (!parsed.has_value()) {
        return std::nullopt;
      }
      return static_cast<float>(*parsed);
    }

    std::optional<double> parseDoubleInput(std::string_view text) { return parseDotDecimalInput<double>(text); }

    bool isMonitorOverrideSettingPath(const std::vector<std::string>& path) {
      return path.size() >= 5 && path[0] == "bar" && path[2] == "monitor";
    }

    bool isDockLauncherIconPath(const std::vector<std::string>& path) {
      return path.size() == 2 && path[0] == "dock" && path[1] == "launcher_icon";
    }

    bool monitorOverrideHasExplicitValue(const Config& cfg, const std::vector<std::string>& path) {
      if (!isMonitorOverrideSettingPath(path)) {
        return false;
      }

      const auto* bar = findBar(cfg, path[1]);
      if (bar == nullptr) {
        return false;
      }

      const auto* override = findMonitorOverride(*bar, path[3]);
      if (override == nullptr) {
        return false;
      }

      const std::string_view key = path.back();
      if (key == "enabled") {
        return override->enabled.has_value();
      }
      if (key == "auto_hide") {
        return override->autoHide.has_value();
      }
      if (key == "reserve_space") {
        return override->reserveSpace.has_value();
      }
      if (key == "thickness") {
        return override->thickness.has_value();
      }
      if (key == "scale") {
        return override->scale.has_value();
      }
      if (key == "margin_ends") {
        return override->marginEnds.has_value();
      }
      if (key == "margin_edge") {
        return override->marginEdge.has_value();
      }
      if (key == "padding") {
        return override->padding.has_value();
      }
      if (key == "radius") {
        return override->radius.has_value();
      }
      if (key == "radius_top_left") {
        return override->radiusTopLeft.has_value();
      }
      if (key == "radius_top_right") {
        return override->radiusTopRight.has_value();
      }
      if (key == "radius_bottom_left") {
        return override->radiusBottomLeft.has_value();
      }
      if (key == "radius_bottom_right") {
        return override->radiusBottomRight.has_value();
      }
      if (key == "background_opacity") {
        return override->backgroundOpacity.has_value();
      }
      if (key == "border") {
        return override->border.has_value();
      }
      if (key == "border_width") {
        return override->borderWidth.has_value();
      }
      if (key == "shadow") {
        return override->shadow.has_value();
      }
      if (key == "widget_spacing") {
        return override->widgetSpacing.has_value();
      }
      if (key == "capsule") {
        return override->widgetCapsuleDefault.has_value();
      }
      if (key == "capsule_fill") {
        return override->widgetCapsuleFill.has_value();
      }
      if (key == "capsule_border") {
        return override->widgetCapsuleBorderSpecified;
      }
      if (key == "capsule_foreground") {
        return override->widgetCapsuleForeground.has_value();
      }
      if (key == "color") {
        return override->widgetColor.has_value();
      }
      if (key == "capsule_groups") {
        return override->widgetCapsuleGroups.has_value();
      }
      if (key == "capsule_padding") {
        return override->widgetCapsulePadding.has_value();
      }
      if (key == "capsule_radius") {
        return override->widgetCapsuleRadius.has_value();
      }
      if (key == "capsule_opacity") {
        return override->widgetCapsuleOpacity.has_value();
      }
      if (key == "start") {
        return override->startWidgets.has_value();
      }
      if (key == "center") {
        return override->centerWidgets.has_value();
      }
      if (key == "end") {
        return override->endWidgets.has_value();
      }
      return false;
    }

    bool isBarCapsuleGroupsPath(const std::vector<std::string>& path) {
      return path.size() == 3 && path[0] == "bar" && path[2] == "capsule_groups";
    }

    bool isMonitorCapsuleGroupsPath(const std::vector<std::string>& path) {
      return path.size() == 5 && path[0] == "bar" && path[2] == "monitor" && path[4] == "capsule_groups";
    }

    bool isCapsuleGroupsPath(const std::vector<std::string>& path) {
      return isBarCapsuleGroupsPath(path) || isMonitorCapsuleGroupsPath(path);
    }

    void collectWidgetNames(std::unordered_set<std::string>& widgetNames, const std::vector<std::string>& widgets) {
      for (const auto& widget : widgets) {
        widgetNames.insert(widget);
      }
    }

    std::unordered_set<std::string> scopedBarWidgetNames(const Config& cfg, const std::vector<std::string>& path) {
      std::unordered_set<std::string> widgetNames;

      const auto* bar = path.size() >= 2 ? findBar(cfg, path[1]) : nullptr;
      if (bar == nullptr) {
        return widgetNames;
      }

      if (isBarCapsuleGroupsPath(path)) {
        collectWidgetNames(widgetNames, bar->startWidgets);
        collectWidgetNames(widgetNames, bar->centerWidgets);
        collectWidgetNames(widgetNames, bar->endWidgets);
        for (const auto& ovr : bar->monitorOverrides) {
          collectWidgetNames(widgetNames, ovr.startWidgets.value_or(bar->startWidgets));
          collectWidgetNames(widgetNames, ovr.centerWidgets.value_or(bar->centerWidgets));
          collectWidgetNames(widgetNames, ovr.endWidgets.value_or(bar->endWidgets));
        }
        return widgetNames;
      }

      const auto* ovr = path.size() >= 4 ? findMonitorOverride(*bar, path[3]) : nullptr;
      if (ovr == nullptr) {
        return widgetNames;
      }

      collectWidgetNames(widgetNames, ovr->startWidgets.value_or(bar->startWidgets));
      collectWidgetNames(widgetNames, ovr->centerWidgets.value_or(bar->centerWidgets));
      collectWidgetNames(widgetNames, ovr->endWidgets.value_or(bar->endWidgets));
      return widgetNames;
    }

    std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>
    capsuleGroupRemovalOverrides(const Config& cfg, const std::vector<std::string>& path, std::string_view removedGroup,
                                 std::vector<std::string> updatedGroups) {
      std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides;
      overrides.push_back({path, std::move(updatedGroups)});

      if (!isCapsuleGroupsPath(path)) {
        return overrides;
      }

      const std::string trimmedRemoved = StringUtils::trim(removedGroup);
      if (trimmedRemoved.empty()) {
        return overrides;
      }

      for (const auto& widgetName : scopedBarWidgetNames(cfg, path)) {
        const auto widgetIt = cfg.widgets.find(widgetName);
        if (widgetIt == cfg.widgets.end() || !widgetIt->second.hasSetting("capsule_group")) {
          continue;
        }
        if (StringUtils::trim(widgetIt->second.getString("capsule_group", "")) != trimmedRemoved) {
          continue;
        }
        overrides.push_back({{"widget", widgetName, "capsule_group"}, std::string()});
      }

      return overrides;
    }

    std::string sessionActionRowSummary(const std::vector<SelectOption>& kindOptions,
                                        const SessionPanelActionConfig& row) {
      if (row.label.has_value() && !row.label->empty()) {
        return *row.label;
      }
      return optionLabel(kindOptions, row.action);
    }

    std::string sanitizedIdleBehaviorName(std::string_view text) {
      std::string out = StringUtils::trim(text);
      for (char& ch : out) {
        if (ch == '.' || ch == '[' || ch == ']') {
          ch = '-';
        }
      }
      return out;
    }

    std::string uniqueIdleBehaviorName(std::string base, const std::vector<IdleBehaviorConfig>& rows,
                                       std::optional<std::size_t> ignoreIndex = std::nullopt) {
      base = sanitizedIdleBehaviorName(base);
      if (base.empty()) {
        base = "idle-behavior";
      }

      std::unordered_set<std::string> names;
      for (std::size_t i = 0; i < rows.size(); ++i) {
        if (ignoreIndex.has_value() && i == *ignoreIndex) {
          continue;
        }
        if (!rows[i].name.empty()) {
          names.insert(rows[i].name);
        }
      }

      if (!names.contains(base)) {
        return base;
      }
      for (int suffix = 2; suffix < 10000; ++suffix) {
        std::string candidate = std::format("{}-{}", base, suffix);
        if (!names.contains(candidate)) {
          return candidate;
        }
      }
      return base;
    }

    void normalizeIdleBehaviorNames(std::vector<IdleBehaviorConfig>& rows) {
      std::vector<IdleBehaviorConfig> normalized;
      normalized.reserve(rows.size());
      for (auto& row : rows) {
        row.name = uniqueIdleBehaviorName(row.name, normalized);
        normalized.push_back(row);
      }
      rows = std::move(normalized);
    }

    std::string idleBehaviorRowSummary(const IdleBehaviorConfig& row) {
      IdleBehaviorConfig norm = row;
      inferIdleBehaviorActionFromLegacyFields(norm);

      const auto displayName = [&]() -> std::string {
        if (norm.action == "lock") {
          return i18n::tr("settings.idle.behavior.presets.lock");
        }
        if (norm.action == "screen_off") {
          return i18n::tr("settings.idle.behavior.presets.monitor-off");
        }
        if (norm.action == "suspend") {
          return i18n::tr("settings.idle.behavior.presets.suspend");
        }
        if (row.name.empty()) {
          return i18n::tr("settings.idle.behavior.unnamed");
        }
        return row.name;
      };

      const std::string name = displayName();
      if (name.empty()) {
        return i18n::tr("settings.idle.behavior.unnamed");
      }
      if (row.timeoutSeconds <= 0) {
        return i18n::tr("settings.idle.behavior.summary-disabled-timeout", "name", name);
      }
      return i18n::tr("settings.idle.behavior.summary", "name", name, "seconds", std::to_string(row.timeoutSeconds));
    }

    void buildSessionActionEntryDetailContentImpl(Flex& section, SettingsContentContext& ctx,
                                                  SessionPanelActionConfig& row, const std::function<void()>& persist) {
      const float scale = ctx.scale;
      const std::vector<SelectOption> kindOptions = {
          {"lock", i18n::tr("settings.session-actions.kind.lock"), {}},
          {"logout", i18n::tr("settings.session-actions.kind.logout"), {}},
          {"suspend", i18n::tr("settings.session-actions.kind.suspend"), {}},
          {"reboot", i18n::tr("settings.session-actions.kind.reboot"), {}},
          {"shutdown", i18n::tr("settings.session-actions.kind.shutdown"), {}},
          {"command", i18n::tr("settings.session-actions.kind.command"), {}},
      };

      const float iconSq = Style::controlHeight * scale;
      const float iconGlyphSize = Style::fontSizeBody * scale;

      auto body = std::make_unique<Flex>();
      body->setDirection(FlexDirection::Horizontal);
      body->setAlign(FlexAlign::Start);
      body->setGap(Style::spaceMd * scale);
      body->setFillWidth(true);

      auto iconCol = std::make_unique<Flex>();
      iconCol->setDirection(FlexDirection::Vertical);
      iconCol->setAlign(FlexAlign::Stretch);
      iconCol->setGap(Style::spaceSm * scale);
      iconCol->addChild(makeLabel(i18n::tr("settings.session-actions.icon-label"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));

      auto glyphBtnRow = std::make_unique<Flex>();
      glyphBtnRow->setDirection(FlexDirection::Horizontal);
      glyphBtnRow->setAlign(FlexAlign::Center);
      glyphBtnRow->setGap(Style::spaceXs * scale);

      const std::string previewGlyph = [&] {
        if (row.glyph.has_value() && !row.glyph->empty()) {
          return *row.glyph;
        }
        return std::string(sessionActionDefaultGlyphName(row.action));
      }();

      auto glyphPickBtn = std::make_unique<Button>();
      glyphPickBtn->setVariant(ButtonVariant::Outline);
      glyphPickBtn->setText("");
      glyphPickBtn->setGlyph(previewGlyph);
      glyphPickBtn->setGlyphSize(iconGlyphSize);
      glyphPickBtn->setMinWidth(iconSq);
      glyphPickBtn->setMaxWidth(iconSq);
      glyphPickBtn->setMinHeight(iconSq);
      glyphPickBtn->setMaxHeight(iconSq);
      glyphPickBtn->setPadding(0.0f, 0.0f);
      glyphPickBtn->setRadius(Style::scaledRadiusMd(scale));
      glyphPickBtn->setOnClick([&row, persist]() {
        GlyphPickerDialogOptions options;
        options.title = i18n::tr("settings.session-actions.glyph-picker-title");
        if (row.glyph.has_value() && !row.glyph->empty()) {
          options.initialGlyph = *row.glyph;
        }
        (void)GlyphPickerDialog::open(std::move(options), [&row, persist](std::optional<GlyphPickerResult> result) {
          if (!result.has_value()) {
            return;
          }
          row.glyph = result->name;
          persist();
        });
      });
      glyphBtnRow->addChild(std::move(glyphPickBtn));

      if (row.glyph.has_value() && !row.glyph->empty()) {
        auto clearG = std::make_unique<Button>();
        clearG->setVariant(ButtonVariant::Ghost);
        clearG->setText(i18n::tr("settings.session-actions.clear-glyph"));
        clearG->setFontSize(Style::fontSizeCaption * scale);
        clearG->setMinHeight(iconSq);
        clearG->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
        clearG->setRadius(Style::scaledRadiusSm(scale));
        clearG->setOnClick([&row, persist]() {
          row.glyph = std::nullopt;
          persist();
        });
        glyphBtnRow->addChild(std::move(clearG));
      }

      iconCol->addChild(std::move(glyphBtnRow));
      body->addChild(std::move(iconCol));

      auto fields = std::make_unique<Flex>();
      fields->setDirection(FlexDirection::Vertical);
      fields->setAlign(FlexAlign::Stretch);
      fields->setGap(Style::spaceSm * scale);
      fields->setFlexGrow(1.0f);

      fields->addChild(makeLabel(i18n::tr("settings.session-actions.kind-section-label"),
                                 Style::fontSizeCaption * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant),
                                 false));
      auto kindSelect = std::make_unique<Select>();
      kindSelect->setOptions(optionLabels(kindOptions));
      if (const auto ki = optionIndex(kindOptions, row.action)) {
        kindSelect->setSelectedIndex(*ki);
      } else {
        kindSelect->clearSelection();
      }
      kindSelect->setFontSize(Style::fontSizeBody * scale);
      kindSelect->setControlHeight(Style::controlHeight * scale);
      kindSelect->setGlyphSize(Style::fontSizeBody * scale);
      kindSelect->setFillWidth(true);
      kindSelect->setOnSelectionChanged([&row, kindOptions, persist](std::size_t index, std::string_view /*label*/) {
        if (index < kindOptions.size()) {
          row.action = kindOptions[index].value;
          persist();
        }
      });
      fields->addChild(std::move(kindSelect));

      auto labelBlock = std::make_unique<Flex>();
      labelBlock->setDirection(FlexDirection::Vertical);
      labelBlock->setAlign(FlexAlign::Stretch);
      labelBlock->setGap(Style::spaceXs * scale);
      labelBlock->setFlexGrow(1.0f);
      labelBlock->addChild(makeLabel(i18n::tr("settings.session-actions.label-field"), Style::fontSizeCaption * scale,
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      auto labelIn = std::make_unique<Input>();
      labelIn->setValue(row.label.value_or(""));
      labelIn->setPlaceholder(i18n::tr("settings.session-actions.label-placeholder"));
      labelIn->setFontSize(Style::fontSizeBody * scale);
      labelIn->setControlHeight(Style::controlHeight * scale);
      labelIn->setHorizontalPadding(Style::spaceSm * scale);
      labelIn->setMinLayoutWidth(200.0f * scale);
      auto* labelPtr = labelIn.get();
      const auto commitLabel = [&row, persist, labelPtr]() {
        const std::string t = StringUtils::trim(labelPtr->value());
        if (t.empty()) {
          row.label = std::nullopt;
        } else {
          row.label = t;
        }
        labelPtr->setInvalid(false);
        persist();
      };
      labelIn->setOnChange([labelPtr](const std::string& /*t*/) { labelPtr->setInvalid(false); });
      labelIn->setOnSubmit([commitLabel](const std::string& /*text*/) { commitLabel(); });
      labelIn->setOnFocusLoss(commitLabel);
      labelBlock->addChild(std::move(labelIn));
      fields->addChild(std::move(labelBlock));

      auto cmdBlock = std::make_unique<Flex>();
      cmdBlock->setDirection(FlexDirection::Vertical);
      cmdBlock->setAlign(FlexAlign::Stretch);
      cmdBlock->setGap(Style::spaceXs * scale);
      cmdBlock->setFlexGrow(1.0f);
      cmdBlock->addChild(makeLabel(i18n::tr("settings.session-actions.command-label"), Style::fontSizeCaption * scale,
                                   colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      auto cmdIn = std::make_unique<Input>();
      cmdIn->setValue(row.command.value_or(""));
      cmdIn->setPlaceholder(i18n::tr("settings.session-actions.command-placeholder"));
      cmdIn->setFontSize(Style::fontSizeBody * scale);
      cmdIn->setControlHeight(Style::controlHeight * scale);
      cmdIn->setHorizontalPadding(Style::spaceSm * scale);
      cmdIn->setMinLayoutWidth(280.0f * scale);
      auto* cmdPtr = cmdIn.get();
      const auto commitCommand = [&row, persist, cmdPtr]() {
        const std::string t = StringUtils::trim(cmdPtr->value());
        if (t.empty()) {
          row.command = std::nullopt;
        } else {
          row.command = t;
        }
        cmdPtr->setInvalid(false);
        persist();
      };
      cmdIn->setOnChange([cmdPtr](const std::string& /*t*/) { cmdPtr->setInvalid(false); });
      cmdIn->setOnSubmit([commitCommand](const std::string& /*text*/) { commitCommand(); });
      cmdIn->setOnFocusLoss(commitCommand);
      cmdBlock->addChild(std::move(cmdIn));
      fields->addChild(std::move(cmdBlock));

      auto variantBlock = std::make_unique<Flex>();
      variantBlock->setDirection(FlexDirection::Vertical);
      variantBlock->setAlign(FlexAlign::Stretch);
      variantBlock->setGap(Style::spaceXs * scale);
      variantBlock->setFlexGrow(1.0f);
      variantBlock->addChild(makeLabel(i18n::tr("settings.session-actions.variant-label"),
                                       Style::fontSizeCaption * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant),
                                       false));
      auto variantSelect = std::make_unique<Select>();
      const std::vector<SelectOption> variantOptions = sessionActionVariantOptions();
      variantSelect->setOptions(optionLabels(variantOptions));
      const std::string selectedVariant(enumToKey(kSessionActionButtonVariants, row.variant));
      if (const auto vi = optionIndex(variantOptions, selectedVariant)) {
        variantSelect->setSelectedIndex(*vi);
      } else {
        variantSelect->clearSelection();
      }
      variantSelect->setFontSize(Style::fontSizeBody * scale);
      variantSelect->setControlHeight(Style::controlHeight * scale);
      variantSelect->setGlyphSize(Style::fontSizeBody * scale);
      variantSelect->setFillWidth(true);
      variantSelect->setOnSelectionChanged(
          [&row, variantOptions, persist](std::size_t index, std::string_view /*label*/) {
            if (index < variantOptions.size()) {
              if (auto parsed = enumFromKey(kSessionActionButtonVariants, variantOptions[index].value)) {
                row.variant = *parsed;
                persist();
              }
            }
          });
      variantBlock->addChild(std::move(variantSelect));
      fields->addChild(std::move(variantBlock));

      body->addChild(std::move(fields));
      section.addChild(std::move(body));
    }

    void buildIdleBehaviorEntryDetailContentImpl(Flex& section, SettingsContentContext& ctx, IdleBehaviorConfig& row,
                                                 const std::function<void()>& persist,
                                                 const std::function<void()>& closeHostedEditor) {
      const float scale = ctx.scale;

      const std::vector<SelectOption> idleActionOptions = {
          {"lock", i18n::tr("settings.idle.behavior.kind.lock"), {}},
          {"screen_off", i18n::tr("settings.idle.behavior.kind.screen-off"), {}},
          {"suspend", i18n::tr("settings.idle.behavior.kind.suspend"), {}},
          {"command", i18n::tr("settings.idle.behavior.kind.custom"), {}},
      };

      IdleBehaviorConfig norm = row;
      inferIdleBehaviorActionFromLegacyFields(norm);
      const bool showCustomCommands = (norm.action == "command");
      const bool showSuspendLock = (norm.action == "suspend");

      auto body = std::make_unique<Flex>();
      body->setDirection(FlexDirection::Vertical);
      body->setAlign(FlexAlign::Stretch);
      body->setGap(Style::spaceMd * scale);

      auto customCommandsGrp = std::make_unique<Flex>();
      customCommandsGrp->setDirection(FlexDirection::Vertical);
      customCommandsGrp->setAlign(FlexAlign::Stretch);
      customCommandsGrp->setGap(Style::spaceMd * scale);
      customCommandsGrp->setVisible(showCustomCommands);
      Flex* customCommandsRaw = customCommandsGrp.get();

      auto suspendLockGrp = std::make_unique<Flex>();
      suspendLockGrp->setDirection(FlexDirection::Horizontal);
      suspendLockGrp->setAlign(FlexAlign::Center);
      suspendLockGrp->setGap(Style::spaceSm * scale);
      suspendLockGrp->setFillWidth(true);
      suspendLockGrp->setVisible(showSuspendLock);
      auto suspendLockLabel = makeLabel(i18n::tr("settings.idle.behavior.lock-before-suspend-label"),
                                        Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), false);
      suspendLockLabel->setFlexGrow(1.0f);
      suspendLockGrp->addChild(std::move(suspendLockLabel));
      auto suspendLockToggle = std::make_unique<Toggle>();
      suspendLockToggle->setScale(scale);
      suspendLockToggle->setChecked(row.lockBeforeSuspend);
      suspendLockToggle->setOnChange([&row, persist](bool v) {
        row.lockBeforeSuspend = v;
        persist();
      });
      suspendLockGrp->addChild(std::move(suspendLockToggle));
      Flex* suspendLockRaw = suspendLockGrp.get();

      const auto addCommandInput = [&](Flex& parent, std::string label, std::string placeholder, std::string& target) {
        auto block = std::make_unique<Flex>();
        block->setDirection(FlexDirection::Vertical);
        block->setAlign(FlexAlign::Stretch);
        block->setGap(Style::spaceXs * scale);
        block->addChild(
            makeLabel(label, Style::fontSizeCaption * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
        auto input = std::make_unique<Input>();
        input->setValue(target);
        input->setPlaceholder(placeholder);
        input->setFontSize(Style::fontSizeBody * scale);
        input->setControlHeight(Style::controlHeight * scale);
        input->setHorizontalPadding(Style::spaceSm * scale);
        auto* inputPtr = input.get();
        auto* targetPtr = &target;
        const auto commit = [targetPtr, persist, inputPtr]() {
          *targetPtr = StringUtils::trim(inputPtr->value());
          inputPtr->setInvalid(false);
          inputPtr->setValue(*targetPtr);
          persist();
        };
        input->setOnChange([inputPtr](const std::string& /*t*/) { inputPtr->setInvalid(false); });
        input->setOnSubmit([commit](const std::string& /*text*/) { commit(); });
        input->setOnFocusLoss(commit);
        block->addChild(std::move(input));
        parent.addChild(std::move(block));
      };

      addCommandInput(*customCommandsGrp, i18n::tr("settings.idle.behavior.command-label"),
                      i18n::tr("settings.idle.behavior.command-placeholder"), row.command);

      auto resumeCommandGrp = std::make_unique<Flex>();
      resumeCommandGrp->setDirection(FlexDirection::Vertical);
      resumeCommandGrp->setAlign(FlexAlign::Stretch);
      resumeCommandGrp->setGap(Style::spaceMd * scale);
      addCommandInput(*resumeCommandGrp, i18n::tr("settings.idle.behavior.resume-command-label"),
                      i18n::tr("settings.idle.behavior.resume-command-placeholder"), row.resumeCommand);

      auto kindBlock = std::make_unique<Flex>();
      kindBlock->setDirection(FlexDirection::Vertical);
      kindBlock->setAlign(FlexAlign::Stretch);
      kindBlock->setGap(Style::spaceXs * scale);
      kindBlock->addChild(makeLabel(i18n::tr("settings.idle.behavior.kind-section-label"),
                                    Style::fontSizeCaption * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant),
                                    false));
      auto kindSelect = std::make_unique<Select>();
      kindSelect->setOptions(optionLabels(idleActionOptions));
      if (const auto ki = optionIndex(idleActionOptions, norm.action)) {
        kindSelect->setSelectedIndex(*ki);
      } else {
        kindSelect->clearSelection();
      }
      kindSelect->setFontSize(Style::fontSizeBody * scale);
      kindSelect->setControlHeight(Style::controlHeight * scale);
      kindSelect->setGlyphSize(Style::fontSizeBody * scale);
      kindSelect->setFillWidth(true);
      kindSelect->setOnSelectionChanged([&row, persist, idleActionOptions, customCommandsRaw,
                                         suspendLockRaw](std::size_t index, std::string_view /*label*/) {
        if (index < idleActionOptions.size()) {
          row.action = idleActionOptions[index].value;
          if (row.action != "command") {
            row.command.clear();
          }
        }
        IdleBehaviorConfig n = row;
        inferIdleBehaviorActionFromLegacyFields(n);
        customCommandsRaw->setVisible(n.action == "command");
        suspendLockRaw->setVisible(n.action == "suspend");
        persist();
      });
      kindBlock->addChild(std::move(kindSelect));
      body->addChild(std::move(kindBlock));
      body->addChild(std::move(suspendLockGrp));

      auto nameBlock = std::make_unique<Flex>();
      nameBlock->setDirection(FlexDirection::Vertical);
      nameBlock->setAlign(FlexAlign::Stretch);
      nameBlock->setGap(Style::spaceXs * scale);
      nameBlock->addChild(makeLabel(i18n::tr("settings.idle.behavior.name-label"), Style::fontSizeCaption * scale,
                                    colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      auto nameIn = std::make_unique<Input>();
      nameIn->setValue(row.name);
      nameIn->setPlaceholder(i18n::tr("settings.idle.behavior.name-placeholder"));
      nameIn->setFontSize(Style::fontSizeBody * scale);
      nameIn->setControlHeight(Style::controlHeight * scale);
      nameIn->setHorizontalPadding(Style::spaceSm * scale);
      auto* namePtr = nameIn.get();
      const auto commitName = [&row, persist, namePtr]() {
        const std::string name = sanitizedIdleBehaviorName(namePtr->value());
        if (name.empty()) {
          namePtr->setInvalid(true);
          return;
        }
        row.name = name;
        namePtr->setInvalid(false);
        namePtr->setValue(row.name);
        persist();
      };
      nameIn->setOnChange([namePtr](const std::string& /*t*/) { namePtr->setInvalid(false); });
      nameIn->setOnSubmit([commitName](const std::string& /*text*/) { commitName(); });
      nameIn->setOnFocusLoss(commitName);
      nameBlock->addChild(std::move(nameIn));
      body->addChild(std::move(nameBlock));

      auto timeoutBlock = std::make_unique<Flex>();
      timeoutBlock->setDirection(FlexDirection::Vertical);
      timeoutBlock->setAlign(FlexAlign::Stretch);
      timeoutBlock->setGap(Style::spaceXs * scale);
      timeoutBlock->addChild(makeLabel(i18n::tr("settings.idle.behavior.timeout-label"), Style::fontSizeCaption * scale,
                                       colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      auto timeoutIn = std::make_unique<Input>();
      timeoutIn->setValue(std::format("{}", row.timeoutSeconds));
      timeoutIn->setPlaceholder("660");
      timeoutIn->setFontSize(Style::fontSizeBody * scale);
      timeoutIn->setControlHeight(Style::controlHeight * scale);
      timeoutIn->setHorizontalPadding(Style::spaceSm * scale);
      auto* timeoutPtr = timeoutIn.get();
      const auto commitTimeout = [&row, persist, timeoutPtr]() {
        const auto parsed = parseDoubleInput(timeoutPtr->value());
        if (!parsed.has_value() || *parsed < 0.0 ||
            *parsed > static_cast<double>(std::numeric_limits<std::int32_t>::max())) {
          timeoutPtr->setInvalid(true);
          return;
        }
        row.timeoutSeconds = static_cast<std::int32_t>(std::lround(*parsed));
        timeoutPtr->setInvalid(false);
        timeoutPtr->setValue(std::format("{}", row.timeoutSeconds));
        persist();
      };
      timeoutIn->setOnChange([timeoutPtr](const std::string& /*t*/) { timeoutPtr->setInvalid(false); });
      timeoutIn->setOnSubmit([commitTimeout](const std::string& /*text*/) { commitTimeout(); });
      timeoutIn->setOnFocusLoss(commitTimeout);
      timeoutBlock->addChild(std::move(timeoutIn));
      body->addChild(std::move(timeoutBlock));

      body->addChild(std::move(customCommandsGrp));
      body->addChild(std::move(resumeCommandGrp));

      section.addChild(std::move(body));

      auto actions = std::make_unique<Flex>();
      actions->setDirection(FlexDirection::Horizontal);
      actions->setAlign(FlexAlign::Center);
      actions->setGap(Style::spaceSm * scale);
      actions->setFillWidth(true);

      auto applyBtn = std::make_unique<Button>();
      applyBtn->setGlyph("check");
      applyBtn->setText(i18n::tr("common.actions.apply"));
      applyBtn->setVariant(ButtonVariant::Default);
      applyBtn->setFontSize(Style::fontSizeBody * scale);
      applyBtn->setGlyphSize(Style::fontSizeBody * scale);
      applyBtn->setMinHeight(Style::controlHeight * scale);
      applyBtn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      applyBtn->setRadius(Style::scaledRadiusMd(scale));
      applyBtn->setFlexGrow(1.0f);
      applyBtn->setOnClick(
          [commitName, commitTimeout, applyHostedEditor = ctx.afterIdleBehaviorApply, closeHostedEditor]() {
            commitName();
            commitTimeout();
            if (applyHostedEditor) {
              applyHostedEditor();
            }
            if (closeHostedEditor) {
              closeHostedEditor();
            }
          });
      actions->addChild(std::move(applyBtn));
      section.addChild(std::move(actions));
    }

    void addIdleLiveStatusPanel(Flex& section, SettingsContentContext& ctx, float scale) {
      auto line = std::make_unique<Label>();
      line->setFontSize(Style::fontSizeBody * scale);
      line->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      line->setText("");
      if (ctx.registerIdleLiveStatusLabel) {
        ctx.registerIdleLiveStatusLabel(line.get());
      }
      section.addChild(std::move(line));
    }

  } // namespace

  std::size_t addSettingsContentSections(Flex& content, const std::vector<SettingEntry>& registry,
                                         SettingsContentContext ctx) {
    const Config& cfg = ctx.config;
    const float scale = ctx.scale;

    const auto sectionLabel = [](std::string_view section) {
      return i18n::tr("settings.navigation.sections." + std::string(section));
    };

    const auto groupLabel = [](std::string_view group) -> std::string {
      return i18n::tr("settings.navigation.groups." + std::string(group));
    };

    const auto makeSection = [&](std::string_view title, std::string_view sectionKey) -> Flex* {
      auto section = std::make_unique<Flex>();
      section->setDirection(FlexDirection::Vertical);
      section->setAlign(FlexAlign::Stretch);
      section->setGap(Style::spaceSm * scale);
      section->setPadding(Style::spaceLg * scale);
      section->setFill(clearColorSpec());

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);

      auto titleGlyph = std::make_unique<Glyph>();
      titleGlyph->setGlyph(sectionGlyph(sectionKey));
      titleGlyph->setGlyphSize(Style::fontSizeHeader * scale);
      titleGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
      titleRow->addChild(std::move(titleGlyph));

      titleRow->addChild(makeLabel(title, Style::fontSizeHeader * scale, colorSpecFromRole(ColorRole::Primary), true));

      section->addChild(std::move(titleRow));
      auto* raw = section.get();
      content.addChild(std::move(section));
      return raw;
    };

    const auto addGroupLabel = [&](Flex& section, std::string_view title, bool isFirst) {
      if (title.empty()) {
        return;
      }
      if (!isFirst) {
        auto groupHeader = std::make_unique<Flex>();
        groupHeader->setDirection(FlexDirection::Vertical);
        groupHeader->setAlign(FlexAlign::Stretch);
        groupHeader->setGap(Style::spaceSm * scale);
        groupHeader->setPadding(Style::spaceSm * scale, 0.0f, 0.0f, 0.0f);
        groupHeader->addChild(std::make_unique<Separator>());
        groupHeader->addChild(
            makeLabel(title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::Secondary), true));
        section.addChild(std::move(groupHeader));
      } else {
        section.addChild(makeLabel(title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::Secondary), true));
      }
    };

    const auto makeResetButton = [&](const std::vector<std::string>& path) {
      auto reset = std::make_unique<Button>();
      reset->setText(i18n::tr("settings.actions.reset"));
      reset->setVariant(ButtonVariant::Ghost);
      reset->setFontSize(Style::fontSizeCaption * scale);
      reset->setMinHeight(Style::controlHeightSm * scale);
      reset->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      reset->setRadius(Style::scaledRadiusMd(scale));
      reset->setOnClick([clearOverride = ctx.clearOverride, path]() { clearOverride(path); });
      return reset;
    };

    const auto makeRow = [&](Flex& section, const SettingEntry& entry, std::unique_ptr<Node> control) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));
      const bool redundantGuiOverride =
          ctx.configService != nullptr && ctx.configService->hasOverride(entry.path) && !overridden;
      const bool monitorSetting = isMonitorOverrideSettingPath(entry.path);
      const bool monitorExplicit = monitorOverrideHasExplicitValue(cfg, entry.path) && !redundantGuiOverride;
      const bool monitorInherited = monitorSetting && !monitorExplicit;

      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Center);
      row->setJustify(FlexJustify::SpaceBetween);
      row->setGap(Style::spaceXs * scale);
      row->setPadding(2.0f * scale, 0.0f);
      row->setMinHeight(Style::controlHeight * scale);

      auto copy = std::make_unique<Flex>();
      copy->setDirection(FlexDirection::Vertical);
      copy->setAlign(FlexAlign::Start);
      copy->setGap(Style::spaceXs * scale);
      copy->setFlexGrow(1.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }

      const auto makeBadge = [&](std::string_view label, const ColorSpec& fill, const ColorSpec& color) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(0, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(fill);
        badge->addChild(makeLabel(label, Style::fontSizeCaption * scale, color, true));
        return badge;
      };

      if (monitorExplicit) {
        titleRow->addChild(makeBadge(i18n::tr("settings.badges.monitor"),
                                     colorSpecFromRole(ColorRole::Secondary, 0.15f),
                                     colorSpecFromRole(ColorRole::Secondary)));
      } else if (monitorInherited) {
        titleRow->addChild(makeBadge(i18n::tr("settings.badges.inherited"),
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant, 0.12f),
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant)));
      }
      if (overridden) {
        titleRow->addChild(makeBadge(i18n::tr("settings.badges.override"), colorSpecFromRole(ColorRole::Primary, 0.15f),
                                     colorSpecFromRole(ColorRole::Primary)));
      }
      if (entry.advanced) {
        titleRow->addChild(makeBadge(i18n::tr("settings.badges.advanced"),
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant, 0.12f),
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant)));
      }
      copy->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        auto detail = makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                colorSpecFromRole(ColorRole::OnSurfaceVariant), false);
        copy->addChild(std::move(detail));
      }

      row->addChild(std::move(copy));

      auto actions = std::make_unique<Flex>();
      actions->setDirection(FlexDirection::Horizontal);
      actions->setAlign(FlexAlign::Center);
      actions->setGap(Style::spaceSm * scale);
      if (overridden) {
        actions->addChild(makeResetButton(entry.path));
      }
      actions->addChild(std::move(control));
      row->addChild(std::move(actions));

      section.addChild(std::move(row));
    };

    const auto makeToggle = [&](bool checked, bool enabled, std::vector<std::string> path,
                                std::optional<bool> clearWhenValue = std::nullopt) {
      auto toggle = std::make_unique<Toggle>();
      toggle->setScale(scale);
      toggle->setChecked(checked);
      toggle->setEnabled(enabled);
      if (enabled) {
        toggle->setOnChange([configService = ctx.configService, setOverride = ctx.setOverride,
                             clearOverride = ctx.clearOverride, path, clearWhenValue](bool value) {
          if (clearWhenValue.has_value() && value == *clearWhenValue && configService != nullptr &&
              configService->hasOverride(path)) {
            clearOverride(path);
            return;
          }
          setOverride(path, value);
        });
      }
      return toggle;
    };

    const auto makeSelect = [&](const SelectSetting& setting, std::vector<std::string> path) -> std::unique_ptr<Node> {
      if (setting.segmented) {
        auto segmented = std::make_unique<Segmented>();
        segmented->setScale(scale);
        for (const auto& opt : setting.options) {
          segmented->addOption(opt.label);
        }
        if (const auto index = optionIndex(setting.options, setting.selectedValue)) {
          segmented->setSelectedIndex(*index);
        }
        auto options = setting.options;
        segmented->setOnChange([setOverride = ctx.setOverride, path, options](std::size_t index) {
          if (index < options.size()) {
            setOverride(path, options[index].value);
          }
        });
        return segmented;
      }

      auto select = std::make_unique<Select>();
      select->setOptions(optionLabels(setting.options));
      if (const auto index = optionIndex(setting.options, setting.selectedValue)) {
        select->setSelectedIndex(*index);
      } else if (!setting.selectedValue.empty()) {
        select->clearSelection();
        select->setPlaceholder(i18n::tr("settings.controls.select.unknown-value", "value", setting.selectedValue));
      }
      select->setFontSize(Style::fontSizeBody * scale);
      select->setControlHeight(Style::controlHeight * scale);
      select->setGlyphSize(Style::fontSizeBody * scale);
      select->setSize(190.0f * scale, Style::controlHeight * scale);
      auto options = setting.options;
      const bool clearOnEmpty = setting.clearOnEmpty;
      select->setOnSelectionChanged([configService = ctx.configService, clearOverride = ctx.clearOverride,
                                     setOverride = ctx.setOverride, requestRebuild = ctx.requestRebuild, path, options,
                                     clearOnEmpty](std::size_t index, std::string_view /*label*/) {
        if (index < options.size()) {
          if (clearOnEmpty && options[index].value.empty()) {
            if (configService != nullptr && configService->hasOverride(path)) {
              clearOverride(path);
            } else {
              requestRebuild();
            }
            return;
          }
          setOverride(path, options[index].value);
        }
      });
      return select;
    };

    const auto makeSlider =
        [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
            bool integerValue = false,
            std::function<std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>(double)> linkedCommit =
                {}) {
          auto wrap = std::make_unique<Flex>();
          wrap->setDirection(FlexDirection::Horizontal);
          wrap->setAlign(FlexAlign::Center);
          wrap->setGap(Style::spaceSm * scale);

          auto valueInput = std::make_unique<Input>();
          valueInput->setValue(formatSliderValue(value, integerValue));
          valueInput->setFontSize(Style::fontSizeCaption * scale);
          valueInput->setControlHeight(Style::controlHeightSm * scale);
          valueInput->setHorizontalPadding(Style::spaceXs * scale);
          valueInput->setSize(50.0f * scale, Style::controlHeightSm * scale);
          auto* valueInputPtr = valueInput.get();

          auto slider = std::make_unique<Slider>();
          slider->setRange(minValue, maxValue);
          slider->setStep(step);
          slider->setSize(Style::sliderDefaultWidth * scale, Style::controlHeight * scale);
          slider->setControlHeight(Style::controlHeight * scale);
          slider->setThumbSize(Style::sliderThumbSize * scale);
          slider->setTrackHeight(Style::sliderTrackHeight * scale);
          slider->setValue(value);
          auto* sliderPtr = slider.get();
          slider->setOnValueChanged([valueInputPtr, integerValue](float next) {
            valueInputPtr->setInvalid(false);
            valueInputPtr->setValue(formatSliderValue(next, integerValue));
          });

          // Helper: commit either via single setOverride or as an atomic batch when linkedCommit
          // returns extra overrides (cross-field constraints).
          const auto commit = [setOverride = ctx.setOverride, setOverrides = ctx.setOverrides, path, integerValue,
                               linkedCommit](double v) {
            ConfigOverrideValue primary =
                integerValue ? ConfigOverrideValue{static_cast<std::int64_t>(std::lround(v))} : ConfigOverrideValue{v};
            if (linkedCommit) {
              auto extras = linkedCommit(v);
              if (!extras.empty()) {
                std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> all;
                all.reserve(extras.size() + 1);
                all.emplace_back(path, std::move(primary));
                for (auto& e : extras) {
                  all.push_back(std::move(e));
                }
                setOverrides(std::move(all));
                return;
              }
            }
            setOverride(path, std::move(primary));
          };

          slider->setOnDragEnd([commit, sliderPtr]() { commit(static_cast<double>(sliderPtr->value())); });

          const auto commitInputText = [commit, sliderPtr, valueInputPtr, minValue, maxValue,
                                        integerValue](const std::string& text) {
            const auto parsed = parseFloatInput(text);
            if (!parsed.has_value() || *parsed < minValue || *parsed > maxValue) {
              valueInputPtr->setInvalid(true);
              return;
            }
            const float v = *parsed;
            valueInputPtr->setInvalid(false);
            sliderPtr->setValue(v);
            if (!integerValue) {
              valueInputPtr->setValue(formatSliderValue(sliderPtr->value(), false));
            }
            commit(static_cast<double>(v));
          };

          valueInput->setOnChange([valueInputPtr](const std::string& /*text*/) { valueInputPtr->setInvalid(false); });
          valueInput->setOnSubmit([commitInputText](const std::string& text) { commitInputText(text); });
          valueInput->setOnFocusLoss([commitInputText, valueInputPtr]() { commitInputText(valueInputPtr->value()); });

          // Slider first, numeric value field on the right (reset from makeRow stays left of this cluster).
          wrap->addChild(std::move(slider));
          wrap->addChild(std::move(valueInput));
          return wrap;
        };

    const auto makeText = [&](const std::string& value, const std::string& placeholder, std::vector<std::string> path,
                              float width = 0.0f) {
      auto input = std::make_unique<Input>();
      input->setValue(value);
      input->setPlaceholder(placeholder.empty() ? i18n::tr("settings.controls.list.add-entry-placeholder")
                                                : placeholder);
      input->setFontSize(Style::fontSizeBody * scale);
      input->setControlHeight(Style::controlHeight * scale);
      input->setHorizontalPadding(Style::spaceSm * scale);
      const float inputWidth = (width > 0.0f ? width : 190.0f) * scale;
      input->setSize(inputWidth, Style::controlHeight * scale);
      input->setOnSubmit([setOverride = ctx.setOverride, path](const std::string& v) { setOverride(path, v); });
      return input;
    };

    const auto makeTextWithPathBrowse = [&](const TextSetting& setting, const std::vector<std::string>& path) {
      auto wrap = std::make_unique<Flex>();
      wrap->setDirection(FlexDirection::Horizontal);
      wrap->setAlign(FlexAlign::Center);
      wrap->setGap(Style::spaceSm * scale);

      auto input = std::make_unique<Input>();
      input->setValue(setting.value);
      input->setPlaceholder(setting.placeholder.empty() ? i18n::tr("settings.controls.list.add-entry-placeholder")
                                                        : setting.placeholder);
      input->setFontSize(Style::fontSizeBody * scale);
      input->setControlHeight(Style::controlHeight * scale);
      input->setHorizontalPadding(Style::spaceSm * scale);
      const float inputWidth = (setting.width > 0.0f ? setting.width : 280.0f) * scale;
      input->setSize(inputWidth, Style::controlHeight * scale);
      auto* inputPtr = input.get();
      input->setOnSubmit([setOverride = ctx.setOverride, path](const std::string& v) { setOverride(path, v); });
      wrap->addChild(std::move(input));

      const bool selectFolder = setting.browseMode == TextSettingBrowseMode::SelectFolder;
      auto browse = std::make_unique<Button>();
      browse->setVariant(ButtonVariant::Outline);
      browse->setGlyph(selectFolder ? "folder" : "file-text");
      browse->setGlyphSize(Style::fontSizeBody * scale);
      browse->setMinHeight(Style::controlHeight * scale);
      browse->setMinWidth(Style::controlHeight * scale);
      browse->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      browse->setRadius(Style::scaledRadiusMd(scale));
      browse->setOnClick(
          [setOverride = ctx.setOverride, path, inputPtr, selectFolder, exts = setting.browseFileExtensions]() {
            FileDialogOptions options;
            options.mode = selectFolder ? FileDialogMode::SelectFolder : FileDialogMode::Open;
            options.defaultViewMode = FileDialogViewMode::List;
            options.title = selectFolder ? i18n::tr("settings.controls.path-browse.folder-title")
                                         : i18n::tr("settings.controls.path-browse.file-title");
            if (!selectFolder) {
              options.extensions = exts;
            }
            const std::string cur = inputPtr->value();
            if (!cur.empty()) {
              std::filesystem::path p(cur);
              std::error_code ec;
              if (selectFolder) {
                if (std::filesystem::exists(p, ec) && std::filesystem::is_directory(p, ec)) {
                  options.startDirectory = p;
                } else if (p.has_parent_path()) {
                  const auto parent = p.parent_path();
                  if (std::filesystem::exists(parent, ec)) {
                    options.startDirectory = parent;
                  }
                }
              } else {
                if (std::filesystem::exists(p, ec) && std::filesystem::is_regular_file(p, ec)) {
                  options.startDirectory = p.parent_path();
                  options.defaultFilename = p.filename().string();
                } else if (p.has_parent_path() && std::filesystem::exists(p.parent_path(), ec)) {
                  options.startDirectory = p.parent_path();
                }
              }
            }
            (void)FileDialog::open(std::move(options),
                                   [setOverride, path, inputPtr](std::optional<std::filesystem::path> picked) {
                                     if (!picked.has_value()) {
                                       return;
                                     }
                                     const std::string s = picked->string();
                                     inputPtr->setValue(s);
                                     setOverride(path, s);
                                   });
          });
      wrap->addChild(std::move(browse));
      return wrap;
    };

    const auto makeGlyphText = [&](const TextSetting& setting, std::vector<std::string> path) -> std::unique_ptr<Node> {
      auto wrap = std::make_unique<Flex>();
      wrap->setDirection(FlexDirection::Horizontal);
      wrap->setAlign(FlexAlign::Center);
      wrap->setGap(Style::spaceSm * scale);
      wrap->addChild(makeText(setting.value, setting.placeholder, path, setting.width));

      auto pickerButton = std::make_unique<Button>();
      pickerButton->setVariant(ButtonVariant::Outline);
      pickerButton->setGlyph("apps");
      pickerButton->setGlyphSize(Style::fontSizeBody * scale);
      pickerButton->setMinHeight(Style::controlHeight * scale);
      pickerButton->setMinWidth(Style::controlHeight * scale);
      pickerButton->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      pickerButton->setRadius(Style::scaledRadiusMd(scale));
      pickerButton->setOnClick([setOverride = ctx.setOverride, path, currentValue = setting.value]() {
        GlyphPickerDialogOptions options;
        if (!currentValue.empty()) {
          options.initialGlyph = currentValue;
        }
        (void)GlyphPickerDialog::open(std::move(options), [setOverride, path](std::optional<GlyphPickerResult> result) {
          if (!result.has_value()) {
            return;
          }
          setOverride(path, result->name);
        });
      });
      wrap->addChild(std::move(pickerButton));
      return wrap;
    };

    const auto makeOptionalNumber = [&](const OptionalNumberSetting& setting, std::vector<std::string> path) {
      auto input = std::make_unique<Input>();
      input->setValue(setting.value.has_value() ? std::format("{}", *setting.value) : "");
      input->setPlaceholder(setting.placeholder);
      input->setFontSize(Style::fontSizeBody * scale);
      input->setControlHeight(Style::controlHeight * scale);
      input->setHorizontalPadding(Style::spaceSm * scale);
      input->setSize(190.0f * scale, Style::controlHeight * scale);
      auto* inputPtr = input.get();
      input->setOnChange([inputPtr](const std::string& /*text*/) { inputPtr->setInvalid(false); });
      input->setOnSubmit([configService = ctx.configService, clearOverride = ctx.clearOverride,
                          setOverride = ctx.setOverride, path, inputPtr, minValue = setting.minValue,
                          maxValue = setting.maxValue](const std::string& text) {
        if (isBlankInput(text)) {
          inputPtr->setInvalid(false);
          if (configService != nullptr && configService->hasOverride(path)) {
            clearOverride(path);
          }
          return;
        }

        const auto parsed = parseDoubleInput(text);
        if (!parsed.has_value() || *parsed < minValue || *parsed > maxValue) {
          inputPtr->setInvalid(true);
          return;
        }

        inputPtr->setInvalid(false);
        setOverride(path, *parsed);
      });
      return input;
    };

    const auto makeStepper = [&](const StepperSetting& setting, std::vector<std::string> path) {
      const int minValue = std::min(setting.minValue, setting.maxValue);
      const int maxValue = std::max(setting.minValue, setting.maxValue);
      const int currentValue = std::clamp(setting.value, minValue, maxValue);

      auto stepper = std::make_unique<Stepper>();
      stepper->setScale(scale);
      stepper->setRange(minValue, maxValue);
      stepper->setStep(setting.step);
      if (!setting.valueSuffix.empty()) {
        stepper->setValueSuffix(setting.valueSuffix);
      }
      stepper->setValue(currentValue);
      stepper->setOnValueCommitted(
          [setOverride = ctx.setOverride, path](int value) { setOverride(path, static_cast<double>(value)); });
      return stepper;
    };

    const auto makeOptionalStepper = [&](const OptionalStepperSetting& setting, std::vector<std::string> path) {
      auto wrap = std::make_unique<Flex>();
      wrap->setDirection(FlexDirection::Horizontal);
      wrap->setAlign(FlexAlign::Center);
      wrap->setGap(Style::spaceSm * scale);

      const int minValue = std::min(setting.minValue, setting.maxValue);
      const int maxValue = std::max(setting.minValue, setting.maxValue);
      const int currentValue = std::clamp(setting.value.value_or(setting.fallbackValue), minValue, maxValue);

      auto segmented = std::make_unique<Segmented>();
      segmented->setScale(scale);
      segmented->addOption(setting.unsetLabel);
      segmented->addOption(setting.customLabel);
      segmented->setSelectedIndex(setting.value.has_value() ? 1 : 0);
      segmented->setOnChange([configService = ctx.configService, clearOverride = ctx.clearOverride,
                              requestRebuild = ctx.requestRebuild, setOverride = ctx.setOverride, path,
                              currentValue](std::size_t index) {
        if (index == 0) {
          if (configService != nullptr && configService->hasOverride(path)) {
            clearOverride(path);
          } else if (requestRebuild) {
            requestRebuild();
          }
          return;
        }
        setOverride(path, static_cast<double>(currentValue));
      });

      auto stepper = std::make_unique<Stepper>();
      stepper->setScale(scale);
      stepper->setRange(minValue, maxValue);
      stepper->setStep(setting.step);
      stepper->setValue(currentValue);
      stepper->setEnabled(setting.value.has_value());
      stepper->setOnValueCommitted(
          [setOverride = ctx.setOverride, path](int value) { setOverride(path, static_cast<double>(value)); });

      wrap->addChild(std::move(segmented));
      wrap->addChild(std::move(stepper));
      return wrap;
    };

    const auto makeColorSpecPicker = [&](const ColorSpecPickerSetting& setting,
                                         std::vector<std::string> path) -> std::unique_ptr<Node> {
      ColorSpecSelectOptions options{
          .roles = setting.roles,
          .selectedValue = setting.selectedValue,
          .allowNone = setting.allowNone,
          .allowCustomColor = setting.allowCustomColor,
          .noneLabel = setting.noneLabel,
          .fontSize = Style::fontSizeBody * scale,
          .controlHeight = Style::controlHeight * scale,
          .glyphSize = Style::fontSizeBody * scale,
          .width = 190.0f * scale,
      };
      return makeColorSpecSelect(
          std::move(options), [setOverride = ctx.setOverride, path](std::string value) { setOverride(path, value); },
          [configService = ctx.configService, clearOverride = ctx.clearOverride, requestRebuild = ctx.requestRebuild,
           path]() {
            if (configService != nullptr && configService->hasOverride(path)) {
              clearOverride(path);
            } else {
              requestRebuild();
            }
          });
    };

    const auto makeSearchPickerButton = [&](const SettingEntry& entry,
                                            const SearchPickerSetting& setting) -> std::unique_ptr<Node> {
      auto button = std::make_unique<Button>();
      button->setVariant(ButtonVariant::Outline);
      button->setGlyph("search");
      button->setText(optionLabel(setting.options, setting.selectedValue));
      button->setContentAlign(ButtonContentAlign::Start);
      button->setFontSize(Style::fontSizeBody * scale);
      button->setGlyphSize(Style::fontSizeBody * scale);
      button->setMinWidth(190.0f * scale);
      button->setMinHeight(Style::controlHeight * scale);
      button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      button->setRadius(Style::scaledRadiusMd(scale));
      button->setOnClick([openPopup = ctx.openSearchPickerPopup, title = entry.title, options = setting.options,
                          selectedValue = setting.selectedValue, placeholder = setting.placeholder,
                          emptyText = setting.emptyText, path = entry.path]() {
        if (openPopup) {
          openPopup(title, options, selectedValue, placeholder, emptyText, path);
        }
      });
      return button;
    };

    const auto makeMultiSelectBlock = [&](Flex& section, const SettingEntry& entry, const MultiSelectSetting& setting) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        block->addChild(makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      }

      auto checkRow = std::make_unique<Flex>();
      checkRow->setDirection(FlexDirection::Horizontal);
      checkRow->setAlign(FlexAlign::Center);
      checkRow->setGap(Style::spaceMd * scale);
      checkRow->setPadding(Style::spaceXs * scale, 0.0f);

      auto options = setting.options;
      auto selected = setting.selectedValues;
      const bool requireAtLeastOne = setting.requireAtLeastOne;
      auto path = entry.path;

      for (const auto& option : options) {
        auto item = std::make_unique<Flex>();
        item->setDirection(FlexDirection::Horizontal);
        item->setAlign(FlexAlign::Center);
        item->setGap(Style::spaceXs * scale);

        auto checkbox = std::make_unique<Checkbox>();
        checkbox->setScale(scale);
        const bool isSelected = std::find(selected.begin(), selected.end(), option.value) != selected.end();
        checkbox->setChecked(isSelected);
        const std::string optionValue = option.value;
        checkbox->setOnChange([setOverride = ctx.setOverride, requestRebuild = ctx.requestRebuild, path, options,
                               selected, optionValue, requireAtLeastOne](bool checked) mutable {
          auto it = std::find(selected.begin(), selected.end(), optionValue);
          if (checked) {
            if (it == selected.end()) {
              selected.push_back(optionValue);
            }
          } else {
            if (it != selected.end()) {
              if (requireAtLeastOne && selected.size() <= 1) {
                requestRebuild();
                return;
              }
              selected.erase(it);
            }
          }
          // Preserve the option order so the override file is stable.
          std::vector<std::string> ordered;
          ordered.reserve(selected.size());
          for (const auto& opt : options) {
            if (std::find(selected.begin(), selected.end(), opt.value) != selected.end()) {
              ordered.push_back(opt.value);
            }
          }
          setOverride(path, ordered);
        });
        item->addChild(std::move(checkbox));
        item->addChild(
            makeLabel(option.label, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), false));

        checkRow->addChild(std::move(item));
      }

      block->addChild(std::move(checkRow));
      section.addChild(std::move(block));
    };

    const auto makeListBlock = [&](Flex& section, const SettingEntry& entry, const ListSetting& list) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
      }
      if (overridden) {
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        block->addChild(makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      }

      auto listEditor = std::make_unique<ListEditor>();
      listEditor->setScale(scale);
      listEditor->setAddPlaceholder(i18n::tr("settings.controls.list.add-entry-placeholder"));
      std::vector<ListEditorOption> suggestedOptions;
      suggestedOptions.reserve(list.suggestedOptions.size());
      for (const auto& opt : list.suggestedOptions) {
        suggestedOptions.push_back(ListEditorOption{.value = opt.value, .label = opt.label});
      }
      listEditor->setSuggestedOptions(std::move(suggestedOptions));
      listEditor->setItems(list.items);
      listEditor->setOnAddRequested(
          [setOverride = ctx.setOverride, items = list.items, path = entry.path](std::string value) mutable {
            if (value.empty()) {
              return;
            }
            items.push_back(std::move(value));
            setOverride(path, items);
          });
      listEditor->setOnRemoveRequested([setOverride = ctx.setOverride, setOverrides = ctx.setOverrides,
                                        config = std::cref(cfg), items = list.items,
                                        path = entry.path](std::size_t index) mutable {
        if (index >= items.size()) {
          return;
        }
        const std::string removedItem = items[index];
        items.erase(items.begin() + static_cast<std::ptrdiff_t>(index));
        const auto overrides = capsuleGroupRemovalOverrides(config.get(), path, removedItem, items);
        if (overrides.size() == 1) {
          setOverride(path, items);
          return;
        }
        setOverrides(overrides);
      });
      listEditor->setOnMoveRequested([setOverride = ctx.setOverride, items = list.items,
                                      path = entry.path](std::size_t from, std::size_t to) mutable {
        if (from >= items.size() || to >= items.size() || from == to) {
          return;
        }
        std::swap(items[from], items[to]);
        setOverride(path, items);
      });
      block->addChild(std::move(listEditor));

      section.addChild(std::move(block));
    };

    const auto makeKeybindListBlock = [&](Flex& section, const SettingEntry& entry,
                                          const KeybindListSetting& keybinds) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);
      block->setFillWidth(true);
      block->setFlexGrow(1.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      // Reserve the Reset button's height so columns line up even when only some are overridden.
      titleRow->setMinHeight(Style::controlHeightSm * scale);
      auto titleLabel =
          makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
      titleLabel->setMaxLines(2);
      titleLabel->setFlexGrow(1.0f);
      titleRow->addChild(std::move(titleLabel));
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
      }
      if (overridden) {
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      // Always reserve two caption lines so blocks line up regardless of how their description wraps.
      auto subtitleBox = std::make_unique<Flex>();
      subtitleBox->setDirection(FlexDirection::Vertical);
      subtitleBox->setAlign(FlexAlign::Stretch);
      subtitleBox->setMinHeight(2.0f * Style::fontSizeCaption * 1.4f * scale);
      if (!entry.subtitle.empty()) {
        auto subtitle = makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false);
        subtitle->setMaxLines(2);
        subtitleBox->addChild(std::move(subtitle));
      }
      block->addChild(std::move(subtitleBox));

      auto list = std::make_unique<Flex>();
      list->setDirection(FlexDirection::Vertical);
      list->setAlign(FlexAlign::Stretch);
      list->setGap(Style::spaceXs * scale);

      // An empty list clears the override so defaults take effect again; never persist as "disabled".
      // If no GUI override exists, request a rebuild so the UI snaps back to the underlying default.
      const auto commitItems = [configService = ctx.configService, setOverride = ctx.setOverride,
                                clearOverride = ctx.clearOverride, requestRebuild = ctx.requestRebuild,
                                path = entry.path](std::vector<KeyChord> items) {
        if (items.empty()) {
          if (configService != nullptr && configService->hasOverride(path)) {
            if (clearOverride) {
              clearOverride(path);
            }
          } else if (requestRebuild) {
            requestRebuild();
          }
          return;
        }
        setOverride(path, items);
      };

      for (std::size_t i = 0; i < keybinds.items.size(); ++i) {
        auto row = std::make_unique<Flex>();
        row->setDirection(FlexDirection::Horizontal);
        row->setAlign(FlexAlign::Center);
        row->setGap(Style::spaceXs * scale);

        auto recorder = std::make_unique<KeybindRecorder>();
        recorder->setScale(scale);
        recorder->setChord(keybinds.items[i]);
        recorder->setUnsetPlaceholder(i18n::tr("settings.controls.keybind.unset-placeholder"));
        recorder->setRecordingPlaceholder(i18n::tr("settings.controls.keybind.recording-placeholder"));
        recorder->setOnCommit([commitItems, items = keybinds.items, i](KeyChord chord) mutable {
          if (i < items.size()) {
            items[i] = chord;
            commitItems(std::move(items));
          }
        });
        row->addChild(std::move(recorder));

        auto removeBtn = std::make_unique<Button>();
        removeBtn->setGlyph("close");
        removeBtn->setVariant(ButtonVariant::Ghost);
        removeBtn->setGlyphSize(Style::fontSizeCaption * scale);
        removeBtn->setMinWidth(Style::controlHeightSm * scale);
        removeBtn->setMinHeight(Style::controlHeightSm * scale);
        removeBtn->setPadding(Style::spaceXs * scale);
        removeBtn->setRadius(Style::scaledRadiusSm(scale));
        removeBtn->setOnClick([commitItems, items = keybinds.items, i]() mutable {
          if (i >= items.size()) {
            return;
          }
          items.erase(items.begin() + static_cast<std::ptrdiff_t>(i));
          commitItems(std::move(items));
        });
        row->addChild(std::move(removeBtn));

        list->addChild(std::move(row));
      }

      const bool canAdd = (keybinds.maxItems == 0 || keybinds.items.size() < keybinds.maxItems);
      if (canAdd) {
        // Trailing recorder is UI-only; it only joins the persisted list once a chord is recorded.
        auto addRow = std::make_unique<Flex>();
        addRow->setDirection(FlexDirection::Horizontal);
        addRow->setAlign(FlexAlign::Center);
        addRow->setGap(Style::spaceXs * scale);

        auto addRecorder = std::make_unique<KeybindRecorder>();
        addRecorder->setScale(scale);
        addRecorder->setUnsetPlaceholder(i18n::tr("settings.controls.keybind.add"));
        addRecorder->setRecordingPlaceholder(i18n::tr("settings.controls.keybind.recording-placeholder"));
        addRecorder->setOnCommit([commitItems, items = keybinds.items](KeyChord chord) mutable {
          items.push_back(chord);
          commitItems(std::move(items));
        });
        addRow->addChild(std::move(addRecorder));

        list->addChild(std::move(addRow));
      }

      block->addChild(std::move(list));

      section.addChild(std::move(block));
    };

    const auto makeShortcutListBlock = [&](Flex& section, const SettingEntry& entry,
                                           const ShortcutListSetting& shortcuts) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
      }
      if (overridden) {
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        block->addChild(makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      }

      std::vector<std::string> itemTypes;
      itemTypes.reserve(shortcuts.items.size());
      for (const auto& item : shortcuts.items) {
        itemTypes.push_back(item.type);
      }

      std::vector<ListEditorOption> suggestedOptions;
      suggestedOptions.reserve(shortcuts.suggestedOptions.size());
      for (const auto& opt : shortcuts.suggestedOptions) {
        suggestedOptions.push_back(ListEditorOption{.value = opt.value, .label = opt.label});
      }

      auto listEditor = std::make_unique<ListEditor>();
      listEditor->setScale(scale);
      listEditor->setMaxItems(shortcuts.maxItems);
      listEditor->setAddPlaceholder(i18n::tr("settings.controls.list.add-entry-placeholder"));
      listEditor->setSuggestedOptions(std::move(suggestedOptions));
      listEditor->setItems(std::move(itemTypes));
      listEditor->setOnAddRequested(
          [setOverride = ctx.setOverride, items = shortcuts.items, path = entry.path](std::string value) mutable {
            if (value.empty() || std::any_of(items.begin(), items.end(),
                                             [&value](const ShortcutConfig& item) { return item.type == value; })) {
              return;
            }
            items.push_back(ShortcutConfig{std::move(value)});
            setOverride(path, items);
          });
      listEditor->setOnRemoveRequested(
          [setOverride = ctx.setOverride, items = shortcuts.items, path = entry.path](std::size_t index) mutable {
            if (index >= items.size()) {
              return;
            }
            items.erase(items.begin() + static_cast<std::ptrdiff_t>(index));
            setOverride(path, items);
          });
      listEditor->setOnMoveRequested([setOverride = ctx.setOverride, items = shortcuts.items,
                                      path = entry.path](std::size_t from, std::size_t to) mutable {
        if (from >= items.size() || to >= items.size() || from == to) {
          return;
        }
        std::swap(items[from], items[to]);
        setOverride(path, items);
      });
      block->addChild(std::move(listEditor));

      section.addChild(std::move(block));
    };

    const auto makeSessionActionsInlineBlock = [&](Flex& section, const SettingEntry& entry,
                                                   const SessionPanelActionsSetting& sa) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
      }
      if (overridden) {
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        block->addChild(makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      }

      const std::vector<SelectOption> kindOptions = {
          {"lock", i18n::tr("settings.session-actions.kind.lock"), {}},
          {"logout", i18n::tr("settings.session-actions.kind.logout"), {}},
          {"suspend", i18n::tr("settings.session-actions.kind.suspend"), {}},
          {"reboot", i18n::tr("settings.session-actions.kind.reboot"), {}},
          {"shutdown", i18n::tr("settings.session-actions.kind.shutdown"), {}},
          {"command", i18n::tr("settings.session-actions.kind.command"), {}},
      };

      auto state = std::make_shared<std::vector<SessionPanelActionConfig>>(sa.items);
      const auto commit = [setOverride = ctx.setOverride, path = entry.path, state, req = ctx.requestContentRebuild]() {
        setOverride(path, *state);
        req();
      };

      const float iconBtnH = Style::controlHeight * scale;

      for (std::size_t idx = 0; idx < state->size(); ++idx) {
        auto row = std::make_unique<Flex>();
        row->setDirection(FlexDirection::Horizontal);
        row->setAlign(FlexAlign::Center);
        row->setJustify(FlexJustify::SpaceBetween);
        row->setGap(Style::spaceSm * scale);
        row->setMinHeight(Style::controlHeightSm * scale);

        auto summary = std::make_unique<Label>();
        summary->setText(sessionActionRowSummary(kindOptions, (*state)[idx]));
        summary->setFontSize(Style::fontSizeBody * scale);
        summary->setColor(colorSpecFromRole(ColorRole::OnSurface));
        summary->setFlexGrow(1.0f);
        row->addChild(std::move(summary));

        auto reorder = std::make_unique<Flex>();
        reorder->setDirection(FlexDirection::Horizontal);
        reorder->setAlign(FlexAlign::Center);
        reorder->setGap(Style::spaceXs * scale);

        auto upBtn = std::make_unique<Button>();
        upBtn->setGlyph("chevron-up");
        upBtn->setVariant(ButtonVariant::Ghost);
        upBtn->setGlyphSize(Style::fontSizeBody * scale);
        upBtn->setMinWidth(Style::controlHeightSm * scale);
        upBtn->setMinHeight(iconBtnH);
        upBtn->setPadding(Style::spaceXs * scale);
        upBtn->setRadius(Style::scaledRadiusMd(scale));
        upBtn->setEnabled(idx > 0);
        upBtn->setOnClick([state, rowIndex = idx, commit]() {
          if (rowIndex == 0 || rowIndex >= state->size()) {
            return;
          }
          std::swap((*state)[rowIndex - 1], (*state)[rowIndex]);
          commit();
        });
        reorder->addChild(std::move(upBtn));

        auto downBtn = std::make_unique<Button>();
        downBtn->setGlyph("chevron-down");
        downBtn->setVariant(ButtonVariant::Ghost);
        downBtn->setGlyphSize(Style::fontSizeBody * scale);
        downBtn->setMinWidth(Style::controlHeightSm * scale);
        downBtn->setMinHeight(iconBtnH);
        downBtn->setPadding(Style::spaceXs * scale);
        downBtn->setRadius(Style::scaledRadiusMd(scale));
        downBtn->setEnabled(idx + 1 < state->size());
        downBtn->setOnClick([state, rowIndex = idx, commit]() {
          if (rowIndex + 1 >= state->size()) {
            return;
          }
          std::swap((*state)[rowIndex + 1], (*state)[rowIndex]);
          commit();
        });
        reorder->addChild(std::move(downBtn));
        row->addChild(std::move(reorder));

        auto entrySettings = std::make_unique<Button>();
        entrySettings->setGlyph("settings");
        entrySettings->setVariant(ButtonVariant::Ghost);
        entrySettings->setGlyphSize(Style::fontSizeCaption * scale);
        entrySettings->setMinWidth(Style::controlHeightSm * scale);
        entrySettings->setMinHeight(Style::controlHeightSm * scale);
        entrySettings->setPadding(Style::spaceXs * scale);
        entrySettings->setRadius(Style::scaledRadiusSm(scale));
        entrySettings->setOnClick([openEntry = ctx.openSessionActionEntryEditor, rowIndex = idx]() {
          if (openEntry) {
            openEntry(rowIndex);
          }
        });
        row->addChild(std::move(entrySettings));

        auto enabledToggle = std::make_unique<Toggle>();
        enabledToggle->setScale(scale);
        enabledToggle->setChecked((*state)[idx].enabled);
        enabledToggle->setOnChange([state, rowIndex = idx, commit](bool v) {
          (*state)[rowIndex].enabled = v;
          commit();
        });
        row->addChild(std::move(enabledToggle));

        block->addChild(std::move(row));
      }

      auto addBtn = std::make_unique<Button>();
      addBtn->setGlyph("add");
      addBtn->setText(i18n::tr("settings.session-actions.add"));
      addBtn->setVariant(ButtonVariant::Default);
      addBtn->setFontSize(Style::fontSizeBody * scale);
      addBtn->setGlyphSize(Style::fontSizeBody * scale);
      addBtn->setMinHeight(Style::controlHeight * scale);
      addBtn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      addBtn->setRadius(Style::scaledRadiusMd(scale));
      addBtn->setOnClick([state, commit]() {
        state->push_back(SessionPanelActionConfig{"command", true, "notify-send 'Noctalia' 'Custom session entry'",
                                                  std::nullopt, std::nullopt, SessionActionButtonVariant::Default});
        commit();
      });
      block->addChild(std::move(addBtn));

      section.addChild(std::move(block));
    };

    const auto makeIdleBehaviorsInlineBlock = [&](Flex& section, const SettingEntry& entry,
                                                  const IdleBehaviorsSetting& idle) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasEffectiveOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->setFillWidth(true);
      {
        auto tl = makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true);
        tl->setFlexGrow(1.0f);
        titleRow->addChild(std::move(tl));
      }
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::scaledRadiusSm(scale));
        badge->setFill(colorSpecFromRole(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badges.override"), Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::Primary), true));
        titleRow->addChild(std::move(badge));
        titleRow->addChild(makeResetButton(entry.path));
      }
      block->addChild(std::move(titleRow));

      if (!entry.subtitle.empty()) {
        block->addChild(makeLabel(entry.subtitle, Style::fontSizeCaption * scale,
                                  colorSpecFromRole(ColorRole::OnSurfaceVariant), false));
      }

      auto state = std::make_shared<std::vector<IdleBehaviorConfig>>(idle.items);
      normalizeIdleBehaviorNames(*state);
      const auto commit = [setOverride = ctx.setOverride, path = entry.path, state, req = ctx.requestContentRebuild]() {
        normalizeIdleBehaviorNames(*state);
        setOverride(path, *state);
        req();
      };

      const float iconBtnH = Style::controlHeight * scale;
      for (std::size_t idx = 0; idx < state->size(); ++idx) {
        auto row = std::make_unique<Flex>();
        row->setDirection(FlexDirection::Horizontal);
        row->setAlign(FlexAlign::Center);
        row->setJustify(FlexJustify::SpaceBetween);
        row->setGap(Style::spaceSm * scale);
        row->setMinHeight(Style::controlHeightSm * scale);

        auto summary = std::make_unique<Label>();
        summary->setText(idleBehaviorRowSummary((*state)[idx]));
        summary->setFontSize(Style::fontSizeBody * scale);
        summary->setColor(colorSpecFromRole(ColorRole::OnSurface));
        summary->setFlexGrow(1.0f);
        row->addChild(std::move(summary));

        auto reorder = std::make_unique<Flex>();
        reorder->setDirection(FlexDirection::Horizontal);
        reorder->setAlign(FlexAlign::Center);
        reorder->setGap(Style::spaceXs * scale);

        auto upBtn = std::make_unique<Button>();
        upBtn->setGlyph("chevron-up");
        upBtn->setVariant(ButtonVariant::Ghost);
        upBtn->setGlyphSize(Style::fontSizeBody * scale);
        upBtn->setMinWidth(Style::controlHeightSm * scale);
        upBtn->setMinHeight(iconBtnH);
        upBtn->setPadding(Style::spaceXs * scale);
        upBtn->setRadius(Style::scaledRadiusMd(scale));
        upBtn->setEnabled(idx > 0);
        upBtn->setOnClick([state, rowIndex = idx, commit]() {
          if (rowIndex == 0 || rowIndex >= state->size()) {
            return;
          }
          std::swap((*state)[rowIndex - 1], (*state)[rowIndex]);
          commit();
        });
        reorder->addChild(std::move(upBtn));

        auto downBtn = std::make_unique<Button>();
        downBtn->setGlyph("chevron-down");
        downBtn->setVariant(ButtonVariant::Ghost);
        downBtn->setGlyphSize(Style::fontSizeBody * scale);
        downBtn->setMinWidth(Style::controlHeightSm * scale);
        downBtn->setMinHeight(iconBtnH);
        downBtn->setPadding(Style::spaceXs * scale);
        downBtn->setRadius(Style::scaledRadiusMd(scale));
        downBtn->setEnabled(idx + 1 < state->size());
        downBtn->setOnClick([state, rowIndex = idx, commit]() {
          if (rowIndex + 1 >= state->size()) {
            return;
          }
          std::swap((*state)[rowIndex + 1], (*state)[rowIndex]);
          commit();
        });
        reorder->addChild(std::move(downBtn));
        row->addChild(std::move(reorder));

        auto entrySettings = std::make_unique<Button>();
        entrySettings->setGlyph("settings");
        entrySettings->setVariant(ButtonVariant::Ghost);
        entrySettings->setGlyphSize(Style::fontSizeCaption * scale);
        entrySettings->setMinWidth(Style::controlHeightSm * scale);
        entrySettings->setMinHeight(Style::controlHeightSm * scale);
        entrySettings->setPadding(Style::spaceXs * scale);
        entrySettings->setRadius(Style::scaledRadiusSm(scale));
        entrySettings->setOnClick([openEntry = ctx.openIdleBehaviorEntryEditor, rowIndex = idx]() {
          if (openEntry) {
            openEntry(rowIndex);
          }
        });
        row->addChild(std::move(entrySettings));

        auto enabledToggle = std::make_unique<Toggle>();
        enabledToggle->setScale(scale);
        enabledToggle->setChecked((*state)[idx].enabled);
        enabledToggle->setOnChange([state, rowIndex = idx, commit](bool v) {
          (*state)[rowIndex].enabled = v;
          commit();
        });
        row->addChild(std::move(enabledToggle));

        block->addChild(std::move(row));
      }

      auto addBtn = std::make_unique<Button>();
      addBtn->setGlyph("add");
      addBtn->setText(i18n::tr("settings.idle.behavior.add"));
      addBtn->setVariant(ButtonVariant::Default);
      addBtn->setFontSize(Style::fontSizeBody * scale);
      addBtn->setGlyphSize(Style::fontSizeBody * scale);
      addBtn->setMinHeight(Style::controlHeight * scale);
      addBtn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      addBtn->setRadius(Style::scaledRadiusMd(scale));
      addBtn->setOnClick([openCreate = ctx.openIdleBehaviorCreateEditor]() {
        if (openCreate) {
          openCreate();
        }
      });
      block->addChild(std::move(addBtn));

      section.addChild(std::move(block));
    };

    const auto makeControl = [&](const SettingEntry& entry) -> std::unique_ptr<Node> {
      return std::visit(
          [&](const auto& control) -> std::unique_ptr<Node> {
            using T = std::decay_t<decltype(control)>;
            if constexpr (std::is_same_v<T, ToggleSetting>) {
              return makeToggle(control.checked, control.enabled, entry.path);
            } else if constexpr (std::is_same_v<T, SelectSetting>) {
              return makeSelect(control, entry.path);
            } else if constexpr (std::is_same_v<T, SliderSetting>) {
              return makeSlider(control.value, control.minValue, control.maxValue, control.step, entry.path,
                                control.integerValue, control.linkedCommit);
            } else if constexpr (std::is_same_v<T, TextSetting>) {
              if (isDockLauncherIconPath(entry.path)) {
                return makeGlyphText(control, entry.path);
              }
              if (control.browseMode != TextSettingBrowseMode::None) {
                return makeTextWithPathBrowse(control, entry.path);
              }
              return makeText(control.value, control.placeholder, entry.path, control.width);
            } else if constexpr (std::is_same_v<T, OptionalNumberSetting>) {
              return makeOptionalNumber(control, entry.path);
            } else if constexpr (std::is_same_v<T, OptionalStepperSetting>) {
              return makeOptionalStepper(control, entry.path);
            } else if constexpr (std::is_same_v<T, StepperSetting>) {
              return makeStepper(control, entry.path);
            } else if constexpr (std::is_same_v<T, SearchPickerSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, MultiSelectSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, ListSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, ShortcutListSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, KeybindListSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, SessionPanelActionsSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, IdleBehaviorsSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, ButtonSetting>) {
              auto button = std::make_unique<Button>();
              button->setVariant(ButtonVariant::Outline);
              if (!control.glyph.empty()) {
                button->setGlyph(control.glyph);
                button->setGlyphSize(Style::fontSizeBody * scale);
              }
              button->setText(control.label);
              button->setFontSize(Style::fontSizeBody * scale);
              button->setMinHeight(Style::controlHeight * scale);
              button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
              button->setRadius(Style::scaledRadiusMd(scale));
              button->setOnClick(control.action);
              return button;
            } else if constexpr (std::is_same_v<T, ColorSpecPickerSetting>) {
              return makeColorSpecPicker(control, entry.path);
            }
          },
          entry.control);
    };

    std::string activeSectionKey;
    std::string activeGroupKey;
    Flex* activeSection = nullptr;
    // Row-major grid state for keybind entries (see KeybindListSetting dispatch below).
    constexpr std::size_t kKeybindsPerRow = 3;
    Flex* activeKeybindRow = nullptr;
    std::size_t activeKeybindRowCount = 0;
    std::size_t visibleEntries = 0;
    const std::string normalizedSearchQuery = normalizedSettingQuery(ctx.searchQuery);

    BarWidgetEditorContext barWidgetEditorCtx{
        .config = cfg,
        .configService = ctx.configService,
        .scale = scale,
        .showAdvanced = ctx.showAdvanced,
        .showOverriddenOnly = ctx.showOverriddenOnly,
        .batteryDeviceOptions = ctx.batteryDeviceOptions,
        .editingWidgetName = ctx.editingWidgetName,
        .pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
        .pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
        .renamingWidgetName = ctx.renamingWidgetName,
        .requestRebuild = ctx.requestRebuild,
        .resetContentScroll = ctx.resetContentScroll,
        .setScrollTarget = ctx.setScrollTarget,
        .focusArea = ctx.focusArea,
        .openWidgetAddPopup = ctx.openBarWidgetAddPopup,
        .setOverride = ctx.setOverride,
        .setOverrides = ctx.setOverrides,
        .clearOverride = ctx.clearOverride,
        .renameWidgetInstance = ctx.renameWidgetInstance,
        .makeResetButton = makeResetButton,
        .makeRow = makeRow,
        .makeToggle = [&](bool checked, std::vector<std::string> path, std::optional<bool> clearWhenValue)
            -> std::unique_ptr<Node> { return makeToggle(checked, true, std::move(path), clearWhenValue); },
        .makeSelect = [&](const SelectSetting& setting, std::vector<std::string> path) -> std::unique_ptr<Node> {
          return makeSelect(setting, std::move(path));
        },
        .makeSlider = [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
                          bool integerValue) -> std::unique_ptr<Node> {
          return makeSlider(value, minValue, maxValue, step, std::move(path), integerValue);
        },
        .makeOptionalNumber = [&](const OptionalNumberSetting& setting, std::vector<std::string> path)
            -> std::unique_ptr<Node> { return makeOptionalNumber(setting, std::move(path)); },
        .makeOptionalStepper = [&](const OptionalStepperSetting& setting, std::vector<std::string> path)
            -> std::unique_ptr<Node> { return makeOptionalStepper(setting, std::move(path)); },
        .makeText = [&](const std::string& value, const std::string& placeholder,
                        std::vector<std::string> path) -> std::unique_ptr<Node> {
          return makeText(value, placeholder, std::move(path));
        }, // width not used in search
        .makeColorSpecPicker = [&](const ColorSpecPickerSetting& setting, std::vector<std::string> path)
            -> std::unique_ptr<Node> { return makeColorSpecPicker(setting, std::move(path)); },
        .makeListBlock = [&](Flex& section, const SettingEntry& entry,
                             const ListSetting& list) { makeListBlock(section, entry, list); },
    };

    auto visibilityConditionMatches = [&](const SettingVisibilityCondition& cond) -> bool {
      for (const auto& other : registry) {
        if (other.path == cond.path) {
          std::string currentValue;
          if (const auto* toggle = std::get_if<ToggleSetting>(&other.control)) {
            currentValue = toggle->checked ? "true" : "false";
          } else if (const auto* select = std::get_if<SelectSetting>(&other.control)) {
            currentValue = select->selectedValue;
          }
          for (const auto& v : cond.values) {
            if (v == currentValue) {
              return true;
            }
          }
          return false;
        }
      }
      return true;
    };

    auto isEntryVisible = [&](const SettingEntry& e) -> bool {
      if (!e.visibleWhen.has_value()) {
        return true;
      }
      for (const auto& cond : e.visibleWhen->all) {
        if (!visibilityConditionMatches(cond)) {
          return false;
        }
      }
      return true;
    };

    for (const auto& entry : registry) {
      if (ctx.searchQuery.empty() && !ctx.selectedSection.empty() && entry.section != ctx.selectedSection) {
        continue;
      }
      if (!ctx.showAdvanced && entry.advanced) {
        continue;
      }
      if (!isEntryVisible(entry)) {
        continue;
      }
      if (ctx.showOverriddenOnly && ctx.configService != nullptr &&
          !ctx.configService->hasEffectiveOverride(entry.path)) {
        continue;
      }
      if (!matchesNormalizedSettingQuery(entry, normalizedSearchQuery)) {
        continue;
      }

      if (entry.section != activeSectionKey) {
        activeSectionKey = entry.section;
        activeGroupKey.clear();
        activeKeybindRow = nullptr;
        activeKeybindRowCount = 0;
        std::string displayTitle;
        if (entry.section == "bar" && ctx.selectedBar != nullptr) {
          displayTitle = i18n::tr("settings.entities.bar.label", "name", ctx.selectedBar->name);
          if (ctx.selectedMonitorOverride != nullptr) {
            displayTitle += " / " + ctx.selectedMonitorOverride->match;
          }
        } else {
          displayTitle = sectionLabel(entry.section);
        }
        activeSection = makeSection(displayTitle, entry.section);
        if (entry.section == "idle") {
          addIdleLiveStatusPanel(*activeSection, ctx, scale);
        }
      }
      if (activeSection != nullptr) {
        if (entry.group != activeGroupKey) {
          const bool isFirstGroup = activeGroupKey.empty();
          activeGroupKey = entry.group;
          activeKeybindRow = nullptr;
          activeKeybindRowCount = 0;
          addGroupLabel(*activeSection, groupLabel(entry.group), isFirstGroup);
        }
        const bool isKeybindEntry = std::holds_alternative<KeybindListSetting>(entry.control);
        if (!isKeybindEntry) {
          activeKeybindRow = nullptr;
          activeKeybindRowCount = 0;
        }
        if (const auto* list = std::get_if<ListSetting>(&entry.control)) {
          if (isFirstBarWidgetListPath(entry.path)) {
            addBarWidgetLaneEditor(*activeSection, entry, barWidgetEditorCtx);
          } else if (!isBarWidgetListPath(entry.path)) {
            makeListBlock(*activeSection, entry, *list);
          }
        } else if (const auto* shortcuts = std::get_if<ShortcutListSetting>(&entry.control)) {
          makeShortcutListBlock(*activeSection, entry, *shortcuts);
        } else if (const auto* keybindList = std::get_if<KeybindListSetting>(&entry.control)) {
          if (activeKeybindRow == nullptr || activeKeybindRowCount >= kKeybindsPerRow) {
            auto row = std::make_unique<Flex>();
            row->setDirection(FlexDirection::Horizontal);
            row->setAlign(FlexAlign::Start);
            row->setGap(Style::spaceMd * scale);
            row->setFillWidth(true);
            activeKeybindRow = static_cast<Flex*>(activeSection->addChild(std::move(row)));
            activeKeybindRowCount = 0;
          }
          makeKeybindListBlock(*activeKeybindRow, entry, *keybindList);
          ++activeKeybindRowCount;
        } else if (const auto* sessionActs = std::get_if<SessionPanelActionsSetting>(&entry.control)) {
          makeSessionActionsInlineBlock(*activeSection, entry, *sessionActs);
        } else if (const auto* idle = std::get_if<IdleBehaviorsSetting>(&entry.control)) {
          makeIdleBehaviorsInlineBlock(*activeSection, entry, *idle);
        } else if (const auto* picker = std::get_if<SearchPickerSetting>(&entry.control)) {
          makeRow(*activeSection, entry, makeSearchPickerButton(entry, *picker));
        } else if (const auto* multi = std::get_if<MultiSelectSetting>(&entry.control)) {
          makeMultiSelectBlock(*activeSection, entry, *multi);
        } else {
          makeRow(*activeSection, entry, makeControl(entry));
        }
        ++visibleEntries;
      }
    }

    if (visibleEntries == 0) {
      auto emptyState = std::make_unique<Flex>();
      emptyState->setDirection(FlexDirection::Vertical);
      emptyState->setAlign(FlexAlign::Center);
      emptyState->setJustify(FlexJustify::Center);
      emptyState->setGap(Style::spaceXs * scale);
      emptyState->setPadding((Style::spaceLg + Style::spaceMd) * scale);
      emptyState->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.24f));
      emptyState->setBorder(colorSpecFromRole(ColorRole::Outline, 0.28f), Style::borderWidth);
      emptyState->setRadius(Style::scaledRadiusMd(scale));
      emptyState->addChild(makeLabel(i18n::tr("settings.window.no-results"), Style::fontSizeBody * scale,
                                     colorSpecFromRole(ColorRole::OnSurface), true));
      emptyState->addChild(makeLabel(i18n::tr("settings.window.no-results-hint"), Style::fontSizeCaption * scale,
                                     colorSpecFromRole(ColorRole::OnSurfaceVariant), false));

      auto emptyRow = std::make_unique<Flex>();
      emptyRow->setDirection(FlexDirection::Horizontal);
      emptyRow->setAlign(FlexAlign::Center);
      emptyRow->setJustify(FlexJustify::Center);
      emptyRow->setFillWidth(true);
      emptyRow->addChild(std::move(emptyState));
      content.addChild(std::move(emptyRow));
    }

    return visibleEntries;
  }

  void buildSessionActionEntryDetailContent(Flex& parent, SettingsContentContext& ctx, SessionPanelActionConfig& row,
                                            const std::function<void()>& persist) {
    buildSessionActionEntryDetailContentImpl(parent, ctx, row, persist);
  }

  void buildIdleBehaviorEntryDetailContent(Flex& parent, SettingsContentContext& ctx, IdleBehaviorConfig& row,
                                           const std::function<void()>& persist) {
    buildIdleBehaviorEntryDetailContentImpl(parent, ctx, row, persist, ctx.closeHostedEditor);
  }

} // namespace settings

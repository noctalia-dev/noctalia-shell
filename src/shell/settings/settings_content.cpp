#include "shell/settings/settings_content.h"

#include "i18n/i18n.h"
#include "render/core/color.h"
#include "shell/settings/bar_widget_editor.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/checkbox.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/search_picker.h"
#include "ui/controls/segmented.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/slider.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <format>
#include <limits>
#include <locale>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
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
      label->setStableBaseline(true);
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

    std::vector<SearchPickerOption> searchPickerOptions(const std::vector<SelectOption>& options) {
      std::vector<SearchPickerOption> out;
      out.reserve(options.size());
      for (const auto& opt : options) {
        out.push_back(SearchPickerOption{.value = opt.value,
                                         .label = opt.label,
                                         .description = opt.description,
                                         .category = opt.category,
                                         .enabled = true});
      }
      return out;
    }

    bool isBlankInput(std::string_view text) { return StringUtils::trim(text).empty(); }

    const std::string& localeDecimalSeparator() {
      static const std::string separator = [] {
        try {
          const std::locale userLocale("");
          const char decimalPoint = std::use_facet<std::numpunct<char>>(userLocale).decimal_point();
          return std::string(1, decimalPoint);
        } catch (...) {
          return std::string(".");
        }
      }();
      return separator;
    }

    std::string formatSliderValue(float value, bool integerValue, char decimalSeparator = '\0') {
      if (integerValue) {
        return std::format("{}", static_cast<int>(std::lround(value)));
      }
      std::string formatted = std::format("{:.2f}", value);
      const std::string decimalSep =
          decimalSeparator == '\0' ? localeDecimalSeparator() : std::string(1, decimalSeparator);
      if (decimalSep != ".") {
        std::size_t dotPos = formatted.find('.');
        if (dotPos != std::string::npos) {
          formatted.replace(dotPos, 1, decimalSep);
        }
      }
      return formatted;
    }

    template <typename T> std::optional<T> parseDecimalInput(std::string_view text) {
      const std::string trimmed = StringUtils::trim(text);
      if (trimmed.empty()) {
        return std::nullopt;
      }

      std::string normalized = trimmed;
      std::replace(normalized.begin(), normalized.end(), ',', '.');

      T value{};
      const char* begin = normalized.data();
      const char* end = begin + normalized.size();
      const auto [ptr, ec] = std::from_chars(begin, end, value, std::chars_format::general);
      if (ec != std::errc{} || ptr != end || !std::isfinite(value)) {
        return std::nullopt;
      }
      if constexpr (std::is_same_v<T, float>) {
        if (value > std::numeric_limits<float>::max() || value < -std::numeric_limits<float>::max()) {
          return std::nullopt;
        }
      }
      return value;
    }

    std::optional<float> parseFloatInput(std::string_view text) {
      const auto parsed = parseDecimalInput<double>(text);
      if (!parsed.has_value()) {
        return std::nullopt;
      }
      return static_cast<float>(*parsed);
    }

    std::optional<double> parseDoubleInput(std::string_view text) { return parseDecimalInput<double>(text); }

    bool isMonitorOverrideSettingPath(const std::vector<std::string>& path) {
      return path.size() >= 5 && path[0] == "bar" && path[2] == "monitor";
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
      if (key == "capsule_padding") {
        return override->widgetCapsulePadding.has_value();
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

  } // namespace

  std::size_t addSettingsContentSections(Flex& content, const std::vector<SettingEntry>& registry,
                                         SettingsContentContext ctx) {
    const Config& cfg = ctx.config;
    const float scale = ctx.scale;

    const auto sectionLabel = [](std::string_view section) {
      return i18n::tr("settings.navigation.sections." + std::string(section));
    };

    const auto groupLabel = [](std::string_view group) {
      return i18n::tr("settings.navigation.groups." + std::string(group));
    };

    const auto makeSection = [&](std::string_view title, std::string_view sectionKey) -> Flex* {
      auto section = std::make_unique<Flex>();
      section->setDirection(FlexDirection::Vertical);
      section->setAlign(FlexAlign::Stretch);
      section->setGap(Style::spaceSm * scale);
      section->setPadding(Style::spaceLg * scale);
      section->setCardStyle(scale);
      section->setFill(colorSpecFromRole(ColorRole::Surface));

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
            makeLabel(title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant), true));
        section.addChild(std::move(groupHeader));
      } else {
        section.addChild(
            makeLabel(title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurfaceVariant), true));
      }
    };

    const auto makeResetButton = [&](const std::vector<std::string>& path) {
      auto reset = std::make_unique<Button>();
      reset->setText(i18n::tr("settings.actions.reset"));
      reset->setVariant(ButtonVariant::Ghost);
      reset->setFontSize(Style::fontSizeCaption * scale);
      reset->setMinHeight(Style::controlHeightSm * scale);
      reset->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      reset->setRadius(Style::radiusMd * scale);
      reset->setOnClick([clearOverride = ctx.clearOverride, path]() { clearOverride(path); });
      return reset;
    };

    const auto makeRow = [&](Flex& section, const SettingEntry& entry, std::unique_ptr<Node> control) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasOverride(entry.path));
      const bool monitorSetting = isMonitorOverrideSettingPath(entry.path);
      const bool monitorExplicit = monitorOverrideHasExplicitValue(cfg, entry.path);
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
      titleRow->addChild(
          makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true));

      const auto makeBadge = [&](std::string_view label, const ColorSpec& fill, const ColorSpec& color) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::radiusSm * scale);
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
        detail->setMaxWidth(360.0f * scale);
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

    const auto makeToggle = [&](bool checked, std::vector<std::string> path) {
      auto toggle = std::make_unique<Toggle>();
      toggle->setScale(scale);
      toggle->setChecked(checked);
      toggle->setOnChange([setOverride = ctx.setOverride, path](bool value) { setOverride(path, value); });
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

    const auto makeSlider = [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
                                bool integerValue = false) {
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
      slider->setOnDragEnd([setOverride = ctx.setOverride, path, sliderPtr, integerValue]() {
        if (integerValue) {
          setOverride(path, static_cast<std::int64_t>(std::lround(sliderPtr->value())));
        } else {
          setOverride(path, static_cast<double>(sliderPtr->value()));
        }
      });

      valueInput->setOnChange([valueInputPtr](const std::string& /*text*/) { valueInputPtr->setInvalid(false); });
      valueInput->setOnSubmit([setOverride = ctx.setOverride, path, sliderPtr, valueInputPtr, minValue, maxValue,
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
          const std::string trimmed = StringUtils::trim(text);
          const char preferredSeparator = trimmed.find(',') != std::string::npos ? ',' : '.';
          valueInputPtr->setValue(formatSliderValue(sliderPtr->value(), false, preferredSeparator));
        }
        if (integerValue) {
          setOverride(path, static_cast<std::int64_t>(std::lround(v)));
        } else {
          setOverride(path, static_cast<double>(v));
        }
      });

      // Slider first, numeric value field on the right (reset from makeRow stays left of this cluster).
      wrap->addChild(std::move(slider));
      wrap->addChild(std::move(valueInput));
      return wrap;
    };

    const auto makeText = [&](const std::string& value, const std::string& placeholder, std::vector<std::string> path) {
      auto input = std::make_unique<Input>();
      input->setValue(value);
      input->setPlaceholder(placeholder.empty() ? i18n::tr("settings.controls.list.add-entry-placeholder")
                                                : placeholder);
      input->setFontSize(Style::fontSizeBody * scale);
      input->setControlHeight(Style::controlHeight * scale);
      input->setHorizontalPadding(Style::spaceSm * scale);
      input->setSize(190.0f * scale, Style::controlHeight * scale);
      input->setOnSubmit([setOverride = ctx.setOverride, path](const std::string& v) { setOverride(path, v); });
      return input;
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

    const auto makeColor = [&](const ColorSetting& setting, std::vector<std::string> path) {
      auto wrap = std::make_unique<Flex>();
      wrap->setDirection(FlexDirection::Horizontal);
      wrap->setAlign(FlexAlign::Center);
      wrap->setGap(Style::spaceSm * scale);

      const float swatchSize = Style::controlHeight * scale;
      auto swatch = std::make_unique<Box>();
      swatch->setSize(swatchSize, swatchSize);
      swatch->setRadius(Style::radiusSm * scale);
      swatch->setBorder(colorSpecFromRole(ColorRole::Outline), 1.0f);
      Color initialColor;
      const bool hasColor = !setting.unset && tryParseHexColor(setting.hex, initialColor);
      if (hasColor) {
        swatch->setFill(initialColor);
      } else {
        swatch->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
      }

      auto button = std::make_unique<Button>();
      button->setVariant(ButtonVariant::Outline);
      button->setText(setting.unset ? i18n::tr("settings.options.theme-role.default") : setting.hex);
      button->setFontSize(Style::fontSizeBody * scale);
      button->setMinHeight(Style::controlHeight * scale);
      button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      button->setRadius(Style::radiusMd * scale);
      const std::optional<Color> initialOpt = hasColor ? std::optional<Color>{initialColor} : std::nullopt;
      const std::string title = i18n::tr("settings.dialogs.color-picker.title");
      button->setOnClick([setOverride = ctx.setOverride, path, initialOpt, title]() {
        ColorPickerDialogOptions options;
        options.title = title;
        if (initialOpt.has_value()) {
          options.initialColor = *initialOpt;
        } else if (const auto last = ColorPickerDialog::lastResult()) {
          options.initialColor = *last;
        }
        (void)ColorPickerDialog::open(std::move(options), [setOverride, path](std::optional<Color> result) {
          if (!result.has_value()) {
            return;
          }
          Color rgb = *result;
          rgb.a = 1.0f;
          setOverride(path, formatRgbHex(rgb));
        });
      });

      wrap->addChild(std::move(swatch));
      wrap->addChild(std::move(button));
      return wrap;
    };

    const auto makeColorRolePicker = [&](const ColorRolePickerSetting& setting,
                                         std::vector<std::string> path) -> std::unique_ptr<Node> {
      std::vector<SelectOption> opts;
      opts.reserve(setting.roles.size() + (setting.allowNone ? 1 : 0));
      std::vector<ColorSpec> indicators;
      indicators.reserve(setting.roles.size() + (setting.allowNone ? 1 : 0));

      if (setting.allowNone) {
        opts.push_back(SelectOption{"", i18n::tr("settings.options.theme-role.default")});
        indicators.push_back(clearColorSpec());
      }
      for (const auto role : setting.roles) {
        opts.push_back(SelectOption{std::string(colorRoleToken(role)), std::string(colorRoleToken(role))});
        indicators.push_back(colorSpecFromRole(role));
      }

      SelectSetting selectSetting{std::move(opts), setting.selectedValue, setting.allowNone};
      auto select = makeSelect(selectSetting, std::move(path));

      if (auto* sel = dynamic_cast<Select*>(select.get())) {
        sel->setOptionIndicators(std::move(indicators));
      }

      return select;
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
      button->setRadius(Style::radiusMd * scale);
      button->setOnClick([&openPath = ctx.openSearchPickerPath, requestContentRebuild = ctx.requestContentRebuild,
                          path = entry.path]() {
        openPath = pathKey(path);
        requestContentRebuild();
      });
      return button;
    };

    const auto makeSearchPickerBlock = [&](Flex& section, const SettingEntry& entry,
                                           const SearchPickerSetting& setting) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasOverride(entry.path));
      const std::string pickerPath = pathKey(entry.path);

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);

      const auto makeBadge = [&](std::string_view label, const ColorSpec& fill, const ColorSpec& color) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::radiusSm * scale);
        badge->setFill(fill);
        badge->addChild(makeLabel(label, Style::fontSizeCaption * scale, color, true));
        return badge;
      };

      auto headerRow = std::make_unique<Flex>();
      headerRow->setDirection(FlexDirection::Horizontal);
      headerRow->setAlign(FlexAlign::Center);
      headerRow->setJustify(FlexJustify::SpaceBetween);
      headerRow->setGap(Style::spaceXs * scale);
      headerRow->setPadding(2.0f * scale, 0.0f);
      headerRow->setMinHeight(Style::controlHeight * scale);

      auto copy = std::make_unique<Flex>();
      copy->setDirection(FlexDirection::Vertical);
      copy->setAlign(FlexAlign::Start);
      copy->setGap(Style::spaceXs * scale);
      copy->setFlexGrow(1.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->addChild(
          makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true));

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
        detail->setMaxWidth(360.0f * scale);
        copy->addChild(std::move(detail));
      }

      headerRow->addChild(std::move(copy));

      auto actions = std::make_unique<Flex>();
      actions->setDirection(FlexDirection::Horizontal);
      actions->setAlign(FlexAlign::Center);
      actions->setGap(Style::spaceSm * scale);
      if (overridden) {
        actions->addChild(makeResetButton(entry.path));
      }

      auto closeBtn = std::make_unique<Button>();
      closeBtn->setVariant(ButtonVariant::Ghost);
      closeBtn->setGlyph("close");
      closeBtn->setGlyphSize(Style::fontSizeCaption * scale);
      closeBtn->setMinWidth(Style::controlHeightSm * scale);
      closeBtn->setMinHeight(Style::controlHeightSm * scale);
      closeBtn->setPadding(Style::spaceXs * scale);
      closeBtn->setRadius(Style::radiusSm * scale);
      closeBtn->setOnClick([&openPath = ctx.openSearchPickerPath, requestContentRebuild = ctx.requestContentRebuild]() {
        openPath.clear();
        requestContentRebuild();
      });
      actions->addChild(std::move(closeBtn));
      headerRow->addChild(std::move(actions));
      block->addChild(std::move(headerRow));

      auto picker = std::make_unique<SearchPicker>();
      if (!setting.placeholder.empty()) {
        picker->setPlaceholder(setting.placeholder);
      }
      if (!setting.emptyText.empty()) {
        picker->setEmptyText(setting.emptyText);
      }
      picker->setOptions(searchPickerOptions(setting.options));
      picker->setSelectedValue(setting.selectedValue);
      picker->setSize(0.0f, setting.preferredHeight * scale);
      picker->setFillWidth(true);
      auto* pickerPtr = picker.get();
      picker->setOnActivated([&openPath = ctx.openSearchPickerPath, requestContentRebuild = ctx.requestContentRebuild,
                              setOverride = ctx.setOverride, path = entry.path,
                              selectedValue = setting.selectedValue](const SearchPickerOption& option) {
        if (option.value.empty()) {
          return;
        }
        openPath.clear();
        if (option.value == selectedValue) {
          requestContentRebuild();
          return;
        }
        setOverride(path, option.value);
      });
      picker->setOnCancel([&openPath = ctx.openSearchPickerPath, requestContentRebuild = ctx.requestContentRebuild]() {
        openPath.clear();
        requestContentRebuild();
      });
      block->addChild(std::move(picker));

      section.addChild(std::move(block));
      if (ctx.openSearchPickerPath == pickerPath && ctx.focusArea) {
        ctx.focusArea(pickerPtr->filterInputArea());
      }
    };

    const auto makeMultiSelectBlock = [&](Flex& section, const SettingEntry& entry, const MultiSelectSetting& setting) {
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->addChild(
          makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true));
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::radiusSm * scale);
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
      const bool overridden = (ctx.configService != nullptr && ctx.configService->hasOverride(entry.path));

      auto block = std::make_unique<Flex>();
      block->setDirection(FlexDirection::Vertical);
      block->setAlign(FlexAlign::Stretch);
      block->setGap(Style::spaceXs * scale);
      block->setPadding(2.0f * scale, 0.0f);

      auto titleRow = std::make_unique<Flex>();
      titleRow->setDirection(FlexDirection::Horizontal);
      titleRow->setAlign(FlexAlign::Center);
      titleRow->setGap(Style::spaceSm * scale);
      titleRow->addChild(
          makeLabel(entry.title, Style::fontSizeBody * scale, colorSpecFromRole(ColorRole::OnSurface), true));
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::radiusSm * scale);
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

      const auto resolveItemLabel = [&list](const std::string& value) -> std::string {
        for (const auto& opt : list.suggestedOptions) {
          if (opt.value == value) {
            return opt.label;
          }
        }
        return value;
      };

      const float labelCellWidth = 200.0f * scale;
      for (std::size_t i = 0; i < list.items.size(); ++i) {
        auto itemRow = std::make_unique<Flex>();
        itemRow->setDirection(FlexDirection::Horizontal);
        itemRow->setAlign(FlexAlign::Center);
        itemRow->setGap(Style::spaceXs * scale);
        itemRow->setMinHeight(Style::controlHeightSm * scale);

        auto labelCell = std::make_unique<Flex>();
        labelCell->setDirection(FlexDirection::Horizontal);
        labelCell->setAlign(FlexAlign::Center);
        labelCell->setMinWidth(labelCellWidth);
        labelCell->addChild(makeLabel(resolveItemLabel(list.items[i]), Style::fontSizeCaption * scale,
                                      colorSpecFromRole(ColorRole::OnSurface), false));
        itemRow->addChild(std::move(labelCell));

        auto removeBtn = std::make_unique<Button>();
        removeBtn->setGlyph("close");
        removeBtn->setVariant(ButtonVariant::Ghost);
        removeBtn->setGlyphSize(Style::fontSizeCaption * scale);
        removeBtn->setMinWidth(Style::controlHeightSm * scale);
        removeBtn->setMinHeight(Style::controlHeightSm * scale);
        removeBtn->setPadding(Style::spaceXs * scale);
        removeBtn->setRadius(Style::radiusSm * scale);
        {
          auto items = list.items;
          auto path = entry.path;
          removeBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
            items.erase(items.begin() + static_cast<std::ptrdiff_t>(i));
            setOverride(path, items);
          });
        }
        itemRow->addChild(std::move(removeBtn));

        if (i > 0) {
          auto upBtn = std::make_unique<Button>();
          upBtn->setGlyph("chevron-up");
          upBtn->setVariant(ButtonVariant::Ghost);
          upBtn->setGlyphSize(Style::fontSizeCaption * scale);
          upBtn->setMinWidth(Style::controlHeightSm * scale);
          upBtn->setMinHeight(Style::controlHeightSm * scale);
          upBtn->setPadding(Style::spaceXs * scale);
          upBtn->setRadius(Style::radiusSm * scale);
          auto items = list.items;
          auto path = entry.path;
          upBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i - 1]);
            setOverride(path, items);
          });
          itemRow->addChild(std::move(upBtn));
        }
        if (i + 1 < list.items.size()) {
          auto downBtn = std::make_unique<Button>();
          downBtn->setGlyph("chevron-down");
          downBtn->setVariant(ButtonVariant::Ghost);
          downBtn->setGlyphSize(Style::fontSizeCaption * scale);
          downBtn->setMinWidth(Style::controlHeightSm * scale);
          downBtn->setMinHeight(Style::controlHeightSm * scale);
          downBtn->setPadding(Style::spaceXs * scale);
          downBtn->setRadius(Style::radiusSm * scale);
          auto items = list.items;
          auto path = entry.path;
          downBtn->setOnClick([setOverride = ctx.setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i + 1]);
            setOverride(path, items);
          });
          itemRow->addChild(std::move(downBtn));
        }

        block->addChild(std::move(itemRow));
      }

      auto addRow = std::make_unique<Flex>();
      addRow->setDirection(FlexDirection::Horizontal);
      addRow->setAlign(FlexAlign::Center);
      addRow->setGap(Style::spaceSm * scale);

      const bool useSelectAdder = !list.suggestedOptions.empty();
      std::vector<SelectOption> remaining;
      if (useSelectAdder) {
        remaining.reserve(list.suggestedOptions.size());
        for (const auto& opt : list.suggestedOptions) {
          if (std::find(list.items.begin(), list.items.end(), opt.value) == list.items.end()) {
            remaining.push_back(opt);
          }
        }
      }

      if (useSelectAdder) {
        if (remaining.empty()) {
          // Every suggested value is already in the list — nothing to add.
          section.addChild(std::move(block));
          return;
        }

        std::vector<std::string> remainingLabels;
        remainingLabels.reserve(remaining.size());
        for (const auto& opt : remaining) {
          remainingLabels.push_back(opt.label);
        }

        auto select = std::make_unique<Select>();
        select->setOptions(remainingLabels);
        select->setPlaceholder(i18n::tr("settings.controls.list.add-entry-placeholder"));
        select->setFontSize(Style::fontSizeCaption * scale);
        select->setControlHeight(Style::controlHeightSm * scale);
        select->setGlyphSize(Style::fontSizeCaption * scale);
        select->setSize(labelCellWidth, Style::controlHeightSm * scale);
        auto* selectPtr = select.get();

        auto addBtn = std::make_unique<Button>();
        addBtn->setGlyph("add");
        addBtn->setVariant(ButtonVariant::Ghost);
        addBtn->setGlyphSize(Style::fontSizeCaption * scale);
        addBtn->setMinWidth(Style::controlHeightSm * scale);
        addBtn->setMinHeight(Style::controlHeightSm * scale);
        addBtn->setPadding(Style::spaceXs * scale);
        addBtn->setRadius(Style::radiusSm * scale);

        auto items = list.items;
        auto path = entry.path;
        addBtn->setOnClick([setOverride = ctx.setOverride, selectPtr, remaining, items, path]() mutable {
          const std::size_t index = selectPtr->selectedIndex();
          if (index >= remaining.size()) {
            return;
          }
          items.push_back(remaining[index].value);
          setOverride(path, items);
        });

        addRow->addChild(std::move(select));
        addRow->addChild(std::move(addBtn));
      } else {
        auto addInput = std::make_unique<Input>();
        addInput->setPlaceholder(i18n::tr("settings.controls.list.add-entry-placeholder"));
        addInput->setFontSize(Style::fontSizeBody * scale);
        addInput->setControlHeight(Style::controlHeight * scale);
        addInput->setHorizontalPadding(Style::spaceSm * scale);
        addInput->setSize(190.0f * scale, Style::controlHeight * scale);
        auto* addInputPtr = addInput.get();

        auto addBtn = std::make_unique<Button>();
        addBtn->setGlyph("add");
        addBtn->setVariant(ButtonVariant::Ghost);
        addBtn->setGlyphSize(Style::fontSizeBody * scale);
        addBtn->setMinWidth(Style::controlHeight * scale);
        addBtn->setMinHeight(Style::controlHeight * scale);
        addBtn->setPadding(Style::spaceSm * scale);
        addBtn->setRadius(Style::radiusMd * scale);
        auto items = list.items;
        auto path = entry.path;
        addBtn->setOnClick([setOverride = ctx.setOverride, addInputPtr, items, path]() mutable {
          const auto& text = addInputPtr->value();
          if (!text.empty()) {
            items.push_back(text);
            setOverride(path, items);
          }
        });

        addInput->setOnSubmit([setOverride = ctx.setOverride, items, path](const std::string& text) mutable {
          if (!text.empty()) {
            items.push_back(text);
            setOverride(path, items);
          }
        });

        addRow->addChild(std::move(addInput));
        addRow->addChild(std::move(addBtn));
      }

      block->addChild(std::move(addRow));

      section.addChild(std::move(block));
    };

    const auto makeControl = [&](const SettingEntry& entry) -> std::unique_ptr<Node> {
      return std::visit(
          [&](const auto& control) -> std::unique_ptr<Node> {
            using T = std::decay_t<decltype(control)>;
            if constexpr (std::is_same_v<T, ToggleSetting>) {
              return makeToggle(control.checked, entry.path);
            } else if constexpr (std::is_same_v<T, SelectSetting>) {
              return makeSelect(control, entry.path);
            } else if constexpr (std::is_same_v<T, SliderSetting>) {
              return makeSlider(control.value, control.minValue, control.maxValue, control.step, entry.path,
                                control.integerValue);
            } else if constexpr (std::is_same_v<T, TextSetting>) {
              return makeText(control.value, control.placeholder, entry.path);
            } else if constexpr (std::is_same_v<T, OptionalNumberSetting>) {
              return makeOptionalNumber(control, entry.path);
            } else if constexpr (std::is_same_v<T, ColorSetting>) {
              return makeColor(control, entry.path);
            } else if constexpr (std::is_same_v<T, SearchPickerSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, MultiSelectSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, ListSetting>) {
              return nullptr;
            } else if constexpr (std::is_same_v<T, ButtonSetting>) {
              auto button = std::make_unique<Button>();
              button->setVariant(ButtonVariant::Outline);
              button->setText(control.label);
              button->setFontSize(Style::fontSizeBody * scale);
              button->setMinHeight(Style::controlHeight * scale);
              button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
              button->setRadius(Style::radiusMd * scale);
              button->setOnClick(control.action);
              return button;
            } else if constexpr (std::is_same_v<T, ColorRolePickerSetting>) {
              return makeColorRolePicker(control, entry.path);
            }
          },
          entry.control);
    };

    std::string activeSectionKey;
    std::string activeGroupKey;
    Flex* activeSection = nullptr;
    std::size_t visibleEntries = 0;
    const std::string normalizedSearchQuery = normalizedSettingQuery(ctx.searchQuery);

    BarWidgetEditorContext barWidgetEditorCtx{
        .config = cfg,
        .configService = ctx.configService,
        .scale = scale,
        .showAdvanced = ctx.showAdvanced,
        .showOverriddenOnly = ctx.showOverriddenOnly,
        .openWidgetPickerPath = ctx.openWidgetPickerPath,
        .editingWidgetName = ctx.editingWidgetName,
        .pendingDeleteWidgetName = ctx.pendingDeleteWidgetName,
        .pendingDeleteWidgetSettingPath = ctx.pendingDeleteWidgetSettingPath,
        .renamingWidgetName = ctx.renamingWidgetName,
        .creatingWidgetType = ctx.creatingWidgetType,
        .requestRebuild = ctx.requestRebuild,
        .resetContentScroll = ctx.resetContentScroll,
        .focusArea = ctx.focusArea,
        .setOverride = ctx.setOverride,
        .setOverrides = ctx.setOverrides,
        .clearOverride = ctx.clearOverride,
        .renameWidgetInstance = ctx.renameWidgetInstance,
        .makeResetButton = makeResetButton,
        .makeRow = makeRow,
        .makeToggle = [&](bool checked, std::vector<std::string> path) -> std::unique_ptr<Node> {
          return makeToggle(checked, std::move(path));
        },
        .makeSelect = [&](const SelectSetting& setting, std::vector<std::string> path) -> std::unique_ptr<Node> {
          return makeSelect(setting, std::move(path));
        },
        .makeSlider = [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
                          bool integerValue) -> std::unique_ptr<Node> {
          return makeSlider(value, minValue, maxValue, step, std::move(path), integerValue);
        },
        .makeText = [&](const std::string& value, const std::string& placeholder, std::vector<std::string> path)
            -> std::unique_ptr<Node> { return makeText(value, placeholder, std::move(path)); },
        .makeColorRolePicker = [&](const ColorRolePickerSetting& setting, std::vector<std::string> path)
            -> std::unique_ptr<Node> { return makeColorRolePicker(setting, std::move(path)); },
        .makeListBlock = [&](Flex& section, const SettingEntry& entry,
                             const ListSetting& list) { makeListBlock(section, entry, list); },
    };

    for (const auto& entry : registry) {
      if (ctx.searchQuery.empty() && !ctx.selectedSection.empty() && entry.section != ctx.selectedSection) {
        continue;
      }
      if (!ctx.showAdvanced && entry.advanced) {
        continue;
      }
      if (ctx.showOverriddenOnly && ctx.configService != nullptr && !ctx.configService->hasOverride(entry.path)) {
        continue;
      }
      if (!matchesNormalizedSettingQuery(entry, normalizedSearchQuery)) {
        continue;
      }

      if (entry.section != activeSectionKey) {
        activeSectionKey = entry.section;
        activeGroupKey.clear();
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
      }
      if (activeSection != nullptr) {
        if (entry.group != activeGroupKey) {
          const bool isFirstGroup = activeGroupKey.empty();
          activeGroupKey = entry.group;
          addGroupLabel(*activeSection, groupLabel(entry.group), isFirstGroup);
        }
        if (const auto* list = std::get_if<ListSetting>(&entry.control)) {
          if (isFirstBarWidgetListPath(entry.path)) {
            addBarWidgetLaneEditor(*activeSection, entry, barWidgetEditorCtx);
          } else if (!isBarWidgetListPath(entry.path)) {
            makeListBlock(*activeSection, entry, *list);
          }
        } else if (const auto* picker = std::get_if<SearchPickerSetting>(&entry.control)) {
          if (ctx.openSearchPickerPath == pathKey(entry.path)) {
            makeSearchPickerBlock(*activeSection, entry, *picker);
          } else {
            makeRow(*activeSection, entry, makeSearchPickerButton(entry, *picker));
          }
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
      emptyState->setRadius(Style::radiusMd * scale);
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

} // namespace settings

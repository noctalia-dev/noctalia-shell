#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "shell/desktop/desktop_widget_settings_registry.h"
#include "shell/desktop/desktop_widgets_editor.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/slider.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"

#include <linux/input-event-codes.h>

namespace {

  constexpr float kInspectorWidth = 340.0f;
  constexpr float kSettingRowHeight = 34.0f;
  constexpr float kLabelWidth = 100.0f;

  using Settings = std::unordered_map<std::string, WidgetSettingValue>;

  std::string getStr(const Settings& s, const std::string& key, const std::string& fallback = {}) {
    const auto it = s.find(key);
    if (it == s.end()) {
      return fallback;
    }
    if (const auto* v = std::get_if<std::string>(&it->second)) {
      return *v;
    }
    return fallback;
  }

  float getFloat(const Settings& s, const std::string& key, float fallback) {
    const auto it = s.find(key);
    if (it == s.end()) {
      return fallback;
    }
    if (const auto* v = std::get_if<double>(&it->second)) {
      return static_cast<float>(*v);
    }
    if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
      return static_cast<float>(*v);
    }
    return fallback;
  }

  bool getBool(const Settings& s, const std::string& key, bool fallback) {
    const auto it = s.find(key);
    if (it == s.end()) {
      return fallback;
    }
    if (const auto* v = std::get_if<bool>(&it->second)) {
      return *v;
    }
    return fallback;
  }

  ColorSpec getColorSpec(const Settings& s, const std::string& key, const ColorSpec& fallback) {
    const auto it = s.find(key);
    if (it == s.end()) {
      return fallback;
    }
    if (const auto* v = std::get_if<std::string>(&it->second)) {
      return colorSpecFromConfigString(*v);
    }
    return fallback;
  }

  std::unique_ptr<Flex> makeRow(std::string_view labelText, std::unique_ptr<Node> control) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setJustify(FlexJustify::SpaceBetween);
    row->setGap(Style::spaceSm);
    row->setMinHeight(kSettingRowHeight);
    row->setFillWidth(true);

    auto labelBox = std::make_unique<Flex>();
    labelBox->setDirection(FlexDirection::Horizontal);
    labelBox->setAlign(FlexAlign::Center);
    labelBox->setMinWidth(kLabelWidth);
    auto label = std::make_unique<Label>();
    label->setText(std::string(labelText));
    label->setFontSize(Style::fontSizeCaption);
    label->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    labelBox->addChild(std::move(label));
    row->addChild(std::move(labelBox));

    row->addChild(std::move(control));
    return row;
  }

  std::unique_ptr<Flex> makeToggleRow(std::string_view labelText, const std::string& key, bool fallback,
                                      const Settings& s, DesktopWidgetsEditor* editor) {
    auto toggle = std::make_unique<Toggle>();
    toggle->setChecked(getBool(s, key, fallback));
    toggle->setOnChange([editor, key](bool checked) { editor->applySettingChange(key, checked); });
    return makeRow(labelText, std::move(toggle));
  }

  std::unique_ptr<Flex> makeSliderRow(std::string_view labelText, const std::string& key, float fallback, float minVal,
                                      float maxVal, float step, const Settings& s, DesktopWidgetsEditor* editor) {
    auto slider = std::make_unique<Slider>();
    slider->setRange(minVal, maxVal);
    slider->setStep(step);
    slider->setValue(getFloat(s, key, fallback));
    slider->setFlexGrow(1.0f);
    slider->setOnValueChanged([editor, key](float val) { editor->applySettingChange(key, static_cast<double>(val)); });
    return makeRow(labelText, std::move(slider));
  }

  std::unique_ptr<Flex> makeColorRoleSelect(std::string_view labelText, const std::string& key,
                                            const ColorSpec& fallback, const Settings& s,
                                            DesktopWidgetsEditor* editor) {
    auto currentSpec = getColorSpec(s, key, fallback);

    std::vector<std::string> options;
    std::vector<ColorSpec> indicators;
    options.reserve(kColorRoleTokens.size() + 1);
    indicators.reserve(kColorRoleTokens.size() + 1);

    std::size_t selectedIndex = kColorRoleTokens.size(); // default to Custom
    for (std::size_t i = 0; i < kColorRoleTokens.size(); ++i) {
      options.emplace_back(kColorRoleTokens[i].token);
      indicators.push_back(colorSpecFromRole(kColorRoleTokens[i].role));
      if (currentSpec.role.has_value() && *currentSpec.role == kColorRoleTokens[i].role) {
        selectedIndex = i;
      }
    }

    auto customLabel = currentSpec.role.has_value() ? i18n::tr("desktop-widgets.editor.settings.custom-color")
                                                    : formatRgbHex(resolveColorSpec(currentSpec));
    options.push_back(customLabel);
    indicators.push_back(currentSpec.role.has_value() ? clearColorSpec()
                                                      : fixedColorSpec(resolveColorSpec(currentSpec)));

    auto select = std::make_unique<Select>();
    select->setOptions(options);
    select->setOptionIndicators(std::move(indicators));
    select->setSelectedIndex(selectedIndex);
    select->setControlHeight(Style::controlHeightSm);
    select->setFlexGrow(1.0f);
    select->setOnSelectionChanged([editor, key, currentSpec](std::size_t index, std::string_view) {
      if (index < kColorRoleTokens.size()) {
        editor->applySettingChange(key, std::string(kColorRoleTokens[index].token));
      } else {
        auto currentColor = resolveColorSpec(currentSpec);
        editor->openColorPicker(key, currentColor);
      }
    });
    return makeRow(labelText, std::move(select));
  }

  std::unique_ptr<Flex> makeInputRow(std::string_view labelText, const std::string& key, const std::string& value,
                                     const std::string& placeholder, DesktopWidgetsEditor* editor) {
    auto input = std::make_unique<Input>();
    input->setValue(value);
    input->setPlaceholder(placeholder);
    input->setControlHeight(Style::controlHeightSm);
    input->setFlexGrow(1.0f);
    input->setOnChange([editor, key](const std::string& val) { editor->applySettingChange(key, val); });
    return makeRow(labelText, std::move(input));
  }

  std::unique_ptr<Flex> makeFilePickerRow(std::string_view labelText, const std::string& key,
                                          DesktopWidgetsEditor* editor) {
    auto changeBtn = std::make_unique<Button>();
    changeBtn->setText(i18n::tr("desktop-widgets.editor.settings.change-image"));
    changeBtn->setVariant(ButtonVariant::Outline);
    changeBtn->setFlexGrow(1.0f);
    changeBtn->setOnClick([editor, key]() {
      FileDialogOptions options;
      options.mode = FileDialogMode::Open;
      options.title = i18n::tr("desktop-widgets.editor.dialogs.select-sticker-image");
      options.extensions = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"};
      (void)FileDialog::open(std::move(options), [editor, key](std::optional<std::filesystem::path> result) {
        if (result) {
          editor->applySettingChange(key, result->string());
        }
      });
    });
    return makeRow(labelText, std::move(changeBtn));
  }

  std::unique_ptr<Flex> makeSelectRow(std::string_view labelText, const std::string& key,
                                      const std::vector<settings::WidgetSettingSelectOption>& options,
                                      const std::string& currentValue, DesktopWidgetsEditor* editor) {
    std::vector<std::string> labels;
    std::vector<std::string> values;
    labels.reserve(options.size());
    values.reserve(options.size());
    std::size_t selectedIndex = 0;

    for (std::size_t i = 0; i < options.size(); ++i) {
      labels.push_back(i18n::tr(options[i].labelKey));
      values.emplace_back(options[i].value);
      if (options[i].value == currentValue) {
        selectedIndex = i;
      }
    }

    auto select = std::make_unique<Select>();
    select->setOptions(labels);
    select->setSelectedIndex(selectedIndex);
    select->setControlHeight(Style::controlHeightSm);
    select->setFlexGrow(1.0f);
    select->setOnSelectionChanged([editor, key, values = std::move(values)](std::size_t index, std::string_view) {
      if (index < values.size()) {
        editor->applySettingChange(key, values[index]);
      }
    });
    return makeRow(labelText, std::move(select));
  }

  std::unique_ptr<Flex> makeSegmentedRow(std::string_view labelText, const std::string& key,
                                         const std::vector<settings::WidgetSettingSelectOption>& options,
                                         const std::string& currentValue, DesktopWidgetsEditor* editor) {
    std::vector<std::string> values;
    values.reserve(options.size());
    std::size_t selectedIndex = 0;

    auto segmented = std::make_unique<Segmented>();
    for (std::size_t i = 0; i < options.size(); ++i) {
      segmented->addOption(i18n::tr(options[i].labelKey));
      values.emplace_back(options[i].value);
      if (options[i].value == currentValue) {
        selectedIndex = i;
      }
    }
    segmented->setSelectedIndex(selectedIndex);
    segmented->setFlexGrow(1.0f);
    segmented->setOnChange([editor, key, values = std::move(values)](std::size_t index) {
      if (index < values.size()) {
        editor->applySettingChange(key, values[index]);
      }
    });
    return makeRow(labelText, std::move(segmented));
  }

  void addSpecSettings(Flex& content, const std::vector<settings::WidgetSettingSpec>& specs, const Settings& s,
                       DesktopWidgetsEditor* editor) {
    for (const auto& spec : specs) {
      const auto label = i18n::tr(spec.labelKey);

      switch (spec.valueType) {
      case settings::WidgetSettingValueType::Bool: {
        const auto* defVal = std::get_if<bool>(&spec.defaultValue);
        content.addChild(makeToggleRow(label, spec.key, defVal != nullptr ? *defVal : false, s, editor));
        break;
      }

      case settings::WidgetSettingValueType::Double: {
        const auto* defVal = std::get_if<double>(&spec.defaultValue);
        const float fallback = defVal != nullptr ? static_cast<float>(*defVal) : 0.0f;
        const float minVal = spec.minValue.has_value() ? static_cast<float>(*spec.minValue) : 0.0f;
        const float maxVal = spec.maxValue.has_value() ? static_cast<float>(*spec.maxValue) : 1.0f;
        content.addChild(
            makeSliderRow(label, spec.key, fallback, minVal, maxVal, static_cast<float>(spec.step), s, editor));
        break;
      }

      case settings::WidgetSettingValueType::String: {
        const auto* defVal = std::get_if<std::string>(&spec.defaultValue);
        const std::string fallback = defVal != nullptr ? *defVal : std::string{};
        if (spec.key == "image_path") {
          content.addChild(makeFilePickerRow(label, spec.key, editor));
        } else {
          content.addChild(makeInputRow(label, spec.key, getStr(s, spec.key, fallback), fallback, editor));
        }
        break;
      }

      case settings::WidgetSettingValueType::Select: {
        const auto* defVal = std::get_if<std::string>(&spec.defaultValue);
        const std::string fallback = defVal != nullptr ? *defVal : std::string{};
        const std::string currentValue = getStr(s, spec.key, fallback);
        if (spec.segmented) {
          content.addChild(makeSegmentedRow(label, spec.key, spec.options, currentValue, editor));
        } else {
          content.addChild(makeSelectRow(label, spec.key, spec.options, currentValue, editor));
        }
        break;
      }

      case settings::WidgetSettingValueType::ColorRole: {
        const auto* defVal = std::get_if<std::string>(&spec.defaultValue);
        const std::string token = defVal != nullptr ? *defVal : std::string{};
        const ColorSpec fallback =
            token.empty() ? colorSpecFromRole(ColorRole::OnSurface) : colorSpecFromConfigString(token);
        content.addChild(makeColorRoleSelect(label, spec.key, fallback, s, editor));
        break;
      }

      default:
        break;
      }
    }
  }

  void addBackgroundSection(Flex& content, const Settings& s, DesktopWidgetsEditor* editor) {
    auto sep = std::make_unique<Separator>();
    sep->setOrientation(SeparatorOrientation::HorizontalRule);
    content.addChild(std::move(sep));

    auto heading = std::make_unique<Label>();
    heading->setText(i18n::tr("desktop-widgets.editor.settings.background-section"));
    heading->setBold(true);
    heading->setFontSize(Style::fontSizeCaption);
    heading->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    content.addChild(std::move(heading));

    addSpecSettings(content, desktop_settings::commonDesktopWidgetSettingSpecs(), s, editor);
  }

} // namespace

void DesktopWidgetsEditor::openColorPicker(const std::string& key, const Color& currentColor) {
  ColorPickerDialogOptions options;
  options.initialColor = currentColor;
  options.title = key;
  (void)ColorPickerDialog::open(std::move(options), [this, key](std::optional<Color> result) {
    if (result) {
      applySettingChange(key, formatRgbHex(*result));
    }
  });
}

void DesktopWidgetsEditor::applySettingChange(const std::string& key, WidgetSettingValue value) {
  deferEditorMutation([this, key, value = std::move(value)]() {
    auto* state = findWidgetState(m_selectedWidgetId);
    if (state == nullptr) {
      return;
    }
    state->settings[key] = value;

    OverlaySurface* surface = findSurfaceForWidget(m_selectedWidgetId);
    if (surface == nullptr) {
      return;
    }
    auto viewIt = surface->views.find(m_selectedWidgetId);
    if (viewIt == surface->views.end()) {
      return;
    }

    auto& view = viewIt->second;
    if (view.transformNode == nullptr) {
      return;
    }

    auto newWidget = m_factory->create(state->type, state->settings, widgetContentScale(*state));
    if (newWidget == nullptr) {
      return;
    }

    if (view.widget != nullptr) {
      const auto& children = view.transformNode->children();
      for (const auto& child : children) {
        view.transformNode->removeChild(child.get());
        break;
      }
    }

    newWidget->create();
    newWidget->setAnimationManager(&surface->animations);
    auto* surfacePtr = surface;
    newWidget->setUpdateCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestUpdateOnly();
      }
    });
    newWidget->setLayoutCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestUpdate();
      }
    });
    newWidget->setRedrawCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestRedraw();
      }
    });
    newWidget->setFrameTickRequestCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestFrameTick();
      }
    });
    newWidget->update(*m_renderContext);
    newWidget->layout(*m_renderContext);

    view.intrinsicWidth = std::max(1.0f, newWidget->intrinsicWidth());
    view.intrinsicHeight = std::max(1.0f, newWidget->intrinsicHeight());
    view.transformNode->addChild(newWidget->releaseRoot());
    view.widget = std::move(newWidget);

    applyViewState(view, *state, false);
    updateSelectionVisuals(*surface);
    surface->surface->requestRedraw();
  });
}

void DesktopWidgetsEditor::buildInspector(OverlaySurface& surface, Node& root,
                                          const DesktopWidgetState& selectedState) {
  auto panel = std::make_unique<Flex>();
  panel->setDirection(FlexDirection::Vertical);
  panel->setGap(0.0f);
  panel->setFill(colorSpecFromRole(ColorRole::Surface, 0.94f));
  panel->setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
  panel->setRadius(Style::scaledRadiusXl());
  panel->setZIndex(201);
  panel->setMinWidth(kInspectorWidth);
  panel->setMaxWidth(kInspectorWidth);

  // Drag handle
  auto handle = std::make_unique<Flex>();
  handle->setDirection(FlexDirection::Horizontal);
  handle->setAlign(FlexAlign::Center);
  handle->setGap(Style::spaceXs);
  handle->setPadding(Style::spaceXs, Style::spaceMd);
  handle->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.85f));
  handle->setRadius(Style::scaledRadiusLg());
  handle->setMinHeight(Style::controlHeightSm);
  handle->setFillWidth(true);

  auto handleGlyph = std::make_unique<Glyph>();
  handleGlyph->setGlyph("menu-2");
  handleGlyph->setGlyphSize(14.0f);
  handle->addChild(std::move(handleGlyph));

  auto handleTitle = std::make_unique<Label>();
  handleTitle->setText(i18n::tr("desktop-widgets.editor.settings.title"));
  handleTitle->setBold(true);
  handleTitle->setFontSize(Style::fontSizeBody);
  handle->addChild(std::move(handleTitle));

  auto handleArea = std::make_unique<InputArea>();
  handleArea->setParticipatesInLayout(false);
  handleArea->setZIndex(1);
  handleArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE);
  handleArea->setOnPress([this, outputName = surface.outputName](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT) {
      return;
    }
    if (data.pressed) {
      startInspectorDrag(outputName);
    } else if (m_drag.mode == DragMode::InspectorMove && m_drag.surfaceOutputName == outputName) {
      finishDrag();
    }
  });
  handleArea->setOnMotion([this, outputName = surface.outputName](const InputArea::PointerData&) {
    if (m_drag.mode == DragMode::InspectorMove && m_drag.surfaceOutputName == outputName) {
      updateDrag();
    }
  });
  auto* handlePtr = handle.get();
  auto* handleAreaPtr = handleArea.get();
  handle->addChild(std::move(handleArea));
  panel->addChild(std::move(handle));

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setSize(kInspectorWidth, 0.0f);

  auto* content = scrollView->content();
  content->setDirection(FlexDirection::Vertical);
  content->setGap(Style::spaceXs);
  content->setPadding(Style::spaceSm, Style::spaceMd);

  addSpecSettings(*content, desktop_settings::desktopWidgetSettingSpecs(selectedState.type), selectedState.settings,
                  this);
  addBackgroundSection(*content, selectedState.settings, this);

  panel->addChild(std::move(scrollView));

  auto* panelPtr = panel.get();
  surface.inspector = panelPtr;
  root.addChild(std::move(panel));
  panelPtr->layout(*m_renderContext);
  handleAreaPtr->setPosition(0.0f, 0.0f);
  handleAreaPtr->setFrameSize(handlePtr->width(), handlePtr->height());

  if (!surface.inspectorPositionInitialized && surface.toolbar != nullptr) {
    surface.inspectorX = surface.toolbarX;
    surface.inspectorY = surface.toolbarY + surface.toolbar->height() + Style::spaceSm;
    surface.inspectorPositionInitialized = true;
  }
  clampInspectorPosition(surface, panelPtr->width(), panelPtr->height());
  panelPtr->setPosition(surface.inspectorX, surface.inspectorY);
}

#include "shell/test/test_panel.h"

#include "render/animation/animation_manager.h"
#include "render/core/color.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/checkbox.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/grid_tile.h"
#include "ui/controls/grid_view.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/controls/select.h"
#include "ui/controls/slider.h"
#include "ui/controls/spinner.h"
#include "ui/controls/stepper.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/dialogs/glyph_picker_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>
#include <string>
#include <vector>

void TestPanel::create() {
  const float scale = contentScale();
  auto rootLayout = std::make_unique<Flex>();
  rootLayout->setDirection(FlexDirection::Vertical);
  rootLayout->setGap(Style::spaceMd * scale);
  rootLayout->setAlign(FlexAlign::Stretch);

  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setJustify(FlexJustify::SpaceBetween);
  headerRow->setGap(Style::spaceSm * scale);

  auto header = std::make_unique<Label>();
  header->setText("Test Controls");
  header->setBold(true);
  header->setFontSize(Style::fontSizeTitle * scale);
  header->setColor(colorSpecFromRole(ColorRole::Primary));
  header->setFlexGrow(1.0f);
  m_headerLabel = header.get();
  headerRow->addChild(std::move(header));

  auto closeButton = std::make_unique<Button>();
  closeButton->setGlyph("close");
  closeButton->setVariant(ButtonVariant::Default);
  closeButton->setGlyphSize(Style::fontSizeBody * scale);
  closeButton->setMinWidth(Style::controlHeightSm * scale);
  closeButton->setMinHeight(Style::controlHeightSm * scale);
  closeButton->setPadding(Style::spaceXs * scale);
  closeButton->setRadius(Style::radiusMd * scale);
  closeButton->setOnClick([]() { PanelManager::instance().closePanel(); });
  m_closeButton = closeButton.get();
  headerRow->addChild(std::move(closeButton));
  rootLayout->addChild(std::move(headerRow));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Horizontal);
  content->setGap(Style::spaceLg * scale);
  content->setAlign(FlexAlign::Start);
  content->setFillWidth(true);

  auto colA = std::make_unique<Flex>();
  colA->setDirection(FlexDirection::Vertical);
  colA->setGap(Style::spaceMd * scale);
  colA->setAlign(FlexAlign::Start);
  colA->setFlexGrow(1.0f);

  auto colB = std::make_unique<Flex>();
  colB->setDirection(FlexDirection::Vertical);
  colB->setGap(Style::spaceMd * scale);
  colB->setAlign(FlexAlign::Start);
  colB->setFlexGrow(1.0f);

  auto colC = std::make_unique<Flex>();
  colC->setDirection(FlexDirection::Vertical);
  colC->setGap(Style::spaceMd * scale);
  colC->setAlign(FlexAlign::Start);
  colC->setFlexGrow(1.0f);

  auto makeRow = [scale]() {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setGap(Style::spaceMd * scale);
    row->setAlign(FlexAlign::Center);
    return row;
  };

  auto makeCol = [scale]() {
    auto col = std::make_unique<Flex>();
    col->setDirection(FlexDirection::Vertical);
    col->setGap(Style::spaceXs * scale);
    col->setAlign(FlexAlign::Start);
    return col;
  };

  // Each control sits in a small section: a caption-style title on top, then
  // the control underneath. This is more compact than the prior row-label
  // pattern and avoids the 150px gutter of empty space on the left.
  auto makeSection = [scale](const char* title) {
    auto section = std::make_unique<Flex>();
    section->setDirection(FlexDirection::Vertical);
    section->setGap(Style::spaceXs * scale);
    section->setAlign(FlexAlign::Start);
    auto label = std::make_unique<Label>();
    label->setText(title);
    label->setFontSize(Style::fontSizeCaption * scale);
    label->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    section->addChild(std::move(label));
    return section;
  };

  // ── Column A: Buttons + Icon buttons ────────────────────────────────────
  {
    struct VariantSpec {
      const char* label;
      ButtonVariant variant;
    };
    const std::vector<VariantSpec> variants = {
        {"Default", ButtonVariant::Default},     {"Accent", ButtonVariant::Accent},
        {"Secondary", ButtonVariant::Secondary}, {"Destructive", ButtonVariant::Destructive},
        {"Outline", ButtonVariant::Outline},     {"Ghost", ButtonVariant::Ghost},
    };

    auto makeVariantButton = [scale](const VariantSpec& spec, bool enabled = true) {
      auto btn = std::make_unique<Button>();
      btn->setText(spec.label);
      btn->setFontSize(Style::fontSizeBody * scale);
      btn->setVariant(spec.variant);
      btn->setMinHeight(Style::controlHeight * scale);
      btn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      btn->setRadius(Style::radiusMd * scale);
      btn->setOnClick([]() {});
      btn->setEnabled(enabled);
      return btn;
    };

    auto buttonsSection = makeSection("Buttons");
    auto buttonsCol = makeCol();
    buttonsCol->setGap(Style::spaceXs * scale);
    constexpr std::size_t kPerRow = 3;
    for (bool enabled : {true, false}) {
      for (std::size_t base = 0; base < variants.size(); base += kPerRow) {
        auto row = makeRow();
        for (std::size_t i = base; i < base + kPerRow && i < variants.size(); ++i) {
          row->addChild(makeVariantButton(variants[i], enabled));
        }
        buttonsCol->addChild(std::move(row));
      }
    }
    buttonsSection->addChild(std::move(buttonsCol));
    colA->addChild(std::move(buttonsSection));
  }

  {
    auto glyphTextButton = std::make_unique<Button>();
    glyphTextButton->setText("Settings");
    glyphTextButton->setGlyph("settings");
    glyphTextButton->setFontSize(Style::fontSizeBody * scale);
    glyphTextButton->setGlyphSize(Style::fontSizeBody * scale);
    glyphTextButton->setVariant(ButtonVariant::Default);
    glyphTextButton->setMinHeight(Style::controlHeight * scale);
    glyphTextButton->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    glyphTextButton->setRadius(Style::radiusMd * scale);
    glyphTextButton->setOnClick([]() {});
    m_glyphTextButton = glyphTextButton.get();

    auto glyphButton = std::make_unique<Button>();
    glyphButton->setGlyph("home");
    glyphButton->setGlyphSize(Style::fontSizeBody * scale);
    glyphButton->setVariant(ButtonVariant::Default);
    glyphButton->setMinHeight(Style::controlHeight * scale);
    glyphButton->setPadding(Style::spaceSm * scale, Style::spaceMd * scale, Style::spaceSm * scale,
                            Style::spaceMd * scale);
    glyphButton->setRadius(Style::radiusMd * scale);
    glyphButton->setOnClick([]() {});
    m_glyphButton = glyphButton.get();

    auto section = makeSection("Icon buttons");
    auto row = makeRow();
    row->addChild(std::move(glyphTextButton));
    row->addChild(std::move(glyphButton));
    section->addChild(std::move(row));
    colA->addChild(std::move(section));
  }

  // Select
  {
    auto select = std::make_unique<Select>();
    select->setSize(220.0f * scale, 0.0f);
    select->setFontSize(Style::fontSizeBody * scale);
    select->setControlHeight(Style::controlHeight * scale);
    select->setHorizontalPadding(Style::spaceMd * scale);
    select->setGlyphSize(14.0f * scale);
    select->setOptions({"Something", "Yop", "Anything"});
    select->setSelectedIndex(0);
    m_select = select.get();

    auto section = makeSection("Select");
    section->setZIndex(10);
    section->addChild(std::move(select));
    colA->addChild(std::move(section));
  }

  // Input
  {
    auto input = std::make_unique<Input>();
    input->setPlaceholder("Type something...");
    input->setSize(220.0f * scale, 0.0f);
    input->setFontSize(Style::fontSizeBody * scale);
    input->setControlHeight(Style::controlHeight * scale);
    input->setHorizontalPadding(Style::spaceMd * scale);
    m_input = input.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_inputValueLabel = valueLabel.get();

    input->setOnChange([this](const std::string& val) {
      if (m_inputValueLabel != nullptr) {
        m_inputValueLabel->setText(val.empty() ? "..." : val.substr(0, 16));
      }
    });

    auto section = makeSection("Input");
    auto row = makeRow();
    row->addChild(std::move(input));
    row->addChild(std::move(valueLabel));
    section->addChild(std::move(row));
    colA->addChild(std::move(section));
  }

  // Label (auto-scroll)
  {
    auto marquee = std::make_unique<Label>();
    marquee->setText("This label scrolls automatically when the line is longer than its layout width :p");
    marquee->setFontSize(Style::fontSizeBody * scale);
    marquee->setMaxWidth(240.0f * scale);
    marquee->setAutoScroll(true);
    marquee->setAutoScrollSpeed(42.0f * scale);

    auto marqueeHover = std::make_unique<Label>();
    marqueeHover->setText("Hover this row to scroll - the marquee pauses when the pointer leaves the label.");
    marqueeHover->setFontSize(Style::fontSizeBody * scale);
    marqueeHover->setMaxWidth(240.0f * scale);
    marqueeHover->setAutoScroll(true);
    marqueeHover->setAutoScrollSpeed(42.0f * scale);
    marqueeHover->setAutoScrollOnlyWhenHovered(true);

    auto section = makeSection("Label (auto-scroll)");
    section->addChild(std::move(marquee));
    section->addChild(std::move(marqueeHover));
    colA->addChild(std::move(section));
  }

  // Slider
  {
    auto slider = std::make_unique<Slider>();
    slider->setRange(0.0f, 100.0f);
    slider->setStep(1.0f);
    slider->setValue(50.0f);
    slider->setSize(Style::sliderDefaultWidth * scale, 0.0f);
    slider->setControlHeight(Style::controlHeight * scale);
    slider->setTrackHeight(Style::sliderTrackHeight * scale);
    slider->setThumbSize(Style::sliderThumbSize * scale);
    slider->setOnValueChanged([this](float value) {
      if (m_sliderValueLabel != nullptr) {
        const int percent = static_cast<int>(std::round(value));
        m_sliderValueLabel->setText(std::to_string(percent) + "%");
      }
    });
    m_slider = slider.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("50%");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_sliderValueLabel = valueLabel.get();

    auto section = makeSection("Slider");
    auto row = makeRow();
    row->addChild(std::move(slider));
    row->addChild(std::move(valueLabel));
    section->addChild(std::move(row));
    colA->addChild(std::move(section));
  }

  // ── Column B: Toggles, Segmented, Checkbox, Radio, Spinner ──────────────
  {
    auto toggle = std::make_unique<Toggle>();
    toggle->setToggleSize(ToggleSize::Medium);
    toggle->setScale(scale);
    toggle->setChecked(false);
    toggle->setOnChange([this](bool checked) {
      if (m_toggleValueLabel != nullptr) {
        m_toggleValueLabel->setText(checked ? "true" : "false");
      }
    });
    m_toggle = toggle.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("false");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_toggleValueLabel = valueLabel.get();

    auto section = makeSection("Toggle");
    auto row = makeRow();
    row->addChild(std::move(toggle));
    row->addChild(std::move(valueLabel));
    section->addChild(std::move(row));
    colB->addChild(std::move(section));
  }

  {
    auto segmented = std::make_unique<Segmented>();
    segmented->setScale(scale);
    segmented->addOption("Light");
    segmented->addOption("Dark");
    segmented->addOption("System");
    segmented->setSelectedIndex(2);

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("System");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_segmentedValueLabel = valueLabel.get();

    static const char* const kLabels[] = {"Light", "Dark", "System"};
    segmented->setOnChange([this](std::size_t index) {
      if (m_segmentedValueLabel != nullptr && index < std::size(kLabels)) {
        m_segmentedValueLabel->setText(kLabels[index]);
      }
    });
    m_segmented = segmented.get();

    auto section = makeSection("Segmented");
    auto row = makeRow();
    row->addChild(std::move(segmented));
    row->addChild(std::move(valueLabel));
    section->addChild(std::move(row));
    colB->addChild(std::move(section));
  }

  {
    auto checkbox = std::make_unique<Checkbox>();
    checkbox->setScale(scale);
    checkbox->setChecked(true);
    checkbox->setOnChange([this](bool checked) {
      if (m_checkboxValueLabel != nullptr) {
        m_checkboxValueLabel->setText(checked ? "true" : "false");
      }
    });
    m_checkbox = checkbox.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("true");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_checkboxValueLabel = valueLabel.get();

    auto section = makeSection("Checkbox");
    auto row = makeRow();
    row->addChild(std::move(checkbox));
    row->addChild(std::move(valueLabel));
    section->addChild(std::move(row));
    colB->addChild(std::move(section));
  }

  {
    auto makeRadioOption = [scale](const char* text, std::unique_ptr<RadioButton> radio) {
      auto opt = std::make_unique<Flex>();
      opt->setDirection(FlexDirection::Horizontal);
      opt->setAlign(FlexAlign::Center);
      opt->setGap(Style::spaceXs * scale);
      opt->addChild(std::move(radio));
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(Style::fontSizeBody * scale);
      opt->addChild(std::move(label));
      return opt;
    };

    auto radioA = std::make_unique<RadioButton>();
    radioA->setScale(scale);
    radioA->setChecked(true);
    m_radioA = radioA.get();

    auto radioB = std::make_unique<RadioButton>();
    radioB->setScale(scale);
    m_radioB = radioB.get();

    if (m_radioA != nullptr) {
      m_radioA->setOnChange([this](bool checked) {
        if (!checked || m_radioB == nullptr) {
          return;
        }
        m_radioA->setChecked(true);
        m_radioB->setChecked(false);
      });
    }
    if (m_radioB != nullptr) {
      m_radioB->setOnChange([this](bool checked) {
        if (!checked || m_radioA == nullptr) {
          return;
        }
        m_radioA->setChecked(false);
        m_radioB->setChecked(true);
      });
    }

    auto options = std::make_unique<Flex>();
    options->setDirection(FlexDirection::Horizontal);
    options->setAlign(FlexAlign::Center);
    options->setGap(Style::spaceMd * scale);
    options->addChild(makeRadioOption("Option A", std::move(radioA)));
    options->addChild(makeRadioOption("Option B", std::move(radioB)));

    auto section = makeSection("Radio");
    section->addChild(std::move(options));
    colB->addChild(std::move(section));
  }

  {
    auto spinner = std::make_unique<Spinner>();
    spinner->setSpinnerSize(20.0f * scale);
    spinner->setThickness(2.0f * scale);
    m_spinner = spinner.get();

    auto section = makeSection("Spinner");
    section->addChild(std::move(spinner));
    colB->addChild(std::move(section));
  }

  {
    auto stepper = std::make_unique<Stepper>();
    stepper->setScale(scale);
    stepper->setRange(0, 99);
    stepper->setStep(1);
    stepper->setValue(42);
    stepper->setOnValueChanged([this](int v) {
      if (m_stepperValueLabel != nullptr) {
        m_stepperValueLabel->setText("onChange: " + std::to_string(v));
      }
    });
    m_stepper = stepper.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("onChange: 42");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_stepperValueLabel = valueLabel.get();

    auto section = makeSection("Stepper");
    section->addChild(std::move(stepper));
    section->addChild(std::move(valueLabel));
    colB->addChild(std::move(section));
  }

  // ── Column C: File dialog, Color picker, Grid view, Transforms ──────────
  {
    auto resultLabel = std::make_unique<Label>();
    resultLabel->setText("No image selected");
    resultLabel->setCaptionStyle();
    resultLabel->setFontSize(Style::fontSizeCaption * scale);
    resultLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    resultLabel->setMaxWidth(280.0f * scale);
    m_fileDialogResultLabel = resultLabel.get();

    auto openFileDialog = std::make_unique<Button>();
    openFileDialog->setText("Browse images...");
    openFileDialog->setGlyph("image");
    openFileDialog->setFontSize(Style::fontSizeBody * scale);
    openFileDialog->setGlyphSize(Style::fontSizeBody * scale);
    openFileDialog->setVariant(ButtonVariant::Default);
    openFileDialog->setMinHeight(Style::controlHeight * scale);
    openFileDialog->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    openFileDialog->setRadius(Style::radiusMd * scale);
    openFileDialog->setOnClick([this]() {
      FileDialogOptions options;
      options.mode = FileDialogMode::Open;
      options.title = "Select Image";
      options.extensions = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"};
      (void)FileDialog::open(std::move(options), [this](std::optional<std::filesystem::path> result) {
        if (m_fileDialogResultLabel == nullptr) {
          return;
        }
        if (result.has_value()) {
          m_fileDialogResultLabel->setText(result->string());
          m_fileDialogResultLabel->setColor(colorSpecFromRole(ColorRole::Primary));
        } else {
          m_fileDialogResultLabel->setText("Cancelled");
          m_fileDialogResultLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        }
      });
    });
    m_openFileDialogButton = openFileDialog.get();

    auto section = makeSection("File dialog");
    auto row = makeRow();
    row->addChild(std::move(openFileDialog));
    row->addChild(std::move(resultLabel));
    section->addChild(std::move(row));
    colC->addChild(std::move(section));
  }

  {
    auto resultSwatch = std::make_unique<Box>();
    resultSwatch->setSize(28.0f * scale, 28.0f * scale);
    resultSwatch->setRadius(Style::radiusMd * scale);
    resultSwatch->setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth * scale);
    if (const auto last = ColorPickerDialog::lastResult()) {
      resultSwatch->setFill(*last);
    } else {
      resultSwatch->setFill(colorForRole(ColorRole::Primary));
    }
    m_colorPickerResultSwatch = resultSwatch.get();

    auto openPicker = std::make_unique<Button>();
    openPicker->setText("Open color picker…");
    openPicker->setFontSize(Style::fontSizeBody * scale);
    openPicker->setVariant(ButtonVariant::Default);
    openPicker->setMinHeight(Style::controlHeight * scale);
    openPicker->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    openPicker->setRadius(Style::radiusMd * scale);
    openPicker->setOnClick([this]() {
      ColorPickerDialogOptions options;
      if (const auto last = ColorPickerDialog::lastResult()) {
        options.initialColor = *last;
      }
      (void)ColorPickerDialog::open(std::move(options), [this](std::optional<Color> result) {
        if (!result.has_value() || m_colorPickerResultSwatch == nullptr) {
          return;
        }
        m_colorPickerResultSwatch->setFill(*result);
      });
    });
    m_openColorPickerButton = openPicker.get();

    auto section = makeSection("Color picker");
    auto row = makeRow();
    row->addChild(std::move(openPicker));
    row->addChild(std::move(resultSwatch));
    section->addChild(std::move(row));
    colC->addChild(std::move(section));
  }

  {
    auto resultLabel = std::make_unique<Label>();
    if (const auto last = GlyphPickerDialog::lastResult()) {
      resultLabel->setText(last->name);
      resultLabel->setColor(colorSpecFromRole(ColorRole::Primary));
    } else {
      resultLabel->setText("No glyph selected");
      resultLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    }
    resultLabel->setCaptionStyle();
    resultLabel->setFontSize(Style::fontSizeCaption * scale);
    resultLabel->setMaxWidth(280.0f * scale);
    m_glyphPickerResultLabel = resultLabel.get();

    auto openPicker = std::make_unique<Button>();
    openPicker->setText("Open glyph picker...");
    openPicker->setFontSize(Style::fontSizeBody * scale);
    openPicker->setVariant(ButtonVariant::Default);
    openPicker->setMinHeight(Style::controlHeight * scale);
    openPicker->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    openPicker->setRadius(Style::radiusMd * scale);
    openPicker->setOnClick([this]() {
      GlyphPickerDialogOptions options;
      if (const auto last = GlyphPickerDialog::lastResult()) {
        options.initialGlyph = last->name;
      }
      (void)GlyphPickerDialog::open(std::move(options), [this](std::optional<GlyphPickerResult> result) {
        if (!result.has_value()) {
          return;
        }
        if (m_glyphPickerResultLabel != nullptr) {
          m_glyphPickerResultLabel->setText(result->name);
          m_glyphPickerResultLabel->setColor(colorSpecFromRole(ColorRole::Primary));
        }
        if (m_glyphButton != nullptr) {
          m_glyphButton->setGlyph(result->name);
        }
      });
    });
    m_openGlyphPickerButton = openPicker.get();

    auto section = makeSection("Glyph picker");
    auto row = makeRow();
    row->addChild(std::move(openPicker));
    row->addChild(std::move(resultLabel));
    section->addChild(std::move(row));
    colC->addChild(std::move(section));
  }

  {
    auto grid = std::make_unique<GridView>();
    grid->setColumns(3);
    grid->setColumnGap(Style::spaceSm * scale);
    grid->setRowGap(Style::spaceSm * scale);
    grid->setPadding(Style::spaceXs * scale);
    grid->setSize(300.0f * scale, 0.0f);
    grid->setUniformCellSize(true);
    grid->setMinCellHeight(64.0f * scale);

    struct TileSpec {
      const char* glyph;
      const char* label;
      bool accent;
    };
    const std::vector<TileSpec> tiles = {
        {"home", "Home", false},         {"media-play", "Music", true},       {"copy", "Gallery", false},
        {"settings", "Settings", false}, {"weather-cloud", "Weather", false}, {"check", "Calendar", false},
    };

    for (const auto& tileData : tiles) {
      auto tile = std::make_unique<GridTile>();
      tile->setDirection(FlexDirection::Vertical);
      tile->setAlign(FlexAlign::Center);
      tile->setJustify(FlexJustify::Center);
      tile->setGap(Style::spaceXs * scale);
      tile->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
      if (tileData.accent) {
        tile->setRadius(Style::radiusMd * scale);
        tile->setFill(colorSpecFromRole(ColorRole::Primary));
        tile->setBorder(colorSpecFromRole(ColorRole::Primary), Style::borderWidth);
      } else {
        tile->setCardStyle(scale);
        tile->setRadius(Style::radiusMd * scale);
      }

      auto icon = std::make_unique<Glyph>();
      icon->setGlyph(tileData.glyph);
      icon->setGlyphSize(16.0f * scale);
      icon->setColor(colorSpecFromRole(tileData.accent ? ColorRole::OnPrimary : ColorRole::OnSurface));
      tile->addChild(std::move(icon));

      auto label = std::make_unique<Label>();
      label->setText(tileData.label);
      label->setCaptionStyle();
      label->setFontSize(Style::fontSizeCaption * scale);
      label->setColor(colorSpecFromRole(tileData.accent ? ColorRole::OnPrimary : ColorRole::OnSurfaceVariant));
      tile->addChild(std::move(label));

      grid->addChild(std::move(tile));
    }

    auto section = makeSection("Grid view");
    section->addChild(std::move(grid));
    colC->addChild(std::move(section));
  }

  // Transforms
  {
    auto transformStage = std::make_unique<Box>();
    transformStage->setSize(280.0f * scale, 220.0f * scale);
    transformStage->setFill(colorSpecFromRole(ColorRole::Surface));
    transformStage->setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth * scale);
    transformStage->setRadius(Style::radiusLg * scale);
    m_transformStage = transformStage.get();

    auto demoBox = std::make_unique<Box>();
    demoBox->setSize(180.0f * scale, 100.0f * scale);
    demoBox->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
    demoBox->setBorder(colorSpecFromRole(ColorRole::Primary), Style::borderWidth * scale);
    demoBox->setRadius(Style::radiusLg * scale);
    demoBox->setRotation(0.0f);
    m_transformDemoBox = demoBox.get();

    auto demoButton = std::make_unique<Button>();
    demoButton->setText("Click me...");
    demoButton->setGlyph("cpu-temperature");
    demoButton->setFontSize(Style::fontSizeBody * scale);
    demoButton->setGlyphSize(Style::fontSizeBody * scale);
    demoButton->setVariant(ButtonVariant::Accent);
    demoButton->setPadding(Style::spaceSm * scale, Style::spaceLg * scale);
    demoButton->setRadius(Style::radiusMd * scale);
    demoButton->setOnClick([this]() {
      if (m_transformHelp != nullptr) {
        m_transformHelp->setText("Transform button clicked!");
        m_transformHelp->setColor(colorSpecFromRole(ColorRole::Secondary));
      }
    });
    m_transformDemoButton = demoButton.get();
    m_transformDemoBox->addChild(std::move(demoButton));

    auto demoGlyph = std::make_unique<Glyph>();
    demoGlyph->setGlyph("noctalia");
    demoGlyph->setPosition(150.0f * scale, 60.0f * scale);
    demoGlyph->setGlyphSize(24.0f * scale);
    demoGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
    demoGlyph->setRotation(static_cast<float>(M_PI) * 0.5f);
    m_transformDemoGlyph = demoGlyph.get();
    m_transformDemoBox->addChild(std::move(demoGlyph));

    auto badgeBox = std::make_unique<Box>();
    badgeBox->setSize(28.0f * scale, 28.0f * scale);
    badgeBox->setFill(colorSpecFromRole(ColorRole::Primary));
    badgeBox->setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth * scale);
    badgeBox->setRadius(14.0f * scale);
    m_transformBadgeBox = badgeBox.get();

    auto badgeLabel = std::make_unique<Label>();
    badgeLabel->setText("3");
    badgeLabel->setFontSize(Style::fontSizeCaption * scale);
    badgeLabel->setColor(colorSpecFromRole(ColorRole::OnPrimary));
    m_transformBadgeLabel = badgeLabel.get();
    m_transformBadgeBox->addChild(std::move(badgeLabel));
    m_transformDemoBox->addChild(std::move(badgeBox));
    m_transformStage->addChild(std::move(demoBox));

    auto helpLabel = std::make_unique<Label>();
    helpLabel->setText("Rotated node with children.");
    helpLabel->setFontSize(Style::fontSizeCaption * scale);
    helpLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_transformHelp = helpLabel.get();

    auto section = makeSection("Transforms");
    section->addChild(std::move(helpLabel));
    section->addChild(std::move(transformStage));
    colC->addChild(std::move(section));
  }

  m_container = colA.get();
  content->addChild(std::move(colA));
  content->addChild(std::move(colB));
  content->addChild(std::move(colC));

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(0.0f);
  scroll->clearFill();
  scroll->clearBorder();
  scroll->setFlexGrow(1.0f);
  m_scrollView = scroll.get();
  auto* scrollContent = scroll->content();
  scrollContent->setDirection(FlexDirection::Vertical);
  scrollContent->setAlign(FlexAlign::Stretch);
  scrollContent->setGap(Style::spaceMd * scale);
  scrollContent->addChild(std::move(content));
  rootLayout->addChild(std::move(scroll));

  setRoot(std::move(rootLayout));

  // Propagate animation manager to all controls in the tree
  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  // Start spinner after animation manager is propagated
  if (m_spinner != nullptr) {
    m_spinner->start();
  }

  if (m_animations != nullptr && m_transformDemoBox != nullptr) {
    m_animations->animate(0.0f, 2.0f * static_cast<float>(M_PI), 8000.0f, Easing::Linear, [this](float phase) {
      if (m_transformDemoBox != nullptr) {
        m_transformDemoBox->setRotation(phase);
        m_transformDemoBox->setScale(1.0f + 0.16f * std::sin(phase));
      }
    });
  }
}

void TestPanel::onClose() {
  m_container = nullptr;
  m_headerLabel = nullptr;
  m_sliderValueLabel = nullptr;
  m_toggleValueLabel = nullptr;
  m_checkboxValueLabel = nullptr;
  m_select = nullptr;
  m_glyphTextButton = nullptr;
  m_glyphButton = nullptr;
  m_glyphBox = nullptr;
  m_glyph = nullptr;
  m_transformStage = nullptr;
  m_transformDemoBox = nullptr;
  m_transformDemoGlyph = nullptr;
  m_transformDemoButton = nullptr;
  m_transformBadgeBox = nullptr;
  m_transformBadgeLabel = nullptr;
  m_slider = nullptr;
  m_toggle = nullptr;
  m_checkbox = nullptr;
  m_radioA = nullptr;
  m_radioB = nullptr;
  m_spinner = nullptr;
  m_stepper = nullptr;
  m_stepperValueLabel = nullptr;
  m_input = nullptr;
  m_inputValueLabel = nullptr;
  m_openFileDialogButton = nullptr;
  m_fileDialogResultLabel = nullptr;
  m_transformHelp = nullptr;
  m_colorPickerResultSwatch = nullptr;
  m_openColorPickerButton = nullptr;
  m_openGlyphPickerButton = nullptr;
  m_glyphPickerResultLabel = nullptr;
  m_segmented = nullptr;
  m_segmentedValueLabel = nullptr;
  m_closeButton = nullptr;
  m_scrollView = nullptr;
}

void TestPanel::doLayout(Renderer& renderer, float width, float height) {
  if (root() == nullptr) {
    return;
  }
  root()->setSize(width, height);
  root()->layout(renderer);

  if (m_glyph != nullptr && m_glyphBox != nullptr) {
    m_glyph->measure(renderer);
    m_glyph->setPosition(std::round((m_glyphBox->width() - m_glyph->width()) * 0.5f),
                         std::round((m_glyphBox->height() - m_glyph->height()) * 0.5f));
  }
  if (m_transformStage != nullptr && m_transformDemoBox != nullptr) {
    m_transformDemoBox->setPosition(std::round((m_transformStage->width() - m_transformDemoBox->width()) * 0.5f),
                                    std::round((m_transformStage->height() - m_transformDemoBox->height()) * 0.5f));
  }
  if (m_transformDemoBox != nullptr && m_transformDemoButton != nullptr) {
    m_transformDemoButton->layout(renderer);
    m_transformDemoButton->setPosition(
        std::round((m_transformDemoBox->width() - m_transformDemoButton->width()) * 0.5f),
        std::round((m_transformDemoBox->height() - m_transformDemoButton->height()) * 0.5f));
  }
  if (m_transformDemoBox != nullptr && m_transformDemoGlyph != nullptr) {
    m_transformDemoGlyph->measure(renderer);
    m_transformDemoGlyph->setPosition(
        18.0f * contentScale(), std::round((m_transformDemoBox->height() - m_transformDemoGlyph->height()) * 0.85f));
  }
  if (m_transformDemoBox != nullptr && m_transformBadgeBox != nullptr) {
    m_transformBadgeBox->setPosition(
        m_transformDemoBox->width() - m_transformBadgeBox->width() - 12.0f * contentScale(), 12.0f * contentScale());
  }
  if (m_transformBadgeBox != nullptr && m_transformBadgeLabel != nullptr) {
    m_transformBadgeLabel->measure(renderer);
    m_transformBadgeLabel->setPosition(
        std::round((m_transformBadgeBox->width() - m_transformBadgeLabel->width()) * 0.5f),
        std::round((m_transformBadgeBox->height() - m_transformBadgeLabel->height()) * 0.5f) - 1.0f * contentScale());
  }
}

void TestPanel::doUpdate(Renderer& /*renderer*/) {}

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
#include "ui/controls/select.h"
#include "ui/controls/slider.h"
#include "ui/controls/spinner.h"
#include "ui/controls/toggle.h"
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
  rootLayout->setAlign(FlexAlign::Start);

  auto header = std::make_unique<Label>();
  header->setText("Test Controls");
  header->setFontSize(Style::fontSizeTitle * scale);
  header->setColor(roleColor(ColorRole::Primary));
  m_headerLabel = header.get();
  rootLayout->addChild(std::move(header));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Horizontal);
  content->setGap(Style::spaceLg * scale);
  content->setAlign(FlexAlign::Start);

  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setGap(Style::spaceMd * scale);
  container->setAlign(FlexAlign::Start);

  const float kRowLabelWidth = 150.0f * scale;

  auto makeCol = [scale]() {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Vertical);
    row->setGap(Style::spaceMd * scale);
    row->setAlign(FlexAlign::Center);
    return row;
  };

  auto makeRow = [scale]() {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setGap(Style::spaceMd * scale);
    row->setAlign(FlexAlign::Center);
    return row;
  };

  auto makeRowLabel = [scale](const char* text, float minWidth) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(Style::fontSizeBody * scale);
    label->setMinWidth(minWidth);
    return label;
  };

  // Button
  auto button = std::make_unique<Button>();
  button->setText("Hello");
  button->setFontSize(Style::fontSizeBody * scale);
  button->setVariant(ButtonVariant::Default);
  button->setMinHeight(Style::controlHeight * scale);
  button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
  button->setRadius(Style::radiusMd * scale);
  button->setOnClick([]() {});
  m_button = button.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button", kRowLabelWidth));
    row->addChild(std::move(button));
    container->addChild(std::move(row));
  }

  // Button w/ glyph
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
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button w/ glyph", kRowLabelWidth));
    row->addChild(std::move(glyphTextButton));
    container->addChild(std::move(row));
  }

  // Button glyph only
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
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button glyph", kRowLabelWidth));
    row->addChild(std::move(glyphButton));
    container->addChild(std::move(row));
  }

  // Glyph in a box
  auto glyphBox = std::make_unique<Box>();
  glyphBox->setSize(Style::controlHeight * scale, Style::controlHeight * scale);
  glyphBox->setFill(roleColor(ColorRole::SurfaceVariant));
  glyphBox->setBorder(roleColor(ColorRole::Outline), Style::borderWidth);
  glyphBox->setRadius(Style::radiusMd * scale);
  m_glyphBox = glyphBox.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("home");
  glyph->setGlyphSize(Style::fontSizeBody * scale);
  glyph->setColor(roleColor(ColorRole::OnSurface));
  m_glyph = glyph.get();
  m_glyphBox->addChild(std::move(glyph));
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Glyph box", kRowLabelWidth));
    row->addChild(std::move(glyphBox));
    container->addChild(std::move(row));
  }

  // Select
  auto select = std::make_unique<Select>();
  select->setSize(220.0f * scale, 0.0f);
  select->setFontSize(Style::fontSizeBody * scale);
  select->setControlHeight(Style::controlHeight * scale);
  select->setHorizontalPadding(Style::spaceMd * scale);
  select->setGlyphSize(14.0f * scale);
  select->setOptions({"Something", "Yop", "Anything"});
  select->setSelectedIndex(0);
  m_select = select.get();
  {
    auto row = makeRow();
    row->setZIndex(10);
    row->addChild(makeRowLabel("Select", kRowLabelWidth));
    row->addChild(std::move(select));

    container->addChild(std::move(row));
  }

  // Slider
  auto slider = std::make_unique<Slider>();
  slider->setRange(0.0f, 100.0f);
  slider->setStep(1.0f);
  slider->setValue(50.0f);
  slider->setSize(180.0f * scale, 0.0f);
  slider->setControlHeight(Style::controlHeight * scale);
  slider->setTrackHeight(6.0f * scale);
  slider->setThumbSize(16.0f * scale);
  slider->setOnValueChanged([this](float value) {
    if (m_sliderValueLabel != nullptr) {
      const int percent = static_cast<int>(std::round(value));
      m_sliderValueLabel->setText(std::to_string(percent) + "%");
    }
  });
  m_slider = slider.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Slider", kRowLabelWidth));
    row->addChild(std::move(slider));

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setText("50%");
    valueLabel->setCaptionStyle();
    valueLabel->setFontSize(Style::fontSizeCaption * scale);
    m_sliderValueLabel = valueLabel.get();
    row->addChild(std::move(valueLabel));

    container->addChild(std::move(row));
  }

  // Toggle
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

  auto toggleValueLabel = std::make_unique<Label>();
  toggleValueLabel->setText("false");
  toggleValueLabel->setCaptionStyle();
  toggleValueLabel->setFontSize(Style::fontSizeCaption * scale);
  m_toggleValueLabel = toggleValueLabel.get();

  m_container = container.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Toggle", kRowLabelWidth));
    row->addChild(std::move(toggle));
    row->addChild(std::move(toggleValueLabel));
    container->addChild(std::move(row));
  }

  // Checkbox
  auto checkbox = std::make_unique<Checkbox>();
  checkbox->setScale(scale);
  checkbox->setChecked(true);
  checkbox->setOnChange([this](bool checked) {
    if (m_checkboxValueLabel != nullptr) {
      m_checkboxValueLabel->setText(checked ? "true" : "false");
    }
  });
  m_checkbox = checkbox.get();

  auto checkboxValueLabel = std::make_unique<Label>();
  checkboxValueLabel->setText("true");
  checkboxValueLabel->setCaptionStyle();
  checkboxValueLabel->setFontSize(Style::fontSizeCaption * scale);
  m_checkboxValueLabel = checkboxValueLabel.get();

  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Checkbox", kRowLabelWidth));
    row->addChild(std::move(checkbox));
    row->addChild(std::move(checkboxValueLabel));
    container->addChild(std::move(row));
  }

  // Radio
  {
    auto options = std::make_unique<Flex>();
    options->setDirection(FlexDirection::Horizontal);
    options->setAlign(FlexAlign::Center);
    options->setGap(Style::spaceMd * scale);

    auto optionA = std::make_unique<Flex>();
    optionA->setDirection(FlexDirection::Horizontal);
    optionA->setAlign(FlexAlign::Center);
    optionA->setGap(Style::spaceXs * scale);

    auto radioA = std::make_unique<RadioButton>();
    radioA->setScale(scale);
    radioA->setChecked(true);
    m_radioA = radioA.get();

    auto labelA = std::make_unique<Label>();
    labelA->setText("Option A");
    labelA->setFontSize(Style::fontSizeBody * scale);

    optionA->addChild(std::move(radioA));
    optionA->addChild(std::move(labelA));

    auto optionB = std::make_unique<Flex>();
    optionB->setDirection(FlexDirection::Horizontal);
    optionB->setAlign(FlexAlign::Center);
    optionB->setGap(Style::spaceXs * scale);

    auto radioB = std::make_unique<RadioButton>();
    radioB->setScale(scale);
    m_radioB = radioB.get();

    auto labelB = std::make_unique<Label>();
    labelB->setText("Option B");
    labelB->setFontSize(Style::fontSizeBody * scale);

    optionB->addChild(std::move(radioB));
    optionB->addChild(std::move(labelB));

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

    options->addChild(std::move(optionA));
    options->addChild(std::move(optionB));

    auto row = makeRow();
    row->addChild(makeRowLabel("Radio", kRowLabelWidth));
    row->addChild(std::move(options));
    container->addChild(std::move(row));
  }

  // Spinner
  {
    auto spinner = std::make_unique<Spinner>();
    spinner->setSpinnerSize(20.0f * scale);
    spinner->setThickness(2.0f * scale);
    m_spinner = spinner.get();
    auto row = makeRow();
    row->addChild(makeRowLabel("Spinner", kRowLabelWidth));
    row->addChild(std::move(spinner));
    container->addChild(std::move(row));
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

    auto col = makeCol();
    col->addChild(std::move(input));
    col->addChild(std::move(valueLabel));

    auto row = makeRow();
    row->addChild(makeRowLabel("Input", kRowLabelWidth));
    row->addChild(std::move(col));

    container->addChild(std::move(row));
  }

  // Color picker (layer panel)
  {
    auto resultSwatch = std::make_unique<Box>();
    resultSwatch->setSize(28.0f * scale, 28.0f * scale);
    resultSwatch->setRadius(Style::radiusMd * scale);
    resultSwatch->setBorder(roleColor(ColorRole::Outline), Style::borderWidth * scale);
    if (const auto last = PanelManager::instance().lastColorPickerResult()) {
      resultSwatch->setFill(*last);
    } else {
      resultSwatch->setFill(resolveThemeColor(roleColor(ColorRole::Primary)));
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
      PanelManager::instance().setColorPickerResultCallback([this](const Color& c) {
        if (m_colorPickerResultSwatch != nullptr) {
          m_colorPickerResultSwatch->setFill(c);
        }
      });
      PanelManager::instance().togglePanel("color-picker");
    });
    m_openColorPickerButton = openPicker.get();

    auto row = makeRow();
    row->setAlign(FlexAlign::Start);
    row->addChild(makeRowLabel("Color picker", kRowLabelWidth));
    row->addChild(std::move(openPicker));
    row->addChild(std::move(resultSwatch));
    container->addChild(std::move(row));
  }

  // Grid view
  {
    auto grid = std::make_unique<GridView>();
    grid->setColumns(4);
    grid->setColumnGap(Style::spaceSm * scale);
    grid->setRowGap(Style::spaceSm * scale);
    grid->setPadding(Style::spaceXs * scale);
    grid->setSize(360.0f * scale, 0.0f);
    grid->setUniformCellSize(true);
    grid->setMinCellHeight(76.0f * scale);

    struct TileSpec {
      const char* glyph;
      const char* label;
      bool accent;
    };
    const std::vector<TileSpec> tiles = {
        {"home", "Home", false},
        {"media-play", "Music", true},
        {"copy", "Gallery", false},
        {"settings", "Settings", false},
        {"weather-cloud", "Weather", false},
        {"check", "Calendar", false},
        {"cpu-temperature", "Terminal", true},
        {"shutdown", "Power", false},
    };

    for (const auto& tileData : tiles) {
      auto tile = std::make_unique<GridTile>();
      tile->setDirection(FlexDirection::Vertical);
      tile->setAlign(FlexAlign::Center);
      tile->setJustify(FlexJustify::Center);
      tile->setGap(Style::spaceXs * scale);
      tile->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
      tile->setRadius(Style::radiusMd * scale);
      tile->setBackground(roleColor(tileData.accent ? ColorRole::Primary : ColorRole::SurfaceVariant));
      tile->setBorderColor(roleColor(tileData.accent ? ColorRole::Primary : ColorRole::Outline));
      tile->setBorderWidth(Style::borderWidth);

      auto icon = std::make_unique<Glyph>();
      icon->setGlyph(tileData.glyph);
      icon->setGlyphSize(16.0f * scale);
      icon->setColor(roleColor(tileData.accent ? ColorRole::OnPrimary : ColorRole::OnSurface));
      tile->addChild(std::move(icon));

      auto label = std::make_unique<Label>();
      label->setText(tileData.label);
      label->setCaptionStyle();
      label->setFontSize(Style::fontSizeCaption * scale);
      label->setColor(roleColor(tileData.accent ? ColorRole::OnPrimary : ColorRole::OnSurfaceVariant));
      tile->addChild(std::move(label));

      grid->addChild(std::move(tile));
    }

    auto row = makeRow();
    row->addChild(makeRowLabel("Grid view", kRowLabelWidth));
    row->addChild(std::move(grid));
    container->addChild(std::move(row));
  }

  auto transformColumn = std::make_unique<Flex>();
  transformColumn->setDirection(FlexDirection::Vertical);
  transformColumn->setGap(Style::spaceMd * scale);
  transformColumn->setAlign(FlexAlign::Start);

  auto transformHeader = std::make_unique<Label>();
  transformHeader->setText("Transforms");
  transformHeader->setFontSize(Style::fontSizeBody * scale);
  transformHeader->setColor(roleColor(ColorRole::Primary));
  transformColumn->addChild(std::move(transformHeader));

  auto transformHelp = std::make_unique<Label>();
  transformHelp->setText("Rotated node with children.");
  transformHelp->setFontSize(Style::fontSizeCaption * scale);
  transformHelp->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_transformHelp = transformHelp.get();
  transformColumn->addChild(std::move(transformHelp));

  auto transformStage = std::make_unique<Box>();
  transformStage->setSize(360.0f * scale, 360.0f * scale);
  transformStage->setFill(roleColor(ColorRole::Surface));
  transformStage->setBorder(roleColor(ColorRole::Outline), Style::borderWidth * scale);
  transformStage->setRadius(Style::radiusLg * scale);
  m_transformStage = transformStage.get();

  auto demoBox = std::make_unique<Box>();
  demoBox->setPosition(60.f, 80.f);
  demoBox->setSize(240.0f * scale, 130.0f * scale);
  demoBox->setFill(roleColor(ColorRole::SurfaceVariant));
  demoBox->setBorder(roleColor(ColorRole::Primary), Style::borderWidth * scale);
  demoBox->setRadius(Style::radiusLg * scale);
  demoBox->setRotation(0.0f);
  m_transformDemoBox = demoBox.get();

  auto demoButton = std::make_unique<Button>();
  demoButton->setText("Click me...");
  demoButton->setGlyph("cpu-temperature");
  demoButton->setFontSize(Style::fontSizeBody * scale);
  demoButton->setGlyphSize(Style::fontSizeBody * scale);
  demoButton->setVariant(ButtonVariant::Accent);
  demoButton->setPosition(20.0f, 20.f);
  demoButton->setPadding(Style::spaceSm * scale, Style::spaceLg * scale);
  demoButton->setRadius(Style::radiusMd * scale);
  demoButton->setOnClick([this]() {
    if (m_transformHelp != nullptr) {
      m_transformHelp->setText("Transform button clicked!!!");
      m_transformHelp->setColor(roleColor(ColorRole::Secondary));
    }
  });
  m_transformDemoButton = demoButton.get();
  m_transformDemoBox->addChild(std::move(demoButton));

  auto demoGlyph = std::make_unique<Glyph>();
  demoGlyph->setGlyph("noctalia");
  demoGlyph->setPosition(200.0f, 80.0f);
  demoGlyph->setGlyphSize(28.0f * scale);
  demoGlyph->setColor(roleColor(ColorRole::Primary));
  demoGlyph->setRotation(static_cast<float>(M_PI) * 0.5f);
  m_transformDemoGlyph = demoGlyph.get();
  m_transformDemoBox->addChild(std::move(demoGlyph));

  auto badgeBox = std::make_unique<Box>();
  badgeBox->setPosition(80.0f, 80.0f);
  badgeBox->setSize(30.0f * scale, 30.0f * scale);
  badgeBox->setFill(roleColor(ColorRole::Primary));
  badgeBox->setBorder(roleColor(ColorRole::Outline), Style::borderWidth * scale);
  badgeBox->setRadius(15.0f * scale);
  m_transformBadgeBox = badgeBox.get();

  auto badgeLabel = std::make_unique<Label>();
  badgeLabel->setText("3");
  badgeLabel->setPosition(10.0f, 10.0f);
  badgeLabel->setFontSize(Style::fontSizeCaption * scale);
  badgeLabel->setColor(roleColor(ColorRole::OnPrimary));
  m_transformBadgeLabel = badgeLabel.get();
  m_transformBadgeBox->addChild(std::move(badgeLabel));
  m_transformDemoBox->addChild(std::move(badgeBox));
  m_transformStage->addChild(std::move(demoBox));
  transformColumn->addChild(std::move(transformStage));

  m_container = container.get();
  content->addChild(std::move(container));
  content->addChild(std::move(transformColumn));
  rootLayout->addChild(std::move(content));

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
  m_button = nullptr;
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
  m_input = nullptr;
  m_inputValueLabel = nullptr;
  m_transformHelp = nullptr;
  m_colorPickerResultSwatch = nullptr;
  m_openColorPickerButton = nullptr;
}

void TestPanel::doLayout(Renderer& renderer, float /*width*/, float /*height*/) {
  if (root() == nullptr) {
    return;
  }
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

#include "shell/test/test_panel.h"

#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
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

void TestPanel::create(Renderer& renderer) {
  const float scale = contentScale();
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setGap(Style::spaceMd * scale);
  container->setAlign(FlexAlign::Start);

  auto header = std::make_unique<Label>();
  header->setText("Test Controls");
  header->setFontSize(Style::fontSizeTitle * scale);
  header->setColor(palette.primary);
  m_headerLabel = header.get();
  container->addChild(std::move(header));

  const float kRowLabelWidth = 150.0f * scale;

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
  glyphButton->setGlyph("media-play");
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
  glyphBox->setFill(palette.surfaceVariant);
  glyphBox->setBorder(palette.outline, Style::borderWidth);
  glyphBox->setRadius(Style::radiusMd * scale);
  m_glyphBox = glyphBox.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("media-play");
  glyph->setGlyphSize(Style::fontSizeBody * scale);
  glyph->setColor(palette.onSurface);
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
        m_inputValueLabel->setText(val.empty() ? "" : val);
      }
    });

    auto row = makeRow();
    row->addChild(makeRowLabel("Input", kRowLabelWidth));
    row->addChild(std::move(input));
    row->addChild(std::move(valueLabel));
    container->addChild(std::move(row));
  }

  m_root = std::move(container);

  // Propagate animation manager to all controls in the tree
  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  // Start spinner after animation manager is propagated
  if (m_spinner != nullptr) {
    m_spinner->start();
  }

  if (m_headerLabel != nullptr) {
    m_headerLabel->measure(renderer);
  }
}

void TestPanel::layout(Renderer& renderer, float /*width*/, float /*height*/) {
  if (m_container == nullptr) {
    return;
  }
  m_container->layout(renderer);
  if (m_glyph != nullptr && m_glyphBox != nullptr) {
    m_glyph->measure(renderer);
    m_glyph->setPosition(std::round((m_glyphBox->width() - m_glyph->width()) * 0.5f),
                        std::round((m_glyphBox->height() - m_glyph->height()) * 0.5f));
  }
}

void TestPanel::update(Renderer& /*renderer*/) {}

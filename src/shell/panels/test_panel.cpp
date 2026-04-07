#include "shell/panels/test_panel.h"

#include "render/scene/input_area.h"
#include "ui/controls/flex.h"
#include "ui/controls/button.h"
#include "ui/controls/select.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/controls/slider.h"
#include "ui/controls/input.h"
#include "ui/controls/spinner.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>
#include <string>

void TestPanel::create(Renderer& renderer) {
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setGap(Style::spaceMd);
  container->setAlign(FlexAlign::Start);

  auto header = std::make_unique<Label>();
  header->setText("Test Controls");
  header->setFontSize(Style::fontSizeTitle);
  header->setColor(palette.primary);
  m_headerLabel = header.get();
  container->addChild(std::move(header));

  constexpr float kRowLabelWidth = 100.0f;

  auto makeRow = []() {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setGap(Style::spaceMd);
    row->setAlign(FlexAlign::Center);
    return row;
  };

  auto makeRowLabel = [](const char* text, float minWidth) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setMinWidth(minWidth);
    return label;
  };

  auto button = std::make_unique<Button>();
  button->setText("Hello");
  button->setVariant(ButtonVariant::Default);
  button->setOnClick([]() {});
  m_button = button.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button", kRowLabelWidth));
    row->addChild(std::move(button));
    container->addChild(std::move(row));
  }

  auto glyphButton = std::make_unique<Button>();
  glyphButton->setText("Settings");
  glyphButton->setGlyph("settings");
  glyphButton->setVariant(ButtonVariant::Default);
  glyphButton->setOnClick([]() {});
  m_glyphButton = glyphButton.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button w/ icon", kRowLabelWidth));
    row->addChild(std::move(glyphButton));
    container->addChild(std::move(row));
  }

  auto select = std::make_unique<Select>();
  select->setSize(220.0f, 0.0f);
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

  auto slider = std::make_unique<Slider>();
  slider->setRange(0.0f, 100.0f);
  slider->setStep(1.0f);
  slider->setValue(50.0f);
  slider->setSize(180.0f, 0.0f);
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
    m_sliderValueLabel = valueLabel.get();
    row->addChild(std::move(valueLabel));

    container->addChild(std::move(row));
  }

  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    m_toggle->setChecked(!m_toggle->checked());
  });

  auto toggle = std::make_unique<Toggle>();
  toggle->setToggleSize(ToggleSize::Medium);
  toggle->setChecked(false);
  m_toggle = toggle.get();
  area->addChild(std::move(toggle));

  m_container = container.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Toggle", kRowLabelWidth));
    row->addChild(std::move(area));
    container->addChild(std::move(row));
  }

  {
    auto options = std::make_unique<Flex>();
    options->setDirection(FlexDirection::Horizontal);
    options->setAlign(FlexAlign::Center);
    options->setGap(Style::spaceMd);

    auto optionA = std::make_unique<Flex>();
    optionA->setDirection(FlexDirection::Horizontal);
    optionA->setAlign(FlexAlign::Center);
    optionA->setGap(Style::spaceXs);

    auto radioA = std::make_unique<RadioButton>();
    radioA->setChecked(true);
    m_radioA = radioA.get();

    auto labelA = std::make_unique<Label>();
    labelA->setText("Option A");

    optionA->addChild(std::move(radioA));
    optionA->addChild(std::move(labelA));

    auto optionB = std::make_unique<Flex>();
    optionB->setDirection(FlexDirection::Horizontal);
    optionB->setAlign(FlexAlign::Center);
    optionB->setGap(Style::spaceXs);

    auto radioB = std::make_unique<RadioButton>();
    m_radioB = radioB.get();

    auto labelB = std::make_unique<Label>();
    labelB->setText("Option B");

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

  {
    auto spinner = std::make_unique<Spinner>();
    m_spinner = spinner.get();
    auto row = makeRow();
    row->addChild(makeRowLabel("Spinner", kRowLabelWidth));
    row->addChild(std::move(spinner));
    container->addChild(std::move(row));
  }

  {
    auto input = std::make_unique<Input>();
    input->setPlaceholder("Type something...");
    input->setSize(220.0f, 0.0f);
    m_input = input.get();

    auto valueLabel = std::make_unique<Label>();
    valueLabel->setCaptionStyle();
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
  if (m_headerLabel != nullptr) {
    m_headerLabel->measure(renderer);
  }
  if (m_sliderValueLabel != nullptr) {
    m_sliderValueLabel->measure(renderer);
  }
  if (m_button != nullptr) {
    m_button->layout(renderer);
    m_button->updateInputArea();
  }
  if (m_select != nullptr) {
    m_select->layout(renderer);
  }
  if (m_glyphButton != nullptr) {
    m_glyphButton->layout(renderer);
  }
  if (m_slider != nullptr) {
    m_slider->layout(renderer);
  }
  if (m_toggle != nullptr) {
    m_toggle->layout(renderer);
  }
  if (m_radioA != nullptr) {
    m_radioA->layout(renderer);
  }
  if (m_radioB != nullptr) {
    m_radioB->layout(renderer);
  }
  // Size the InputArea to match the toggle
  if (m_toggle != nullptr && m_toggle->parent() != nullptr) {
    m_toggle->parent()->setSize(m_toggle->width(), m_toggle->height());
  }
  if (m_input != nullptr) {
    m_input->layout(renderer);
  }
  if (m_inputValueLabel != nullptr) {
    m_inputValueLabel->measure(renderer);
  }
  m_container->layout(renderer);
}

void TestPanel::update(Renderer& /*renderer*/) {}

#include "shell/panels/TestPanelContent.h"

#include "render/scene/InputArea.h"
#include "ui/controls/Box.h"
#include "ui/controls/Button.h"
#include "ui/controls/Select.h"
#include "ui/controls/Label.h"
#include "ui/controls/Slider.h"
#include "ui/controls/Spinner.h"
#include "ui/controls/Toggle.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <cmath>
#include <memory>
#include <string>

void TestPanelContent::create(Renderer& renderer) {
  auto container = std::make_unique<Box>();
  container->setDirection(BoxDirection::Vertical);
  container->setGap(Style::spaceMd);
  container->setAlign(BoxAlign::Start);

  auto header = std::make_unique<Label>();
  header->setText("Test Controls");
  header->setFontSize(Style::fontSizeTitle);
  header->setColor(palette.primary);
  m_headerLabel = header.get();
  container->addChild(std::move(header));

  constexpr float kRowLabelWidth = 100.0f;

  auto makeRow = []() {
    auto row = std::make_unique<Box>();
    row->setDirection(BoxDirection::Horizontal);
    row->setGap(Style::spaceMd);
    row->setAlign(BoxAlign::Center);
    return row;
  };

  auto makeRowLabel = [](const char* text, float minWidth) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setMinWidth(minWidth);
    return label;
  };

  auto button = std::make_unique<Button>();
  button->setText("Button");
  button->setVariant(ButtonVariant::Default);
  button->setOnClick([]() {});
  m_button = button.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button", kRowLabelWidth));
    row->addChild(std::move(button));
    container->addChild(std::move(row));
  }

  auto iconButton = std::make_unique<Button>();
  iconButton->setText("Settings");
  iconButton->setIcon("settings");
  iconButton->setVariant(ButtonVariant::Default);
  iconButton->setOnClick([]() {});
  m_iconButton = iconButton.get();
  {
    auto row = makeRow();
    row->addChild(makeRowLabel("Button w/ icon", kRowLabelWidth));
    row->addChild(std::move(iconButton));
    container->addChild(std::move(row));
  }

  auto select = std::make_unique<Select>();
  select->setSize(220.0f, 0.0f);
  select->setOptions({"Balanced", "Performance", "Power Saver"});
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
  toggle->setAnimationManager(m_animations);
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
    auto spinner = std::make_unique<Spinner>();
    spinner->setAnimationManager(m_animations);
    spinner->start();
    m_spinner = spinner.get();
    auto row = makeRow();
    row->addChild(makeRowLabel("Spinner", kRowLabelWidth));
    row->addChild(std::move(spinner));
    container->addChild(std::move(row));
  }

  m_root = std::move(container);

  if (m_headerLabel != nullptr) {
    m_headerLabel->measure(renderer);
  }
}

void TestPanelContent::layout(Renderer& renderer, float /*width*/, float /*height*/) {
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
  if (m_iconButton != nullptr) {
    m_iconButton->layout(renderer);
  }
  if (m_slider != nullptr) {
    m_slider->layout(renderer);
  }
  if (m_toggle != nullptr) {
    m_toggle->layout(renderer);
  }
  // Size the InputArea to match the toggle
  if (m_toggle != nullptr && m_toggle->parent() != nullptr) {
    m_toggle->parent()->setSize(m_toggle->width(), m_toggle->height());
  }
  m_container->layout(renderer);
}

void TestPanelContent::update(Renderer& /*renderer*/) {}

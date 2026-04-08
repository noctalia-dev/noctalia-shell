#include "shell/control_center/audio_tab.h"

#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/slider.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <utility>
#include <vector>

using namespace control_center;

namespace {

constexpr float kDevicesColumnGrow = 3.0f;
constexpr float kVolumeColumnGrow = 2.0f;
constexpr float kColumnMinWidth = Style::controlHeightLg * 8;
constexpr float kValueLabelWidth = Style::controlHeightLg + Style::spaceLg;

class AudioDeviceRow : public Flex {
public:
  explicit AudioDeviceRow(std::function<void()> onSelect) : m_onSelect(std::move(onSelect)) {
    setDirection(FlexDirection::Horizontal);
    setAlign(FlexAlign::Center);
    setGap(Style::spaceSm);
    setPadding(Style::spaceSm, Style::spaceMd);
    setMinHeight(Style::controlHeightLg);
    setRadius(Style::radiusMd);
    setBackground(palette.surface);
    setBorderWidth(0.0f);
    setSoftness(1.0f);

    auto radio = std::make_unique<RadioButton>();
    radio->setOnChange([this](bool /*checked*/) {
      if (m_onSelect) {
        m_onSelect();
      }
    });
    m_radio = static_cast<RadioButton*>(addChild(std::move(radio)));

    auto textColumn = std::make_unique<Flex>();
    textColumn->setDirection(FlexDirection::Vertical);
    textColumn->setAlign(FlexAlign::Start);
    textColumn->setGap(0.0f);
    textColumn->setFlexGrow(1.0f);
    m_textColumn = static_cast<Flex*>(addChild(std::move(textColumn)));

    auto title = std::make_unique<Label>();
    title->setBold(true);
    title->setFontSize(Style::fontSizeBody);
    title->setColor(palette.onSurface);
    m_title = title.get();
    m_textColumn->addChild(std::move(title));

    auto detail = std::make_unique<Label>();
    detail->setCaptionStyle();
    detail->setColor(palette.onSurfaceVariant);
    detail->setVisible(false);
    m_detail = detail.get();
    m_textColumn->addChild(std::move(detail));

    auto area = std::make_unique<InputArea>();
    area->setPropagateEvents(true);
    area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyState(); });
    area->setOnLeave([this]() { applyState(); });
    area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyState(); });
    area->setOnClick([this](const InputArea::PointerData& /*data*/) {
      if (m_onSelect) {
        m_onSelect();
      }
    });
    m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

    applyState();
  }

  void setDevice(const AudioNode& node) {
    m_radio->setChecked(node.isDefault);

    const std::string title = !node.description.empty() ? node.description : node.name;
    const bool showDetail = !node.description.empty() && !node.name.empty() && node.description != node.name;

    if (m_title != nullptr) {
      m_title->setText(title);
    }
    if (m_detail != nullptr) {
      m_detail->setText(showDetail ? node.name : "");
      m_detail->setVisible(showDetail);
    }
  }

  void layout(Renderer& renderer) override {
    if (m_radio == nullptr || m_title == nullptr || m_inputArea == nullptr) {
      return;
    }

    m_radio->layout(renderer);

    const float textMaxWidth =
        std::max(0.0f, width() - paddingLeft() - paddingRight() - gap() - m_radio->width());
    m_title->setMaxWidth(textMaxWidth);
    if (m_detail != nullptr) {
      m_detail->setMaxWidth(textMaxWidth);
    }

    m_inputArea->setVisible(false);
    Flex::layout(renderer);
    m_inputArea->setVisible(true);
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());

    applyState();
  }

private:
  void applyState() {
    if (pressed()) {
      setBackground(palette.primary);
      setBorderColor(palette.primary);
      setBorderWidth(Style::borderWidth);
      if (m_title != nullptr) {
        m_title->setColor(palette.onPrimary);
      }
      if (m_detail != nullptr) {
        m_detail->setColor(palette.onPrimary);
      }
      return;
    }

    setBackground(palette.surface);
    setBorderColor(hovered() ? palette.primary : palette.surface);
    setBorderWidth(hovered() ? Style::borderWidth : 0.0f);
    if (m_title != nullptr) {
      m_title->setColor(palette.onSurface);
    }
    if (m_detail != nullptr) {
      m_detail->setColor(palette.onSurfaceVariant);
    }
  }

  [[nodiscard]] bool hovered() const noexcept { return m_inputArea != nullptr && m_inputArea->hovered(); }
  [[nodiscard]] bool pressed() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

  std::function<void()> m_onSelect;
  RadioButton* m_radio = nullptr;
  Flex* m_textColumn = nullptr;
  Label* m_title = nullptr;
  Label* m_detail = nullptr;
  InputArea* m_inputArea = nullptr;
};

std::vector<AudioNode> sortedDevices(const std::vector<AudioNode>& devices) {
  std::vector<AudioNode> sorted = devices;
  std::ranges::sort(sorted, [](const AudioNode& a, const AudioNode& b) {
    const std::string& left = !a.description.empty() ? a.description : a.name;
    const std::string& right = !b.description.empty() ? b.description : b.name;
    if (left != right) {
      return left < right;
    }
    return a.id < b.id;
  });
  return sorted;
}

void addSubtitle(Flex& parent, const std::string& text, float scale) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setCaptionStyle();
  label->setFontSize(Style::fontSizeCaption * scale);
  label->setColor(palette.onSurfaceVariant);
  parent.addChild(std::move(label));
}

void addEmptyState(Flex& parent, const std::string& title, const std::string& body, float scale) {
  auto card = std::make_unique<Flex>();
  card->setDirection(FlexDirection::Vertical);
  card->setAlign(FlexAlign::Start);
  card->setGap(Style::spaceXs * scale);
  card->setPadding(Style::spaceMd * scale);
  card->setRadius(Style::radiusMd * scale);
  card->setBackground(palette.surface);
  card->setBorderWidth(0.0f);

  auto titleLabel = std::make_unique<Label>();
  titleLabel->setText(title);
  titleLabel->setBold(true);
  titleLabel->setFontSize(Style::fontSizeBody * scale);
  titleLabel->setColor(palette.onSurface);
  card->addChild(std::move(titleLabel));

  auto bodyLabel = std::make_unique<Label>();
  bodyLabel->setText(body);
  bodyLabel->setCaptionStyle();
  bodyLabel->setFontSize(Style::fontSizeCaption * scale);
  bodyLabel->setColor(palette.onSurfaceVariant);
  card->addChild(std::move(bodyLabel));

  parent.addChild(std::move(card));
}

const AudioNode* findAudioNodeById(const std::vector<AudioNode>& devices, std::uint32_t id) {
  const auto it = std::ranges::find(devices, id, &AudioNode::id);
  return it != devices.end() ? &(*it) : nullptr;
}

} // namespace

AudioTab::AudioTab(PipeWireService* audio) : m_audio(audio) {}

std::unique_ptr<Flex> AudioTab::build(Renderer& /*renderer*/) {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto deviceColumn = std::make_unique<Flex>();
  deviceColumn->setDirection(FlexDirection::Vertical);
  deviceColumn->setAlign(FlexAlign::Stretch);
  deviceColumn->setGap(Style::spaceSm * scale);
  deviceColumn->setFlexGrow(kDevicesColumnGrow);
  deviceColumn->setMinWidth(kColumnMinWidth * scale);
  m_deviceColumn = deviceColumn.get();

  auto outputCard = std::make_unique<Flex>();
  applyCard(*outputCard, scale);
  outputCard->setAlign(FlexAlign::Stretch);
  outputCard->setGap(Style::spaceSm * scale);
  outputCard->setFlexGrow(1.0f);
  m_outputCard = outputCard.get();
  addTitle(*outputCard, "Outputs", scale);
  addSubtitle(*outputCard, "Default playback device", scale);

  auto outputScroll = std::make_unique<ScrollView>();
  outputScroll->setFlexGrow(1.0f);
  outputScroll->setScrollbarVisible(true);
  outputScroll->setViewportPaddingH(0.0f);
  outputScroll->setViewportPaddingV(0.0f);
  outputScroll->setBackgroundStyle(rgba(0, 0, 0, 0), rgba(0, 0, 0, 0), 0.0f);
  m_outputScroll = outputScroll.get();
  m_outputList = outputScroll->content();
  m_outputList->setDirection(FlexDirection::Vertical);
  m_outputList->setAlign(FlexAlign::Stretch);
  m_outputList->setGap(Style::spaceSm * scale);
  outputCard->addChild(std::move(outputScroll));
  deviceColumn->addChild(std::move(outputCard));

  auto inputCard = std::make_unique<Flex>();
  applyCard(*inputCard, scale);
  inputCard->setAlign(FlexAlign::Stretch);
  inputCard->setGap(Style::spaceSm * scale);
  inputCard->setFlexGrow(1.0f);
  m_inputCard = inputCard.get();
  addTitle(*inputCard, "Inputs", scale);
  addSubtitle(*inputCard, "Default recording device", scale);

  auto inputScroll = std::make_unique<ScrollView>();
  inputScroll->setFlexGrow(1.0f);
  inputScroll->setScrollbarVisible(true);
  inputScroll->setViewportPaddingH(0.0f);
  inputScroll->setViewportPaddingV(0.0f);
  inputScroll->setBackgroundStyle(rgba(0, 0, 0, 0), rgba(0, 0, 0, 0), 0.0f);
  m_inputScroll = inputScroll.get();
  m_inputList = inputScroll->content();
  m_inputList->setDirection(FlexDirection::Vertical);
  m_inputList->setAlign(FlexAlign::Stretch);
  m_inputList->setGap(Style::spaceSm * scale);
  inputCard->addChild(std::move(inputScroll));
  deviceColumn->addChild(std::move(inputCard));

  auto volumeColumn = std::make_unique<Flex>();
  volumeColumn->setDirection(FlexDirection::Vertical);
  volumeColumn->setAlign(FlexAlign::Stretch);
  volumeColumn->setGap(Style::spaceSm * scale);
  volumeColumn->setFlexGrow(kVolumeColumnGrow);
  volumeColumn->setMinWidth(kColumnMinWidth * scale);
  m_volumeColumn = volumeColumn.get();

  auto outputVolumeCard = std::make_unique<Flex>();
  applyCard(*outputVolumeCard, scale);
  outputVolumeCard->setAlign(FlexAlign::Stretch);
  outputVolumeCard->setGap(Style::spaceSm * scale);
  outputVolumeCard->setFlexGrow(1.0f);
  m_outputVolumeCard = outputVolumeCard.get();
  addTitle(*outputVolumeCard, "Speaker Volume", scale);

  auto outputDeviceLabel = std::make_unique<Label>();
  outputDeviceLabel->setText("No output device selected");
  outputDeviceLabel->setCaptionStyle();
  outputDeviceLabel->setFontSize(Style::fontSizeCaption * scale);
  outputDeviceLabel->setColor(palette.onSurfaceVariant);
  m_outputDeviceLabel = outputDeviceLabel.get();
  outputVolumeCard->addChild(std::move(outputDeviceLabel));

  auto outputRow = std::make_unique<Flex>();
  outputRow->setDirection(FlexDirection::Horizontal);
  outputRow->setAlign(FlexAlign::Center);
  outputRow->setGap(Style::spaceSm * scale);

  auto outputSlider = std::make_unique<Slider>();
  outputSlider->setRange(0.0f, 150.0f);
  outputSlider->setStep(1.0f);
  outputSlider->setFlexGrow(1.0f);
  outputSlider->setControlHeight(Style::controlHeight * scale);
  outputSlider->setTrackHeight(6.0f * scale);
  outputSlider->setThumbSize(16.0f * scale);
  outputSlider->setOnValueChanged([this](float value) {
    if (m_syncingOutputSlider || m_audio == nullptr) {
      return;
    }
    const std::uint32_t sinkId = m_audio->state().defaultSinkId;
    if (sinkId != 0) {
      m_audio->setSinkVolume(sinkId, value / 100.0f);
    }
    if (m_outputValue != nullptr) {
      m_outputValue->setText(std::to_string(static_cast<int>(std::round(value))) + "%");
    }
  });
  m_outputSlider = outputSlider.get();
  outputRow->addChild(std::move(outputSlider));

  auto outputValue = std::make_unique<Label>();
  outputValue->setText("0%");
  outputValue->setBold(true);
  outputValue->setFontSize(Style::fontSizeBody * scale);
  outputValue->setMinWidth(kValueLabelWidth * scale);
  m_outputValue = outputValue.get();
  outputRow->addChild(std::move(outputValue));
  outputVolumeCard->addChild(std::move(outputRow));
  volumeColumn->addChild(std::move(outputVolumeCard));

  auto inputVolumeCard = std::make_unique<Flex>();
  applyCard(*inputVolumeCard, scale);
  inputVolumeCard->setAlign(FlexAlign::Stretch);
  inputVolumeCard->setGap(Style::spaceSm * scale);
  inputVolumeCard->setFlexGrow(1.0f);
  m_inputVolumeCard = inputVolumeCard.get();
  addTitle(*inputVolumeCard, "Microphone Volume", scale);

  auto inputDeviceLabel = std::make_unique<Label>();
  inputDeviceLabel->setText("No input device selected");
  inputDeviceLabel->setCaptionStyle();
  inputDeviceLabel->setFontSize(Style::fontSizeCaption * scale);
  inputDeviceLabel->setColor(palette.onSurfaceVariant);
  m_inputDeviceLabel = inputDeviceLabel.get();
  inputVolumeCard->addChild(std::move(inputDeviceLabel));

  auto inputRow = std::make_unique<Flex>();
  inputRow->setDirection(FlexDirection::Horizontal);
  inputRow->setAlign(FlexAlign::Center);
  inputRow->setGap(Style::spaceSm * scale);

  auto inputSlider = std::make_unique<Slider>();
  inputSlider->setRange(0.0f, 150.0f);
  inputSlider->setStep(1.0f);
  inputSlider->setFlexGrow(1.0f);
  inputSlider->setControlHeight(Style::controlHeight * scale);
  inputSlider->setTrackHeight(6.0f * scale);
  inputSlider->setThumbSize(16.0f * scale);
  inputSlider->setOnValueChanged([this](float value) {
    if (m_syncingInputSlider || m_audio == nullptr) {
      return;
    }
    const std::uint32_t sourceId = m_audio->state().defaultSourceId;
    if (sourceId != 0) {
      m_audio->setSourceVolume(sourceId, value / 100.0f);
    }
    if (m_inputValue != nullptr) {
      m_inputValue->setText(std::to_string(static_cast<int>(std::round(value))) + "%");
    }
  });
  m_inputSlider = inputSlider.get();
  inputRow->addChild(std::move(inputSlider));

  auto inputValue = std::make_unique<Label>();
  inputValue->setText("0%");
  inputValue->setBold(true);
  inputValue->setFontSize(Style::fontSizeBody * scale);
  inputValue->setMinWidth(kValueLabelWidth * scale);
  m_inputValue = inputValue.get();
  inputRow->addChild(std::move(inputValue));
  inputVolumeCard->addChild(std::move(inputRow));
  volumeColumn->addChild(std::move(inputVolumeCard));

  tab->addChild(std::move(deviceColumn));
  tab->addChild(std::move(volumeColumn));
  return tab;
}

void AudioTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  if (m_outputDeviceLabel != nullptr && m_outputVolumeCard != nullptr) {
    m_outputDeviceLabel->setMaxWidth(
        std::max(0.0f, m_outputVolumeCard->width() - m_outputVolumeCard->paddingLeft() - m_outputVolumeCard->paddingRight()));
  }
  if (m_inputDeviceLabel != nullptr && m_inputVolumeCard != nullptr) {
    m_inputDeviceLabel->setMaxWidth(
        std::max(0.0f, m_inputVolumeCard->width() - m_inputVolumeCard->paddingLeft() - m_inputVolumeCard->paddingRight()));
  }

  rebuildLists(renderer);
  m_rootLayout->layout(renderer);
}

void AudioTab::update(Renderer& renderer) {
  rebuildLists(renderer);

  const AudioState* state = m_audio != nullptr ? &m_audio->state() : nullptr;
  const AudioNode* sink = state != nullptr ? findAudioNodeById(state->sinks, state->defaultSinkId) : nullptr;
  const AudioNode* source = state != nullptr ? findAudioNodeById(state->sources, state->defaultSourceId) : nullptr;

  if (m_outputDeviceLabel != nullptr) {
    m_outputDeviceLabel->setText(
        sink != nullptr ? (!sink->description.empty() ? sink->description : sink->name) : "No output device selected");
  }
  if (m_inputDeviceLabel != nullptr) {
    m_inputDeviceLabel->setText(
        source != nullptr ? (!source->description.empty() ? source->description : source->name) : "No input device selected");
  }

  const float sinkVolume = sink != nullptr ? sink->volume * 100.0f : 0.0f;
  const float sourceVolume = source != nullptr ? source->volume * 100.0f : 0.0f;

  if (m_outputSlider != nullptr) {
    m_outputSlider->setEnabled(sink != nullptr);
    if (!m_outputSlider->dragging() && std::abs(sinkVolume - m_lastSinkVolume) >= 0.5f) {
      m_syncingOutputSlider = true;
      m_outputSlider->setValue(sinkVolume);
      m_syncingOutputSlider = false;
      if (m_outputValue != nullptr) {
        m_outputValue->setText(std::to_string(static_cast<int>(std::round(sinkVolume))) + "%");
      }
      m_lastSinkVolume = sinkVolume;
    }
  }

  if (m_inputSlider != nullptr) {
    m_inputSlider->setEnabled(source != nullptr);
    if (!m_inputSlider->dragging() && std::abs(sourceVolume - m_lastSourceVolume) >= 0.5f) {
      m_syncingInputSlider = true;
      m_inputSlider->setValue(sourceVolume);
      m_syncingInputSlider = false;
      if (m_inputValue != nullptr) {
        m_inputValue->setText(std::to_string(static_cast<int>(std::round(sourceVolume))) + "%");
      }
      m_lastSourceVolume = sourceVolume;
    }
  }
}

void AudioTab::onClose() {
  m_rootLayout = nullptr;
  m_deviceColumn = nullptr;
  m_outputCard = nullptr;
  m_inputCard = nullptr;
  m_outputScroll = nullptr;
  m_inputScroll = nullptr;
  m_outputList = nullptr;
  m_inputList = nullptr;
  m_volumeColumn = nullptr;
  m_outputVolumeCard = nullptr;
  m_inputVolumeCard = nullptr;
  m_outputDeviceLabel = nullptr;
  m_inputDeviceLabel = nullptr;
  m_outputSlider = nullptr;
  m_outputValue = nullptr;
  m_inputSlider = nullptr;
  m_inputValue = nullptr;
  m_lastOutputWidth = -1.0f;
  m_lastInputWidth = -1.0f;
  m_lastChangeSerial = 0;
  m_lastSinkVolume = -1.0f;
  m_lastSourceVolume = -1.0f;
}

void AudioTab::rebuildLists(Renderer& renderer) {
  if (m_outputList == nullptr || m_inputList == nullptr || m_outputScroll == nullptr || m_inputScroll == nullptr) {
    return;
  }

  const float outputWidth = m_outputScroll->contentViewportWidth();
  const float inputWidth = m_inputScroll->contentViewportWidth();
  const std::uint64_t changeSerial = m_audio != nullptr ? m_audio->changeSerial() : 0;

  if (outputWidth <= 0.0f || inputWidth <= 0.0f) {
    return;
  }
  if (outputWidth == m_lastOutputWidth && inputWidth == m_lastInputWidth && changeSerial == m_lastChangeSerial) {
    return;
  }

  while (!m_outputList->children().empty()) {
    m_outputList->removeChild(m_outputList->children().front().get());
  }
  while (!m_inputList->children().empty()) {
    m_inputList->removeChild(m_inputList->children().front().get());
  }

  const float scale = contentScale();
  if (m_audio == nullptr) {
    addEmptyState(*m_outputList, "Audio unavailable", "PipeWire is not active.", scale);
    addEmptyState(*m_inputList, "Audio unavailable", "PipeWire is not active.", scale);
    m_lastOutputWidth = outputWidth;
    m_lastInputWidth = inputWidth;
    m_lastChangeSerial = changeSerial;
    return;
  }

  const AudioState& state = m_audio->state();
  if (state.sinks.empty()) {
    addEmptyState(*m_outputList, "No output devices", "No playback sinks are currently available.", scale);
  } else {
    for (const auto& sink : sortedDevices(state.sinks)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = sink.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSink(id);
        }
        PanelManager::instance().refresh();
      });
      row->setDevice(sink);
      m_outputList->addChild(std::move(row));
    }
  }

  if (state.sources.empty()) {
    addEmptyState(*m_inputList, "No input devices", "No recording sources are currently available.", scale);
  } else {
    for (const auto& source : sortedDevices(state.sources)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = source.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSource(id);
        }
        PanelManager::instance().refresh();
      });
      row->setDevice(source);
      m_inputList->addChild(std::move(row));
    }
  }

  m_outputList->layout(renderer);
  m_inputList->layout(renderer);

  m_lastOutputWidth = outputWidth;
  m_lastInputWidth = inputWidth;
  m_lastChangeSerial = changeSerial;
}

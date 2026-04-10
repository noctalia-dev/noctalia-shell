#include "shell/control_center/audio_tab.h"

#include "config/config_service.h"
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
constexpr float kValueLabelWidth = Style::controlHeightLg + Style::spaceLg;
constexpr auto kVolumeDebounceInterval = std::chrono::milliseconds(45);
constexpr float kVolumeSyncEpsilon = 0.005f;           // 0.5%
constexpr auto kVolumeStateHoldoff = std::chrono::milliseconds(180);

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

    m_detail = nullptr; // Remove detail label (subtext)

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
    // Removed unused variable 'showDetail'

    if (m_title != nullptr) {
      m_title->setText(title);
    }
    // Removed subtext (detail) handling
  }

  void layout(Renderer& renderer) override {
    if (m_radio == nullptr || m_title == nullptr || m_inputArea == nullptr) {
      return;
    }

    m_radio->layout(renderer);

    const float textMaxWidth =
        std::max(0.0f, width() - paddingLeft() - paddingRight() - gap() - m_radio->width());
    m_title->setMaxWidth(textMaxWidth);
    // Removed subtext (detail) max width

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
      return;
    }

    setBackground(palette.surface);
    setBorderColor(hovered() ? palette.primary : palette.surface);
    setBorderWidth(hovered() ? Style::borderWidth : 0.0f);
    if (m_title != nullptr) {
      m_title->setColor(palette.onSurface);
    }
    // Removed subtext (detail) color handling
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

std::string deviceListKey(const std::vector<AudioNode>& devices) {
  std::string key;
  for (const auto& device : devices) {
    key += std::to_string(device.id);
    key.push_back(':');
    key += device.isDefault ? '1' : '0';
    key.push_back(':');
    key += device.name;
    key.push_back(':');
    key += device.description;
    key.push_back('\n');
  }
  return key;
}

std::string widestPercentLabel(float sliderMaxValue) {
  const std::size_t digits =
      std::to_string(static_cast<int>(std::round(std::max(0.0f, sliderMaxValue) * 100.0f))).size();
  return std::string(std::max<std::size_t>(1, digits), '8') + "%";
}

} // namespace

AudioTab::AudioTab(PipeWireService* audio, ConfigService* config) : m_audio(audio), m_config(config) {}

bool AudioTab::dragging() const noexcept {
  return (m_outputSlider != nullptr && m_outputSlider->dragging()) || (m_inputSlider != nullptr && m_inputSlider->dragging());
}

std::unique_ptr<Flex> AudioTab::create() {
  const float scale = contentScale();
  const float sliderMax = sliderMaxPercent() / 100.0f;

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceSm * scale);
  m_rootLayout = tab.get();

  auto deviceColumn = std::make_unique<Flex>();
  deviceColumn->setDirection(FlexDirection::Vertical);
  deviceColumn->setAlign(FlexAlign::Stretch);
  deviceColumn->setGap(Style::spaceSm * scale);
  deviceColumn->setFlexGrow(kDevicesColumnGrow);
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
  outputSlider->setRange(0.0f, sliderMax);
  outputSlider->setStep(0.01f);
  outputSlider->setFlexGrow(1.0f);
  outputSlider->setControlHeight(Style::controlHeight * scale);
  outputSlider->setTrackHeight(6.0f * scale);
  outputSlider->setThumbSize(16.0f * scale);
  outputSlider->setOnValueChanged([this](float value) {
    if (m_syncingOutputSlider || m_audio == nullptr) {
      return;
    }
    queueSinkVolume(value);
    if (m_outputSlider != nullptr && m_outputSlider->dragging()) {
      // Restart one-shot debounce while dragging; send latest settled value.
      m_sinkVolumeDebounceTimer.start(kVolumeDebounceInterval, [this]() { flushPendingVolumes(); });
    } else {
      m_sinkVolumeDebounceTimer.stop();
      flushPendingVolumes();
    }
    if (m_outputValue != nullptr) {
      m_outputValue->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
    }
  });
  outputSlider->setOnDragEnd([this]() {
    m_sinkVolumeDebounceTimer.stop();
    flushPendingVolumes();
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
  inputSlider->setRange(0.0f, sliderMax);
  inputSlider->setStep(0.01f);
  inputSlider->setFlexGrow(1.0f);
  inputSlider->setControlHeight(Style::controlHeight * scale);
  inputSlider->setTrackHeight(6.0f * scale);
  inputSlider->setThumbSize(16.0f * scale);
  inputSlider->setOnValueChanged([this](float value) {
    if (m_syncingInputSlider || m_audio == nullptr) {
      return;
    }
    queueSourceVolume(value);
    if (m_inputSlider != nullptr && m_inputSlider->dragging()) {
      // Restart one-shot debounce while dragging; send latest settled value.
      m_sourceVolumeDebounceTimer.start(kVolumeDebounceInterval, [this]() { flushPendingVolumes(); });
    } else {
      m_sourceVolumeDebounceTimer.stop();
      flushPendingVolumes();
    }
    if (m_inputValue != nullptr) {
      m_inputValue->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
    }
  });
  inputSlider->setOnDragEnd([this]() {
    m_sourceVolumeDebounceTimer.stop();
    flushPendingVolumes();
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

  syncValueLabelWidths(renderer);
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
  m_rootLayout->layout(renderer);

  rebuildLists(renderer);
}

void AudioTab::update(Renderer& renderer) {
  rebuildLists(renderer);
  syncValueLabelWidths(renderer);

  const float sliderMax = sliderMaxPercent() / 100.0f;
  if (m_outputSlider != nullptr) {
    m_syncingOutputSlider = true;
    m_outputSlider->setRange(0.0f, sliderMax);
    m_syncingOutputSlider = false;
  }
  if (m_inputSlider != nullptr) {
    m_syncingInputSlider = true;
    m_inputSlider->setRange(0.0f, sliderMax);
    m_syncingInputSlider = false;
  }

  const AudioNode* sink = m_audio != nullptr ? m_audio->defaultSink() : nullptr;
  const AudioNode* source = m_audio != nullptr ? m_audio->defaultSource() : nullptr;
  const auto now = std::chrono::steady_clock::now();
  const bool outputDragging = m_outputSlider != nullptr && m_outputSlider->dragging();
  const bool inputDragging = m_inputSlider != nullptr && m_inputSlider->dragging();

  if (m_outputDeviceLabel != nullptr) {
    m_outputDeviceLabel->setText(
        sink != nullptr ? (!sink->description.empty() ? sink->description : sink->name) : "No output device selected");
  }
  if (m_inputDeviceLabel != nullptr) {
    m_inputDeviceLabel->setText(
        source != nullptr ? (!source->description.empty() ? source->description : source->name) : "No input device selected");
  }

  const float sinkVolume = sink != nullptr ? sink->volume : 0.0f;
  const float sourceVolume = source != nullptr ? source->volume : 0.0f;
  const bool showPendingSink = sink != nullptr && m_pendingSinkVolume >= 0.0f && m_pendingSinkId == sink->id;
  const bool showPendingSource = source != nullptr && m_pendingSourceVolume >= 0.0f && m_pendingSourceId == source->id;
  const bool holdSinkState = outputDragging && sink != nullptr && m_lastSentSinkVolume >= 0.0f &&
                             now < m_ignoreSinkStateUntil &&
                             std::abs(sink->volume - m_lastSentSinkVolume) > 0.02f;
  const bool holdSourceState = inputDragging && source != nullptr && m_lastSentSourceVolume >= 0.0f &&
                               now < m_ignoreSourceStateUntil &&
                               std::abs(source->volume - m_lastSentSourceVolume) > 0.02f;
  const float displayedSinkVolume =
      std::clamp(showPendingSink ? m_pendingSinkVolume : (holdSinkState ? m_lastSentSinkVolume : sinkVolume), 0.0f,
                 sliderMax);
  const float displayedSourceVolume =
      std::clamp(showPendingSource ? m_pendingSourceVolume
                                   : (holdSourceState ? m_lastSentSourceVolume : sourceVolume),
                 0.0f, sliderMax);

  if (m_outputSlider != nullptr) {
    m_outputSlider->setEnabled(sink != nullptr);
    if (!m_outputSlider->dragging() && std::abs(displayedSinkVolume - m_lastSinkVolume) >= kVolumeSyncEpsilon) {
      m_syncingOutputSlider = true;
      m_outputSlider->setValue(displayedSinkVolume);
      m_syncingOutputSlider = false;
      if (m_outputValue != nullptr) {
        m_outputValue->setText(std::to_string(static_cast<int>(std::round(displayedSinkVolume * 100.0f))) + "%");
      }
      m_lastSinkVolume = displayedSinkVolume;
    }
  }

  if (m_inputSlider != nullptr) {
    m_inputSlider->setEnabled(source != nullptr);
    if (!m_inputSlider->dragging() && std::abs(displayedSourceVolume - m_lastSourceVolume) >= kVolumeSyncEpsilon) {
      m_syncingInputSlider = true;
      m_inputSlider->setValue(displayedSourceVolume);
      m_syncingInputSlider = false;
      if (m_inputValue != nullptr) {
        m_inputValue->setText(std::to_string(static_cast<int>(std::round(displayedSourceVolume * 100.0f))) + "%");
      }
      m_lastSourceVolume = displayedSourceVolume;
    }
  }
}

void AudioTab::onClose() {
  flushPendingVolumes(true);
  m_sinkVolumeDebounceTimer.stop();
  m_sourceVolumeDebounceTimer.stop();
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
  m_lastOutputListKey.clear();
  m_lastInputListKey.clear();
  m_pendingSinkId = 0;
  m_pendingSourceId = 0;
  m_lastSinkVolume = -1.0f;
  m_lastSourceVolume = -1.0f;
  m_pendingSinkVolume = -1.0f;
  m_pendingSourceVolume = -1.0f;
  m_lastSentSinkVolume = -1.0f;
  m_lastSentSourceVolume = -1.0f;
  m_ignoreSinkStateUntil = {};
  m_ignoreSourceStateUntil = {};
}

void AudioTab::rebuildLists(Renderer& renderer) {
  if (m_outputList == nullptr || m_inputList == nullptr || m_outputScroll == nullptr || m_inputScroll == nullptr) {
    return;
  }

  const float outputWidth = m_outputScroll->contentViewportWidth();
  const float inputWidth = m_inputScroll->contentViewportWidth();

  if (outputWidth <= 0.0f || inputWidth <= 0.0f) {
    return;
  }

  const float scale = contentScale();
  if (m_audio == nullptr) {
    if (outputWidth == m_lastOutputWidth && inputWidth == m_lastInputWidth && m_lastOutputListKey == "unavailable" &&
        m_lastInputListKey == "unavailable") {
      return;
    }
    while (!m_outputList->children().empty()) {
      m_outputList->removeChild(m_outputList->children().front().get());
    }
    while (!m_inputList->children().empty()) {
      m_inputList->removeChild(m_inputList->children().front().get());
    }
    addEmptyState(*m_outputList, "Audio unavailable", "PipeWire is not active.", scale);
    addEmptyState(*m_inputList, "Audio unavailable", "PipeWire is not active.", scale);
    m_lastOutputWidth = outputWidth;
    m_lastInputWidth = inputWidth;
    m_lastOutputListKey = "unavailable";
    m_lastInputListKey = "unavailable";
    return;
  }

  const AudioState& state = m_audio->state();
  const std::string nextOutputListKey = state.sinks.empty() ? "empty" : deviceListKey(state.sinks);
  const std::string nextInputListKey = state.sources.empty() ? "empty" : deviceListKey(state.sources);

  if (outputWidth == m_lastOutputWidth && inputWidth == m_lastInputWidth && nextOutputListKey == m_lastOutputListKey &&
      nextInputListKey == m_lastInputListKey) {
    return;
  }

  while (!m_outputList->children().empty()) {
    m_outputList->removeChild(m_outputList->children().front().get());
  }
  while (!m_inputList->children().empty()) {
    m_inputList->removeChild(m_inputList->children().front().get());
  }

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
  m_lastOutputListKey = nextOutputListKey;
  m_lastInputListKey = nextInputListKey;
}

void AudioTab::syncValueLabelWidths(Renderer& renderer) {
  const std::string sampleLabel = widestPercentLabel(sliderMaxPercent());
  const TextMetrics metrics = renderer.measureText(sampleLabel, Style::fontSizeBody * contentScale(), true);
  const float minWidth = std::round(metrics.width);
  if (m_outputValue != nullptr) {
    m_outputValue->setMinWidth(minWidth);
  }
  if (m_inputValue != nullptr) {
    m_inputValue->setMinWidth(minWidth);
  }
}

float AudioTab::sliderMaxPercent() const {
  return (m_config != nullptr && m_config->config().audio.enableOverdrive) ? 150.0f : 100.0f;
}

void AudioTab::queueSinkVolume(float value) {
  const AudioNode* sink = m_audio != nullptr ? m_audio->defaultSink() : nullptr;
  m_pendingSinkId = sink != nullptr ? sink->id : 0;
  m_pendingSinkVolume = std::clamp(value, 0.0f, sliderMaxPercent() / 100.0f);
}

void AudioTab::queueSourceVolume(float value) {
  const AudioNode* source = m_audio != nullptr ? m_audio->defaultSource() : nullptr;
  m_pendingSourceId = source != nullptr ? source->id : 0;
  m_pendingSourceVolume = std::clamp(value, 0.0f, sliderMaxPercent() / 100.0f);
}

void AudioTab::flushPendingVolumes(bool force) {
  if (m_audio == nullptr) {
    m_sinkVolumeDebounceTimer.stop();
    m_sourceVolumeDebounceTimer.stop();
    m_pendingSinkId = 0;
    m_pendingSourceId = 0;
    m_pendingSinkVolume = -1.0f;
    m_pendingSourceVolume = -1.0f;
    return;
  }

  const float sliderMax = sliderMaxPercent() / 100.0f;
  const bool outputDragging = m_outputSlider != nullptr && m_outputSlider->dragging();
  const bool inputDragging = m_inputSlider != nullptr && m_inputSlider->dragging();

  if (m_pendingSinkVolume >= 0.0f) {
    m_pendingSinkVolume = std::clamp(m_pendingSinkVolume, 0.0f, sliderMax);
  }
  if (m_pendingSourceVolume >= 0.0f) {
    m_pendingSourceVolume = std::clamp(m_pendingSourceVolume, 0.0f, sliderMax);
  }

  if (m_pendingSinkVolume >= 0.0f) {
    const std::uint32_t sinkId = m_pendingSinkId;
    bool shouldSendSink = force;
    if (!shouldSendSink && sinkId != 0) {
      const float delta = std::abs(m_pendingSinkVolume - m_lastSentSinkVolume);
      shouldSendSink = delta >= 0.0001f;
    }
    if (sinkId != 0 && shouldSendSink) {
      m_audio->setSinkVolume(sinkId, m_pendingSinkVolume);
      m_audio->emitVolumePreview(false, sinkId, m_pendingSinkVolume);
      m_lastSentSinkVolume = m_pendingSinkVolume;
      m_ignoreSinkStateUntil = std::chrono::steady_clock::now() + kVolumeStateHoldoff;
    }
    if (force || !outputDragging) {
      m_pendingSinkId = 0;
      m_pendingSinkVolume = -1.0f;
      m_sinkVolumeDebounceTimer.stop();
    }
  }

  if (m_pendingSourceVolume >= 0.0f) {
    const std::uint32_t sourceId = m_pendingSourceId;
    bool shouldSendSource = force;
    if (!shouldSendSource && sourceId != 0) {
      const float delta = std::abs(m_pendingSourceVolume - m_lastSentSourceVolume);
      shouldSendSource = delta >= 0.0001f;
    }
    if (sourceId != 0 && shouldSendSource) {
      m_audio->setSourceVolume(sourceId, m_pendingSourceVolume);
      m_audio->emitVolumePreview(true, sourceId, m_pendingSourceVolume);
      m_lastSentSourceVolume = m_pendingSourceVolume;
      m_ignoreSourceStateUntil = std::chrono::steady_clock::now() + kVolumeStateHoldoff;
    }
    if (force || !inputDragging) {
      m_pendingSourceId = 0;
      m_pendingSourceVolume = -1.0f;
      m_sourceVolumeDebounceTimer.stop();
    }
  }
}

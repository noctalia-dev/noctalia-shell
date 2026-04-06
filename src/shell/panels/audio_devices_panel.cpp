#include "shell/panels/audio_devices_panel.h"

#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

class AudioDeviceRow : public Flex {
public:
  explicit AudioDeviceRow(std::function<void()> onSelect) : m_onSelect(std::move(onSelect)) {
    setDirection(FlexDirection::Horizontal);
    setAlign(FlexAlign::Center);
    setGap(static_cast<float>(Style::spaceSm));
    setPadding(static_cast<float>(Style::spaceSm), static_cast<float>(Style::spaceMd),
               static_cast<float>(Style::spaceSm), static_cast<float>(Style::spaceMd));
    setMinHeight(static_cast<float>(Style::controlHeightLg));
    setRadius(static_cast<float>(Style::radiusMd));
    setBackground(palette.surfaceVariant);
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

  void setRowWidth(float width) { m_rowWidth = width; }

  void setDevice(const AudioNode& node) {
    m_radio->setChecked(node.isDefault);

    const std::string title = !node.description.empty() ? node.description : node.name;

    if (m_title != nullptr) {
      m_title->setText(title);
    }
    if (m_detail != nullptr) {
      m_detail->setVisible(false);
      m_detail->setText("");
    }
  }

  void layout(Renderer& renderer) override {
    if (m_radio == nullptr || m_textColumn == nullptr || m_title == nullptr || m_inputArea == nullptr) {
      return;
    }

    m_radio->layout(renderer);

    const float textMaxWidth = std::max(
        0.0f, m_rowWidth - static_cast<float>(Style::spaceMd * 2 + Style::spaceSm) - m_radio->width());
    m_title->setMaxWidth(textMaxWidth);
    m_title->measure(renderer);

    if (m_detail != nullptr && m_detail->visible()) {
      m_detail->setMaxWidth(textMaxWidth);
      m_detail->measure(renderer);
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
      setBorderWidth(static_cast<float>(Style::borderWidth));
      if (m_title != nullptr) {
        m_title->setColor(palette.onPrimary);
      }
      if (m_detail != nullptr) {
        m_detail->setColor(palette.onPrimary);
      }
      return;
    }

    setBackground(palette.surfaceVariant);
    setBorderColor(hovered() ? palette.primary : palette.surfaceVariant);
    setBorderWidth(hovered() ? static_cast<float>(Style::borderWidth) : 0.0f);
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
  float m_rowWidth = 0.0f;
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

void addSectionHeader(Flex& parent, const char* title, const char* subtitle) {
  auto section = std::make_unique<Flex>();
  section->setDirection(FlexDirection::Vertical);
  section->setAlign(FlexAlign::Start);
  section->setGap(0.0f);

  auto titleLabel = std::make_unique<Label>();
  titleLabel->setText(title);
  titleLabel->setBold(true);
  titleLabel->setFontSize(Style::fontSizeBody);
  titleLabel->setColor(palette.primary);
  section->addChild(std::move(titleLabel));

  auto subtitleLabel = std::make_unique<Label>();
  subtitleLabel->setText(subtitle);
  subtitleLabel->setCaptionStyle();
  subtitleLabel->setColor(palette.onSurfaceVariant);
  section->addChild(std::move(subtitleLabel));

  parent.addChild(std::move(section));
}

void addEmptyState(Flex& parent, Renderer& renderer, float width, const char* title, const char* body) {
  auto card = std::make_unique<Flex>();
  card->setDirection(FlexDirection::Vertical);
  card->setAlign(FlexAlign::Start);
  card->setGap(static_cast<float>(Style::spaceXs));
  card->setPadding(static_cast<float>(Style::spaceMd));
  card->setRadius(static_cast<float>(Style::radiusMd));
  card->setBackground(palette.surfaceVariant);
  card->setBorderWidth(0.0f);
  card->setMinWidth(width);

  auto titleLabel = std::make_unique<Label>();
  titleLabel->setText(title);
  titleLabel->setBold(true);
  titleLabel->setMaxWidth(width - static_cast<float>(Style::spaceMd * 2));
  titleLabel->measure(renderer);
  card->addChild(std::move(titleLabel));

  auto bodyLabel = std::make_unique<Label>();
  bodyLabel->setText(body);
  bodyLabel->setCaptionStyle();
  bodyLabel->setColor(palette.onSurfaceVariant);
  bodyLabel->setMaxWidth(width - static_cast<float>(Style::spaceMd * 2));
  bodyLabel->measure(renderer);
  card->addChild(std::move(bodyLabel));

  parent.addChild(std::move(card));
}

} // namespace

AudioDevicesPanel::AudioDevicesPanel(PipeWireService* audio) : m_audio(audio) {}

void AudioDevicesPanel::create(Renderer& renderer) {
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setAlign(FlexAlign::Start);
  container->setGap(static_cast<float>(Style::spaceMd));

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Vertical);
  header->setAlign(FlexAlign::Start);
  header->setGap(static_cast<float>(Style::spaceXs));
  header->setBackground(palette.surface);
  header->setPadding(0.0f, 0.0f, static_cast<float>(Style::spaceXs), 0.0f);
  header->setZIndex(2);
  m_header = header.get();

  auto title = std::make_unique<Label>();
  title->setText("Audio Devices");
  title->setFontSize(Style::fontSizeTitle);
  title->setBold(true);
  title->setColor(palette.primary);
  m_titleLabel = title.get();
  header->addChild(std::move(title));

  auto subtitle = std::make_unique<Label>();
  subtitle->setText("Select the default output and input devices");
  subtitle->setCaptionStyle();
  subtitle->setColor(palette.onSurfaceVariant);
  m_subtitleLabel = subtitle.get();
  header->addChild(std::move(subtitle));

  container->addChild(std::move(header));

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setScrollbarVisible(true);
  scrollView->setScrollStep(static_cast<float>(Style::controlHeightLg + Style::spaceSm));
  scrollView->setZIndex(1);
  m_scrollView = scrollView.get();
  m_list = scrollView->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(static_cast<float>(Style::spaceLg));
  container->addChild(std::move(scrollView));

  m_container = container.get();
  m_root = std::move(container);

  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  rebuildList(renderer, preferredWidth());
}

void AudioDevicesPanel::layout(Renderer& renderer, float width, float height) {
  if (m_container == nullptr || m_header == nullptr || m_scrollView == nullptr) {
    return;
  }

  m_lastWidth = width;
  m_lastHeight = height;

  if (m_titleLabel != nullptr) {
    m_titleLabel->setMaxWidth(width);
    m_titleLabel->measure(renderer);
  }
  if (m_subtitleLabel != nullptr) {
    m_subtitleLabel->setMaxWidth(width);
    m_subtitleLabel->measure(renderer);
  }

  m_header->setMinWidth(width);
  m_header->layout(renderer);

  const float scrollHeight = std::max(0.0f, height - m_header->height() - static_cast<float>(Style::spaceMd));
  m_scrollView->setSize(width, scrollHeight);
  m_scrollView->layout(renderer);
  rebuildList(renderer, m_scrollView->contentViewportWidth());
  m_scrollView->layout(renderer);

  m_container->setMinWidth(width);
  m_container->setSize(width, height);
  m_container->layout(renderer);
}

void AudioDevicesPanel::update(Renderer& renderer) {
  const std::uint64_t changeSerial = m_audio != nullptr ? m_audio->changeSerial() : 0;
  if ((changeSerial == m_lastChangeSerial && m_lastListWidth >= 0.0f) || m_lastWidth <= 0.0f) {
    return;
  }

  const float listWidth = m_scrollView != nullptr ? m_scrollView->contentViewportWidth() : m_lastWidth;
  rebuildList(renderer, listWidth);
}

void AudioDevicesPanel::rebuildList(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  const std::uint64_t changeSerial = m_audio != nullptr ? m_audio->changeSerial() : 0;
  if (width == m_lastListWidth && changeSerial == m_lastChangeSerial) {
    return;
  }

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  const float rowWidth = std::max(0.0f, width);
  if (m_audio == nullptr) {
    addEmptyState(*m_list, renderer, rowWidth, "Audio unavailable", "PipeWire is not active.");
    m_lastChangeSerial = changeSerial;
    m_lastListWidth = width;
    return;
  }

  const AudioState& state = m_audio->state();
  addSectionHeader(*m_list, "Outputs", "Available playback devices");
  if (state.sinks.empty()) {
    addEmptyState(*m_list, renderer, rowWidth, "No output devices", "No playback sinks are currently available.");
  } else {
    auto outputSection = std::make_unique<Flex>();
    outputSection->setDirection(FlexDirection::Vertical);
    outputSection->setAlign(FlexAlign::Start);
    outputSection->setGap(static_cast<float>(Style::spaceSm));

    for (const auto& sink : sortedDevices(state.sinks)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = sink.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSink(id);
        }
        PanelManager::instance().refresh();
      });
      row->setRowWidth(rowWidth);
      row->setDevice(sink);
      row->setMinWidth(rowWidth);
      row->layout(renderer);
      outputSection->addChild(std::move(row));
    }

    m_list->addChild(std::move(outputSection));
  }

  addSectionHeader(*m_list, "Inputs", "Available recording devices");
  if (state.sources.empty()) {
    addEmptyState(*m_list, renderer, rowWidth, "No input devices", "No recording sources are currently available.");
  } else {
    auto inputSection = std::make_unique<Flex>();
    inputSection->setDirection(FlexDirection::Vertical);
    inputSection->setAlign(FlexAlign::Start);
    inputSection->setGap(static_cast<float>(Style::spaceSm));

    for (const auto& source : sortedDevices(state.sources)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = source.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSource(id);
        }
        PanelManager::instance().refresh();
      });
      row->setRowWidth(rowWidth);
      row->setDevice(source);
      row->setMinWidth(rowWidth);
      row->layout(renderer);
      inputSection->addChild(std::move(row));
    }

    m_list->addChild(std::move(inputSection));
  }

  m_lastChangeSerial = changeSerial;
  m_lastListWidth = width;
}

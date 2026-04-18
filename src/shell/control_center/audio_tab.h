#pragma once

#include "core/timer_manager.h"
#include "shell/control_center/tab.h"

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

class ConfigService;
class Flex;
class Label;
class PipeWireService;
class Renderer;
class ScrollView;
class Slider;

class AudioTab : public Tab {
public:
  AudioTab(PipeWireService* audio, ConfigService* config);

  std::unique_ptr<Flex> create() override;
  void onClose() override;
  [[nodiscard]] bool dragging() const noexcept;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void rebuildLists(Renderer& renderer);
  void syncValueLabelWidths(Renderer& renderer);
  [[nodiscard]] float sliderMaxPercent() const;
  void queueSinkVolume(float value);
  void queueSourceVolume(float value);
  void flushPendingVolumes(bool force = false);

  PipeWireService* m_audio = nullptr;
  ConfigService* m_config = nullptr;

  Flex* m_rootLayout = nullptr;
  Flex* m_deviceColumn = nullptr;
  Flex* m_outputCard = nullptr;
  Flex* m_inputCard = nullptr;
  ScrollView* m_outputScroll = nullptr;
  ScrollView* m_inputScroll = nullptr;
  Flex* m_outputList = nullptr;
  Flex* m_inputList = nullptr;
  Flex* m_volumeColumn = nullptr;
  Flex* m_outputVolumeCard = nullptr;
  Flex* m_inputVolumeCard = nullptr;
  Label* m_outputDeviceLabel = nullptr;
  Label* m_inputDeviceLabel = nullptr;
  Slider* m_outputSlider = nullptr;
  Label* m_outputValue = nullptr;
  Slider* m_inputSlider = nullptr;
  Label* m_inputValue = nullptr;

  float m_lastOutputWidth = -1.0f;
  float m_lastInputWidth = -1.0f;
  std::string m_lastOutputListKey;
  std::string m_lastInputListKey;
  float m_lastSinkVolume = -1.0f;
  float m_lastSourceVolume = -1.0f;
  std::uint32_t m_pendingSinkId = 0;
  std::uint32_t m_pendingSourceId = 0;
  float m_pendingSinkVolume = -1.0f;
  float m_pendingSourceVolume = -1.0f;
  float m_lastSentSinkVolume = -1.0f;
  float m_lastSentSourceVolume = -1.0f;
  std::chrono::steady_clock::time_point m_lastSinkCommitAt{};
  std::chrono::steady_clock::time_point m_lastSourceCommitAt{};
  std::chrono::steady_clock::time_point m_ignoreSinkStateUntil{};
  std::chrono::steady_clock::time_point m_ignoreSourceStateUntil{};
  Timer m_sinkVolumeDebounceTimer;
  Timer m_sourceVolumeDebounceTimer;
  bool m_syncingOutputSlider = false;
  bool m_syncingInputSlider = false;
};

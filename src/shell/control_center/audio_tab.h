#pragma once

#include "shell/control_center/tab.h"

#include <cstdint>
#include <vector>

class Flex;
class Label;
class PipeWireService;
class Renderer;
class ScrollView;
class Slider;

class AudioTab : public Tab {
public:
  explicit AudioTab(PipeWireService* audio);

  std::unique_ptr<Flex> build(Renderer& renderer) override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void onClose() override;

private:
  void rebuildLists(Renderer& renderer);

  PipeWireService* m_audio = nullptr;

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
  std::uint64_t m_lastChangeSerial = 0;
  float m_lastSinkVolume = -1.0f;
  float m_lastSourceVolume = -1.0f;
  bool m_syncingOutputSlider = false;
  bool m_syncingInputSlider = false;
};

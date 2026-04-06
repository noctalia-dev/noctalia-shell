#pragma once

#include "shell/panel/panel.h"

#include <cstdint>

class Flex;
class Label;
class PipeWireService;
class ScrollView;

class AudioDevicesPanel : public Panel {
public:
  explicit AudioDevicesPanel(PipeWireService* audio);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;

  [[nodiscard]] float preferredWidth() const override { return 420.0f; }
  [[nodiscard]] float preferredHeight() const override { return 460.0f; }

private:
  void rebuildList(Renderer& renderer, float width);

  PipeWireService* m_audio = nullptr;
  Flex* m_container = nullptr;
  Flex* m_header = nullptr;
  ScrollView* m_scrollView = nullptr;
  Flex* m_list = nullptr;
  Label* m_titleLabel = nullptr;
  Label* m_subtitleLabel = nullptr;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  float m_lastListWidth = -1.0f;
  std::uint64_t m_lastChangeSerial = 0;
};

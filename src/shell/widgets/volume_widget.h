#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Icon;
class Label;
class PipeWireService;
struct wl_output;

class VolumeWidget : public Widget {
public:
  VolumeWidget(PipeWireService* audio, wl_output* output, std::int32_t scale);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  PipeWireService* m_audio = nullptr;
  wl_output* m_output = nullptr;
  std::int32_t m_scale = 1;
  Icon* m_icon = nullptr;
  Label* m_label = nullptr;
  float m_lastVolume = -1.0f;
  bool m_lastMuted = false;
};

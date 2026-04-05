#pragma once

#include "shell/widget/widget.h"

class Icon;
class Label;
class PipeWireService;

class VolumeWidget : public Widget {
public:
  explicit VolumeWidget(PipeWireService* audio);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  PipeWireService* m_audio = nullptr;
  Icon* m_icon = nullptr;
  Label* m_label = nullptr;
  float m_lastVolume = -1.0f;
  bool m_lastMuted = false;
};

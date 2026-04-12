#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Glyph;
class Label;
class PipeWireService;
struct wl_output;

class VolumeWidget : public Widget {
public:
  VolumeWidget(PipeWireService* audio, wl_output* output);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  PipeWireService* m_audio = nullptr;
  wl_output* m_output = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  float m_lastVolume = -1.0f;
  bool m_lastMuted = false;
};

#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <vector>

class Box;
class Renderer;

class AudioSpectrum : public Node {
public:
  AudioSpectrum();

  void setValues(const std::vector<float>& values);
  void setGradient(const Color& lowColor, const Color& highColor);
  void setSpacingRatio(float ratio);

  void layout(Renderer& renderer) override;

private:
  void ensureBarCount(std::size_t count);
  void recolorBars();

  std::vector<float> m_values;
  std::vector<Box*> m_bars;
  Color m_lowColor = {};
  Color m_highColor = {};
  float m_spacingRatio = 0.5f;
};

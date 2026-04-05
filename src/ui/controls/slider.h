#pragma once

#include "ui/controls/flex.h"

#include <functional>

class InputArea;
class RectNode;
class Renderer;

class Slider : public Flex {
public:
  Slider();

  void setRange(float minValue, float maxValue);
  void setStep(float step);
  void setValue(float value);
  void setEnabled(bool enabled);
  void setOnValueChanged(std::function<void(float)> callback);

  [[nodiscard]] float value() const noexcept { return m_value; }
  [[nodiscard]] float minValue() const noexcept { return m_min; }
  [[nodiscard]] float maxValue() const noexcept { return m_max; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }

  void layout(Renderer& renderer) override;

private:
  void updateFromLocalX(float x);
  void updateGeometry();
  void applyVisualState();
  [[nodiscard]] float normalizedValue() const noexcept;
  [[nodiscard]] float snapped(float value) const noexcept;

  RectNode* m_track = nullptr;
  RectNode* m_fill = nullptr;
  RectNode* m_thumb = nullptr;
  InputArea* m_inputArea = nullptr;

  std::function<void(float)> m_onValueChanged;

  float m_min = 0.0f;
  float m_max = 100.0f;
  float m_step = 1.0f;
  float m_value = 50.0f;
  bool m_enabled = true;
};

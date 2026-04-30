#pragma once

#include "ui/controls/flex.h"
#include "ui/style.h"

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
  void setTrackHeight(float height);
  void setThumbSize(float size);
  void setControlHeight(float height);
  void setWheelAdjustEnabled(bool enabled);
  void setOnValueChanged(std::function<void(float)> callback);
  void setOnDragEnd(std::function<void()> callback);

  [[nodiscard]] float value() const noexcept { return m_value; }
  [[nodiscard]] float minValue() const noexcept { return m_min; }
  [[nodiscard]] float maxValue() const noexcept { return m_max; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool wheelAdjustEnabled() const noexcept { return m_wheelAdjustEnabled; }
  [[nodiscard]] bool dragging() const noexcept;

private:
  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;
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
  std::function<void()> m_onDragEnd;

  float m_min = 0.0f;
  float m_max = 100.0f;
  float m_step = 1.0f;
  float m_value = 50.0f;
  bool m_enabled = true;
  bool m_wheelAdjustEnabled = false;
  float m_trackHeight = Style::sliderTrackHeight;
  float m_thumbSizePx = Style::sliderThumbSize;
  float m_controlHeightPx = Style::controlHeight;
};

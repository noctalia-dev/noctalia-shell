#pragma once

#include "ui/controls/flex.h"

enum class ToggleSize : std::uint8_t {
  Small,
  Medium,
  Large,
};

class Toggle : public Flex {
public:
  Toggle();

  void setChecked(bool checked);
  void setEnabled(bool enabled);
  void setToggleSize(ToggleSize size);
  void setScale(float scale);
  [[nodiscard]] bool checked() const noexcept { return m_checked; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] ToggleSize toggleSize() const noexcept { return m_size; }

private:
  void applySize();
  void applyState();
  void applyAnimatedState(float t);

  class RectNode* m_thumb = nullptr;
  std::uint32_t m_animId = 0;
  ToggleSize m_size = ToggleSize::Medium;
  bool m_checked = false;
  bool m_enabled = true;
  float m_inset = 0.0f;
  float m_travel = 0.0f;
  float m_thumbSize = 0.0f;
  float m_scale = 1.0f;
};

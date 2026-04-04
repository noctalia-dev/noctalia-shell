#pragma once

#include "ui/controls/Box.h"

enum class ToggleSize : std::uint8_t {
  Small,
  Medium,
  Large,
};

class Toggle : public Box {
public:
  Toggle();

  void setChecked(bool checked);
  void setEnabled(bool enabled);
  void setToggleSize(ToggleSize size);

  [[nodiscard]] bool checked() const noexcept { return m_checked; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] ToggleSize toggleSize() const noexcept { return m_size; }

private:
  void applySize();
  void applyState();

  class RectNode* m_thumb = nullptr;
  ToggleSize m_size = ToggleSize::Medium;
  bool m_checked = false;
  bool m_enabled = true;
  float m_inset = 0.0f;
  float m_travel = 0.0f;
  float m_thumbSize = 0.0f;
};

#pragma once

#include "ui/controls/flex.h"
#include "ui/signal.h"

#include <functional>

enum class ToggleSize : std::uint8_t {
  Small,
  Medium,
  Large,
};

class InputArea;
class Renderer;

class Toggle : public Flex {
public:
  Toggle();

  void setChecked(bool checked);
  void setEnabled(bool enabled);
  void setToggleSize(ToggleSize size);
  void setScale(float scale);
  void setOnChange(std::function<void(bool)> callback);
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;
  [[nodiscard]] bool checked() const noexcept { return m_checked; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] ToggleSize toggleSize() const noexcept { return m_size; }
  void layout(Renderer& renderer) override;

private:
  void applySize();
  void applyState();
  void applyAnimatedState(float t);

  class RectNode* m_thumb = nullptr;
  InputArea* m_inputArea = nullptr;
  std::uint32_t m_animId = 0;
  std::function<void(bool)> m_onChange;
  ToggleSize m_size = ToggleSize::Medium;
  bool m_checked = false;
  bool m_enabled = true;
  float m_inset = 0.0f;
  float m_travel = 0.0f;
  float m_thumbSize = 0.0f;
  float m_scale = 1.0f;
  float m_animationProgress = 0.0f;
  Signal<>::ScopedConnection m_paletteConn;
};

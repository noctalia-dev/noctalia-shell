#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <functional>

class Box;
class InputArea;
class Renderer;

class RadioButton : public Node {
public:
  RadioButton();

  void setChecked(bool checked);
  void setEnabled(bool enabled);
  void setOnChange(std::function<void(bool)> callback);
  void setScale(float scale);

  [[nodiscard]] bool checked() const noexcept { return m_checked; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;

  void layout(Renderer& renderer) override;

private:
  void applyState();

  Box* m_outer = nullptr;
  Box* m_inner = nullptr;
  InputArea* m_inputArea = nullptr;
  std::function<void(bool)> m_onChange;
  bool m_checked = false;
  bool m_enabled = true;
  float m_scale = 1.0f;
};

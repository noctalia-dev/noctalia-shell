#pragma once

#include "render/scene/node.h"

#include <functional>

class Box;
class Glyph;
class InputArea;
class Renderer;

class Checkbox : public Node {
public:
  Checkbox();

  void setChecked(bool checked);
  void setEnabled(bool enabled);
  void setOnChange(std::function<void(bool)> callback);
  void setScale(float scale);

  [[nodiscard]] bool checked() const noexcept { return m_checked; }
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;

private:
  void doLayout(Renderer& renderer) override;
  void applyState();

  Box* m_box = nullptr;
  Glyph* m_checkGlyph = nullptr;
  InputArea* m_inputArea = nullptr;
  std::function<void(bool)> m_onChange;
  bool m_checked = false;
  bool m_enabled = true;
  float m_scale = 1.0f;
};

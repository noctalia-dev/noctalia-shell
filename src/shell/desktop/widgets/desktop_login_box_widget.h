#pragma once

#include "shell/desktop/desktop_widget.h"

class Box;
class Glyph;

class DesktopLoginBoxWidget : public DesktopWidget {
public:
  void create() override;
  void setScreenWidth(float screenWidth) noexcept { m_screenWidth = screenWidth; }

private:
  void doLayout(Renderer& renderer) override;

  float m_screenWidth = 0.0f;
  Box* m_panel = nullptr;
  Box* m_passwordGhost = nullptr;
  Box* m_loginButtonGhost = nullptr;
  Glyph* m_loginGlyph = nullptr;
};

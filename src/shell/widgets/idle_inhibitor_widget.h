#pragma once

#include "shell/widget/widget.h"

class Glyph;
class IdleInhibitor;
class InputArea;

class IdleInhibitorWidget : public Widget {
public:
  explicit IdleInhibitorWidget(IdleInhibitor* inhibitor);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  IdleInhibitor* m_inhibitor = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  bool m_lastEnabled = false;
  bool m_lastAvailable = false;
};

#pragma once

#include "shell/bar/widget.h"

class Glyph;
class IdleInhibitor;
class InputArea;

class IdleInhibitorWidget : public Widget {
public:
  explicit IdleInhibitorWidget(IdleInhibitor* inhibitor);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  IdleInhibitor* m_inhibitor = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  bool m_lastEnabled = false;
  bool m_lastAvailable = false;
};

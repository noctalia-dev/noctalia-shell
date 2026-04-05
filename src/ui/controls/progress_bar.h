#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

class RectNode;

class ProgressBar : public Node {
public:
  ProgressBar();

  void setFillColor(const Color& color);
  void setTrackColor(const Color& color);
  void setRadius(float radius);
  void setSoftness(float softness);

  void setProgress(float progress); // 0.0–1.0
  [[nodiscard]] float progress() const noexcept { return m_progress; }

  void setSize(float width, float height) override;

private:
  void updateGeometry();

  RectNode* m_track = nullptr;
  RectNode* m_fill = nullptr;
  float m_progress = 1.0f;
};

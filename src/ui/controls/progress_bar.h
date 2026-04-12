#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

#include <optional>

class RectNode;

enum class ProgressBarOrientation { Horizontal, Vertical };

class ProgressBar : public Node {
public:
  ProgressBar();

  void setFill(const ThemeColor& color);
  void setFill(const Color& color);
  void setTrack(const ThemeColor& color);
  void setTrack(const Color& color);
  void setFillColor(const ThemeColor& color);
  void setFillColor(const Color& color);
  void setTrackColor(const ThemeColor& color);
  void setTrackColor(const Color& color);
  void setRadius(float radius);
  void setSoftness(float softness);
  void setOrientation(ProgressBarOrientation orientation);

  void setProgress(float progress); // 0.0–1.0
  [[nodiscard]] float progress() const noexcept { return m_progress; }

  void setSize(float width, float height) override;

private:
  void applyPalette();
  void updateGeometry();

  RectNode* m_track = nullptr;
  RectNode* m_fill = nullptr;
  ThemeColor m_trackColor = roleColor(ColorRole::SurfaceVariant);
  ThemeColor m_fillColor = roleColor(ColorRole::Primary);
  float m_progress = 1.0f;
  ProgressBarOrientation m_orientation = ProgressBarOrientation::Horizontal;
  Signal<>::ScopedConnection m_paletteConn;
};

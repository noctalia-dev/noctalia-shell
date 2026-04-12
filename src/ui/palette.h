#pragma once

#include "render/core/color.h"

struct Palette {
  Color primary;
  Color onPrimary;
  Color secondary;
  Color onSecondary;
  Color tertiary;
  Color onTertiary;
  Color error;
  Color onError;
  Color surface;
  Color onSurface;
  Color surfaceVariant;
  Color onSurfaceVariant;
  Color outline;
  Color shadow;
  Color hover;
  Color onHover;
};

extern Palette palette;

void setPalette(const Palette& p);

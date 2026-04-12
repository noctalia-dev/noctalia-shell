#include "ui/palette.h"

#include "theme/builtin_schemes.h"

Palette palette = noctalia::theme::findBuiltinScheme("Noctalia")->dark;

void setPalette(const Palette& p) { palette = p; }

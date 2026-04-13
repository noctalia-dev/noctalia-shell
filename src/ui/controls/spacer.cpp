#include "ui/controls/spacer.h"

#include "render/core/renderer.h"

Spacer::Spacer() { setFlexGrow(1.0f); }

void Spacer::doLayout(Renderer& /*renderer*/) {}

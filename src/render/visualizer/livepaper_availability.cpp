#include "render/visualizer/livepaper_availability.h"

namespace noctalia::livepaper {

  namespace {
    bool g_rendererReady = false;
  }

  bool rendererReady() noexcept { return g_rendererReady; }

  void setRendererReady(bool ready) noexcept { g_rendererReady = ready; }

} // namespace noctalia::livepaper

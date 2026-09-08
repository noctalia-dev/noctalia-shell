#pragma once

// Whether the [wallpaper.live_paper] visualizer can actually run on this
// build/machine. Two independent conditions gate it, and the settings UI needs
// to tell them apart to explain itself:
//
//   compiledIn()     libprojectM was found at configure time (meson `livepaper`
//                    feature). When false the whole visualizer is a stub and no
//                    amount of configuration will start it.
//   rendererReady()  ProjectMRenderer actually initialized: requires
//                    compiledIn(), a GLES3 shared context (projectM 4 uses
//                    VAOs) and a successful projectM setup.
//
// Lives in its own always-compiled translation unit so callers that must work
// in both build variants (settings registry, wallpaper) need no #ifdef.
namespace noctalia::livepaper {

  [[nodiscard]] constexpr bool compiledIn() noexcept {
#ifdef NOCTALIA_HAVE_LIVEPAPER
    return true;
#else
    return false;
#endif
  }

  // Set once by Application during UI initialization; read on the same
  // (main) thread by the settings registry.
  [[nodiscard]] bool rendererReady() noexcept;
  void setRendererReady(bool ready) noexcept;

} // namespace noctalia::livepaper

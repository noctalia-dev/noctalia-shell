// No-op implementations of the live-paper plumbing for builds where
// libprojectM was not found / the meson `livepaper` feature is disabled.
//
// The wallpaper and lock-screen integration call into these classes through
// non-owning pointers and already null-check before doing anything visible to
// the user. When the feature is compiled out, Application never constructs
// any of these instances, so the only symbols that need to exist are the
// out-of-line definitions emitted by the headers (constructors, the
// destructor, and the methods called unconditionally by other translation
// units). Each one degrades to a quiet no-op or an obviously-empty return
// value.

#include "pipewire/pipewire_pcm_tap.h"
#include "render/core/texture_handle.h"
#include "render/visualizer/projectm_renderer.h"
#include "shell/wallpaper/visualizer_service.h"

#include <cstdint>
#include <string>
#include <vector>

// ── ProjectMRenderer ─────────────────────────────────────────────────────────

ProjectMRenderer::ProjectMRenderer() = default;
ProjectMRenderer::~ProjectMRenderer() = default;

bool ProjectMRenderer::initialize(
    GlSharedContext& /*shared*/, wl_compositor* /*compositor*/, std::uint32_t /*width*/, std::uint32_t /*height*/
) {
  return false;
}
void ProjectMRenderer::shutdown() {}
void ProjectMRenderer::resize(std::uint32_t /*width*/, std::uint32_t /*height*/) {}
TextureHandle ProjectMRenderer::textureHandle() const noexcept { return TextureHandle{}; }
void ProjectMRenderer::setMeshSize(int /*meshW*/, int /*meshH*/) {}
void ProjectMRenderer::setFps(int /*fps*/) {}
void ProjectMRenderer::loadPreset(const std::string& /*path*/) {}
void ProjectMRenderer::setTextureSearchPaths(const std::vector<std::string>& /*paths*/) {}
void ProjectMRenderer::renderFrame() {}

// ── VisualizerService ────────────────────────────────────────────────────────

VisualizerService::VisualizerService() = default;
VisualizerService::~VisualizerService() = default;

void VisualizerService::initialize(ProjectMRenderer* /*renderer*/, ConfigService* /*config*/, MprisService* /*mpris*/) {
}
void VisualizerService::shutdown() {}
void VisualizerService::onConfigChanged() {}
void VisualizerService::onMprisChanged() {}
void VisualizerService::advancePreset() {}
void VisualizerService::setEnabled(bool /*enabled*/) {}
void VisualizerService::toggleEnabled() {}
void VisualizerService::setSessionLocked(bool /*locked*/) {}
bool VisualizerService::enabled() const noexcept { return false; }

// ── PipeWirePcmTap ───────────────────────────────────────────────────────────

// PipeWirePcmTap's `m_stream` member is a `std::unique_ptr<Stream>` where
// Stream is forward-declared in the header (real definition lives in the
// pipewire_pcm_tap.cpp). The compiler needs a complete Stream type to
// instantiate ~unique_ptr, so we provide an empty one here. Since the stub
// never constructs a Stream, the unique_ptr is always null and its deleter is
// a no-op at runtime.
class PipeWirePcmTap::Stream {};

PipeWirePcmTap::PipeWirePcmTap(PipeWireService& service, PipeWireSpectrum* spectrum)
    : m_service(service), m_spectrum(spectrum) {}
PipeWirePcmTap::~PipeWirePcmTap() = default;

void PipeWirePcmTap::start(std::string /*targetNodeName*/) {}
void PipeWirePcmTap::stop() {}
void PipeWirePcmTap::handleAudioStateChanged() {}
void PipeWirePcmTap::setMicFallbackAllowed(bool /*allowed*/) {}
int PipeWirePcmTap::consume(float* /*out*/, int /*maxFrames*/) { return 0; }
bool PipeWirePcmTap::isRunning() const noexcept { return false; }

#include "render/backend/render_backend.h"

#include "render/backend/gles_render_backend.h"

std::unique_ptr<RenderBackend> createDefaultRenderBackend() { return std::make_unique<GlesRenderBackend>(); }

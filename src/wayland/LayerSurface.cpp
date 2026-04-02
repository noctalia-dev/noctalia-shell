#include "wayland/LayerSurface.hpp"

#include "wayland/WaylandConnection.hpp"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kBarHeight = 36;
constexpr std::uint32_t kAnchorMask =
    ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
    ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
    ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;

const zwlr_layer_surface_v1_listener kLayerSurfaceListener = {
    .configure = &LayerSurface::handleConfigure,
    .closed = &LayerSurface::handleClosed,
};

const wl_callback_listener kFrameListener = {
    .done = &LayerSurface::handleFrameDone,
};

const wl_buffer_listener kBufferListener = {
    .release = &LayerSurface::handleBufferRelease,
};

int createAnonymousFile(std::size_t size) {
    char fileTemplate[] = "/tmp/noctalia-layer-surface-XXXXXX";
    const int fd = mkstemp(fileTemplate);
    if (fd < 0) {
        throw std::runtime_error("failed to create shm temp file");
    }

    unlink(fileTemplate);

    if (ftruncate(fd, static_cast<off_t>(size)) != 0) {
        close(fd);
        throw std::runtime_error("failed to resize shm temp file");
    }

    return fd;
}

} // namespace

LayerSurface::LayerSurface(WaylandConnection& connection)
    : m_connection(connection) {}

LayerSurface::~LayerSurface() {
    cleanup();
}

bool LayerSurface::initialize() {
    if (!m_connection.hasRequiredGlobals()) {
        std::cout << "[noctalia] layer surface skipped: missing compositor/shm/layer-shell globals\n";
        return false;
    }

    if (!createSurface()) {
        return false;
    }

    m_running = true;
    return true;
}

bool LayerSurface::isRunning() const noexcept {
    return m_running;
}

void LayerSurface::dispatch() {
    if (!m_running) {
        return;
    }

    if (wl_display_dispatch(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
    }
}

void LayerSurface::handleConfigure(void* data,
                                   zwlr_layer_surface_v1* layerSurface,
                                   std::uint32_t serial,
                                   std::uint32_t width,
                                   std::uint32_t height) {
    auto* self = static_cast<LayerSurface*>(data);
    zwlr_layer_surface_v1_ack_configure(layerSurface, serial);

    self->m_width = (width == 0) ? 1920 : width;
    self->m_height = (height == 0) ? kBarHeight : height;
    self->m_configured = true;

    if (!self->createOrResizeBuffer(self->m_width, self->m_height)) {
        self->m_running = false;
        return;
    }

    self->render();
}

void LayerSurface::handleClosed(void* data,
                                zwlr_layer_surface_v1* /*layerSurface*/) {
    auto* self = static_cast<LayerSurface*>(data);
    self->m_running = false;
}

void LayerSurface::handleFrameDone(void* data,
                                   wl_callback* callback,
                                   std::uint32_t /*callbackData*/) {
    auto* self = static_cast<LayerSurface*>(data);

    if (callback != nullptr) {
        wl_callback_destroy(callback);
    }

    self->m_frameCallback = nullptr;

    if (self->m_running && self->m_configured) {
        self->requestFrame();
    }
}

void LayerSurface::handleBufferRelease(void* data,
                                       wl_buffer* /*buffer*/) {
    auto* self = static_cast<LayerSurface*>(data);
    self->m_bufferBusy = false;
}

bool LayerSurface::createSurface() {
    m_surface = wl_compositor_create_surface(m_connection.compositor());
    if (m_surface == nullptr) {
        throw std::runtime_error("failed to create wl_surface");
    }

    wl_output* output = nullptr;
    if (!m_connection.outputs().empty()) {
        output = m_connection.outputs().front().output;
    }

    m_layerSurface = zwlr_layer_shell_v1_get_layer_surface(
        m_connection.layerShell(),
        m_surface,
        output,
        ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        "noctalia-bar");
    if (m_layerSurface == nullptr) {
        throw std::runtime_error("failed to create layer surface");
    }

    if (zwlr_layer_surface_v1_add_listener(m_layerSurface, &kLayerSurfaceListener, this) != 0) {
        throw std::runtime_error("failed to add layer surface listener");
    }

    zwlr_layer_surface_v1_set_anchor(m_layerSurface, kAnchorMask);
    zwlr_layer_surface_v1_set_size(m_layerSurface, 0, kBarHeight);
    zwlr_layer_surface_v1_set_exclusive_zone(m_layerSurface, static_cast<int32_t>(kBarHeight));
    zwlr_layer_surface_v1_set_margin(m_layerSurface, 0, 0, 0, 0);
    zwlr_layer_surface_v1_set_keyboard_interactivity(
        m_layerSurface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);

    wl_surface_commit(m_surface);
    if (wl_display_roundtrip(m_connection.display()) < 0) {
        throw std::runtime_error("failed during layer surface initial roundtrip");
    }

    return true;
}

bool LayerSurface::createOrResizeBuffer(std::uint32_t width, std::uint32_t height) {
    if (width == 0 || height == 0) {
        return false;
    }

    const std::size_t pixelCount = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    const std::size_t bufferSize = pixelCount * sizeof(std::uint32_t);

    destroyBuffer();

    m_shmBuffer.fd = createAnonymousFile(bufferSize);
    m_shmBuffer.size = bufferSize;
    m_shmBuffer.data = mmap(nullptr, bufferSize, PROT_READ | PROT_WRITE, MAP_SHARED, m_shmBuffer.fd, 0);
    if (m_shmBuffer.data == MAP_FAILED) {
        const int savedErrno = errno;
        close(m_shmBuffer.fd);
        m_shmBuffer.fd = -1;
        throw std::runtime_error("failed to mmap shm buffer: " + std::string(std::strerror(savedErrno)));
    }

    m_shmBuffer.pool = wl_shm_create_pool(
        m_connection.shm(), m_shmBuffer.fd, static_cast<int32_t>(bufferSize));
    if (m_shmBuffer.pool == nullptr) {
        destroyBuffer();
        throw std::runtime_error("failed to create wl_shm_pool");
    }

    m_shmBuffer.buffer = wl_shm_pool_create_buffer(
        m_shmBuffer.pool,
        0,
        static_cast<int32_t>(width),
        static_cast<int32_t>(height),
        static_cast<int32_t>(width * sizeof(std::uint32_t)),
        WL_SHM_FORMAT_XRGB8888);
    if (m_shmBuffer.buffer == nullptr) {
        destroyBuffer();
        throw std::runtime_error("failed to create wl_buffer");
    }

    if (wl_buffer_add_listener(m_shmBuffer.buffer, &kBufferListener, this) != 0) {
        destroyBuffer();
        throw std::runtime_error("failed to add wl_buffer listener");
    }

    m_shmBuffer.pixels.resize(pixelCount);
    return true;
}

void LayerSurface::render() {
    if (m_surface == nullptr || m_shmBuffer.buffer == nullptr || m_bufferBusy) {
        return;
    }

    std::fill(m_shmBuffer.pixels.begin(), m_shmBuffer.pixels.end(), 0x00121A24u);
    std::memcpy(m_shmBuffer.data, m_shmBuffer.pixels.data(), m_shmBuffer.size);

    wl_surface_attach(m_surface, m_shmBuffer.buffer, 0, 0);
    wl_surface_damage_buffer(m_surface, 0, 0, static_cast<int32_t>(m_width), static_cast<int32_t>(m_height));
    requestFrame();
    wl_surface_commit(m_surface);
    m_bufferBusy = true;
}

void LayerSurface::requestFrame() {
    if (m_frameCallback != nullptr) {
        return;
    }

    m_frameCallback = wl_surface_frame(m_surface);
    if (m_frameCallback != nullptr) {
        wl_callback_add_listener(m_frameCallback, &kFrameListener, this);
    }
}

void LayerSurface::destroyBuffer() {
    if (m_frameCallback != nullptr) {
        wl_callback_destroy(m_frameCallback);
        m_frameCallback = nullptr;
    }

    if (m_shmBuffer.buffer != nullptr) {
        wl_buffer_destroy(m_shmBuffer.buffer);
        m_shmBuffer.buffer = nullptr;
    }

    if (m_shmBuffer.pool != nullptr) {
        wl_shm_pool_destroy(m_shmBuffer.pool);
        m_shmBuffer.pool = nullptr;
    }

    if (m_shmBuffer.data != nullptr && m_shmBuffer.data != MAP_FAILED) {
        munmap(m_shmBuffer.data, m_shmBuffer.size);
        m_shmBuffer.data = nullptr;
    }

    if (m_shmBuffer.fd >= 0) {
        close(m_shmBuffer.fd);
        m_shmBuffer.fd = -1;
    }

    m_shmBuffer.size = 0;
    m_shmBuffer.pixels.clear();
    m_bufferBusy = false;
}

void LayerSurface::cleanup() {
    destroyBuffer();

    if (m_layerSurface != nullptr) {
        zwlr_layer_surface_v1_destroy(m_layerSurface);
        m_layerSurface = nullptr;
    }

    if (m_surface != nullptr) {
        wl_surface_destroy(m_surface);
        m_surface = nullptr;
    }

    m_running = false;
    m_configured = false;
}

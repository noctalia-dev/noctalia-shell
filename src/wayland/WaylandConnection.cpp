#include "wayland/WaylandConnection.hpp"

#include "core/Log.hpp"

#include <algorithm>
#include <stdexcept>

#include <wayland-client.h>

#if NOCTALIA_HAVE_WLR_LAYER_SHELL
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#endif
#include "xdg-output-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kCompositorVersion = 4;
constexpr std::uint32_t kSeatVersion = 5;
constexpr std::uint32_t kShmVersion = 1;
#if NOCTALIA_HAVE_WLR_LAYER_SHELL
constexpr std::uint32_t kLayerShellVersion = 4;
#endif
constexpr std::uint32_t kXdgOutputManagerVersion = 3;

const wl_registry_listener kRegistryListener = {
    .global = &WaylandConnection::handleGlobal,
    .global_remove = &WaylandConnection::handleGlobalRemove,
};

} // namespace

WaylandConnection::WaylandConnection() = default;

WaylandConnection::~WaylandConnection() {
    cleanup();
}

bool WaylandConnection::connect() {
    if (m_display != nullptr) {
        return true;
    }

    m_display = wl_display_connect(nullptr);
    if (m_display == nullptr) {
        throw std::runtime_error("failed to connect to Wayland display");
    }

    m_registry = wl_display_get_registry(m_display);
    if (m_registry == nullptr) {
        cleanup();
        throw std::runtime_error("failed to acquire Wayland registry");
    }

    if (wl_registry_add_listener(m_registry, &kRegistryListener, this) != 0) {
        cleanup();
        throw std::runtime_error("failed to add Wayland registry listener");
    }

    if (wl_display_roundtrip(m_display) < 0) {
        cleanup();
        throw std::runtime_error("failed during Wayland registry roundtrip");
    }

    if (wl_display_roundtrip(m_display) < 0) {
        cleanup();
        throw std::runtime_error("failed during Wayland output discovery roundtrip");
    }

    logStartupSummary();
    return true;
}

bool WaylandConnection::isConnected() const noexcept {
    return m_display != nullptr;
}

bool WaylandConnection::hasRequiredGlobals() const noexcept {
    return m_compositor != nullptr && m_shm != nullptr && m_layerShell != nullptr;
}

bool WaylandConnection::hasLayerShell() const noexcept {
    return m_hasLayerShellGlobal;
}

bool WaylandConnection::hasXdgOutputManager() const noexcept {
    return m_xdgOutputManager != nullptr;
}

wl_display* WaylandConnection::display() const noexcept {
    return m_display;
}

wl_compositor* WaylandConnection::compositor() const noexcept {
    return m_compositor;
}

wl_shm* WaylandConnection::shm() const noexcept {
    return m_shm;
}

zwlr_layer_shell_v1* WaylandConnection::layerShell() const noexcept {
    return m_layerShell;
}

const std::vector<WaylandOutput>& WaylandConnection::outputs() const noexcept {
    return m_outputs;
}

void WaylandConnection::handleGlobal(void* data,
                                     wl_registry* registry,
                                     std::uint32_t name,
                                     const char* interface,
                                     std::uint32_t version) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->bindGlobal(registry, name, interface, version);
}

void WaylandConnection::handleGlobalRemove(void* data,
                                           wl_registry* /*registry*/,
                                           std::uint32_t name) {
    auto* self = static_cast<WaylandConnection*>(data);
    std::erase_if(self->m_outputs, [name](const WaylandOutput& output) {
        return output.name == name;
    });
}

void WaylandConnection::bindGlobal(wl_registry* registry,
                                   std::uint32_t name,
                                   const char* interface,
                                   std::uint32_t version) {
    const std::string interfaceName = interface;

    if (interfaceName == wl_compositor_interface.name) {
        const auto bindVersion = std::min(version, kCompositorVersion);
        m_compositor = static_cast<wl_compositor*>(
            wl_registry_bind(registry, name, &wl_compositor_interface, bindVersion));
        return;
    }

    if (interfaceName == wl_seat_interface.name) {
        const auto bindVersion = std::min(version, kSeatVersion);
        m_seat = static_cast<wl_seat*>(
            wl_registry_bind(registry, name, &wl_seat_interface, bindVersion));
        return;
    }

    if (interfaceName == wl_shm_interface.name) {
        const auto bindVersion = std::min(version, kShmVersion);
        m_shm = static_cast<wl_shm*>(
            wl_registry_bind(registry, name, &wl_shm_interface, bindVersion));
        return;
    }

    if (interfaceName == "zwlr_layer_shell_v1") {
        m_hasLayerShellGlobal = true;
#if NOCTALIA_HAVE_WLR_LAYER_SHELL
        const auto bindVersion = std::min(version, kLayerShellVersion);
        m_layerShell = static_cast<zwlr_layer_shell_v1*>(
            wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, bindVersion));
#endif
        return;
    }

    if (interfaceName == zxdg_output_manager_v1_interface.name) {
        const auto bindVersion = std::min(version, kXdgOutputManagerVersion);
        m_xdgOutputManager = static_cast<zxdg_output_manager_v1*>(
            wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, bindVersion));
        return;
    }

    if (interfaceName == wl_output_interface.name) {
        auto* output = static_cast<wl_output*>(
            wl_registry_bind(registry, name, &wl_output_interface, 1));
        m_outputs.push_back(WaylandOutput{
            .name = name,
            .interfaceName = interfaceName,
            .version = version,
            .output = output,
        });
    }
}

void WaylandConnection::cleanup() {
    if (m_xdgOutputManager != nullptr) {
        zxdg_output_manager_v1_destroy(m_xdgOutputManager);
        m_xdgOutputManager = nullptr;
    }

    if (m_layerShell != nullptr) {
#if NOCTALIA_HAVE_WLR_LAYER_SHELL
        zwlr_layer_shell_v1_destroy(m_layerShell);
#endif
        m_layerShell = nullptr;
    }

    if (m_seat != nullptr) {
        wl_seat_destroy(m_seat);
        m_seat = nullptr;
    }

    if (m_shm != nullptr) {
        wl_shm_destroy(m_shm);
        m_shm = nullptr;
    }

    if (m_compositor != nullptr) {
        wl_compositor_destroy(m_compositor);
        m_compositor = nullptr;
    }

    for (auto& output : m_outputs) {
        if (output.output != nullptr) {
            wl_output_destroy(output.output);
            output.output = nullptr;
        }
    }

    if (m_registry != nullptr) {
        wl_registry_destroy(m_registry);
        m_registry = nullptr;
    }

    if (m_display != nullptr) {
        wl_display_disconnect(m_display);
        m_display = nullptr;
    }

    m_outputs.clear();
}

void WaylandConnection::logStartupSummary() const {
    logInfo("wayland connected compositor={} shm={} layer-shell={} xdg-output={} outputs={}",
        m_compositor != nullptr ? "yes" : "no",
        m_shm != nullptr ? "yes" : "no",
        hasLayerShell() ? "yes" : "no",
        hasXdgOutputManager() ? "yes" : "no",
        m_outputs.size());

    for (const auto& output : m_outputs) {
        logInfo("output global={} version={}", output.name, output.version);
    }
}

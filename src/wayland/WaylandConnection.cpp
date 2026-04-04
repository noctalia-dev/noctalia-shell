#include "wayland/WaylandConnection.hpp"

#include "core/Log.hpp"

#include <algorithm>
#include <stdexcept>

#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "cursor-shape-v1-client-protocol.h"
#include "ext-workspace-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kCompositorVersion = 4;
constexpr std::uint32_t kSeatVersion = 5;
constexpr std::uint32_t kShmVersion = 1;
constexpr std::uint32_t kLayerShellVersion = 4;
constexpr std::uint32_t kXdgOutputManagerVersion = 3;
constexpr std::uint32_t kExtWorkspaceManagerVersion = 1;
constexpr std::uint32_t kCursorShapeManagerVersion = 1;
constexpr std::uint32_t kOutputVersion = 4;

const wl_seat_listener kSeatListener = {
    .capabilities = &WaylandConnection::handleSeatCapabilities,
    .name = &WaylandConnection::handleSeatName,
};

const wl_pointer_listener kPointerListener = {
    .enter = &WaylandConnection::handlePointerEnter,
    .leave = &WaylandConnection::handlePointerLeave,
    .motion = &WaylandConnection::handlePointerMotion,
    .button = &WaylandConnection::handlePointerButton,
    .axis = [](void*, wl_pointer*, std::uint32_t, std::uint32_t, std::int32_t) {},
    .frame = &WaylandConnection::handlePointerFrame,
    .axis_source = [](void*, wl_pointer*, std::uint32_t) {},
    .axis_stop = [](void*, wl_pointer*, std::uint32_t, std::uint32_t) {},
    .axis_discrete = [](void*, wl_pointer*, std::uint32_t, std::int32_t) {},
    .axis_value120 = [](void*, wl_pointer*, std::uint32_t, std::int32_t) {},
    .axis_relative_direction = [](void*, wl_pointer*, std::uint32_t, std::uint32_t) {},
};

const wl_registry_listener kRegistryListener = {
    .global = &WaylandConnection::handleGlobal,
    .global_remove = &WaylandConnection::handleGlobalRemove,
};

void outputGeometry(void* /*data*/, wl_output* /*output*/,
                    int32_t /*x*/, int32_t /*y*/,
                    int32_t /*physW*/, int32_t /*physH*/,
                    int32_t /*subpixel*/,
                    const char* /*make*/, const char* /*model*/,
                    int32_t /*transform*/) {}

void outputMode(void* data, wl_output* wlOut,
                uint32_t flags, int32_t w, int32_t h, int32_t /*refresh*/) {
    if ((flags & WL_OUTPUT_MODE_CURRENT) == 0) {
        return;
    }
    auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
    if (out != nullptr) {
        out->width = w;
        out->height = h;
    }
}

void outputDone(void* data, wl_output* wlOut) {
    auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
    if (out != nullptr) {
        out->done = true;
    }
}

void outputScale(void* data, wl_output* wlOut, int32_t factor) {
    auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
    if (out != nullptr) {
        out->scale = factor;
    }
}

void outputName(void* data, wl_output* wlOut, const char* name) {
    auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
    if (out != nullptr && name != nullptr) {
        out->connectorName = name;
    }
}

void outputDescription(void* data, wl_output* wlOut, const char* desc) {
    auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
    if (out != nullptr) {
        out->description = desc;
    }
}

const wl_output_listener kOutputListener = {
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .name = outputName,
    .description = outputDescription,
};

void workspaceGroupCapabilities(void* /*data*/, ext_workspace_group_handle_v1* /*group*/, uint32_t /*caps*/) {}

void workspaceGroupOutputEnter(void* data, ext_workspace_group_handle_v1* group, wl_output* output) {
    static_cast<WaylandConnection*>(data)->onWorkspaceGroupOutputEnter(group, output);
}

void workspaceGroupOutputLeave(void* data, ext_workspace_group_handle_v1* group, wl_output* output) {
    static_cast<WaylandConnection*>(data)->onWorkspaceGroupOutputLeave(group, output);
}

void workspaceGroupWorkspaceEnter(void* data, ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
    static_cast<WaylandConnection*>(data)->onWorkspaceGroupWorkspaceEnter(group, workspace);
}

void workspaceGroupWorkspaceLeave(void* data, ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
    static_cast<WaylandConnection*>(data)->onWorkspaceGroupWorkspaceLeave(group, workspace);
}
void workspaceGroupRemoved(void* data, ext_workspace_group_handle_v1* group) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceGroupRemoved(group);
}

const ext_workspace_group_handle_v1_listener kWorkspaceGroupListener = {
    .capabilities = workspaceGroupCapabilities,
    .output_enter = workspaceGroupOutputEnter,
    .output_leave = workspaceGroupOutputLeave,
    .workspace_enter = workspaceGroupWorkspaceEnter,
    .workspace_leave = workspaceGroupWorkspaceLeave,
    .removed = workspaceGroupRemoved,
};

void workspaceId(void* data, ext_workspace_handle_v1* workspace, const char* id) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceIdChanged(workspace, id);
}

void workspaceName(void* data, ext_workspace_handle_v1* workspace, const char* name) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceNameChanged(workspace, name);
}

void workspaceCoordinates(void* data, ext_workspace_handle_v1* workspace, wl_array* coords) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceCoordinatesChanged(workspace, coords);
}

void workspaceState(void* data, ext_workspace_handle_v1* workspace, uint32_t state) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceStateChanged(workspace, state);
}

void workspaceCapabilities(void* /*data*/, ext_workspace_handle_v1* /*workspace*/, uint32_t /*caps*/) {}

void workspaceRemoved(void* data, ext_workspace_handle_v1* workspace) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceRemoved(workspace);
}

const ext_workspace_handle_v1_listener kWorkspaceListener = {
    .id = workspaceId,
    .name = workspaceName,
    .coordinates = workspaceCoordinates,
    .state = workspaceState,
    .capabilities = workspaceCapabilities,
    .removed = workspaceRemoved,
};

void workspaceManagerWorkspaceGroup(void* data,
                                    ext_workspace_manager_v1* /*manager*/,
                                    ext_workspace_group_handle_v1* group) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceGroupCreated(group);
}

void workspaceManagerWorkspace(void* data,
                               ext_workspace_manager_v1* /*manager*/,
                               ext_workspace_handle_v1* workspace) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceCreated(workspace);
}

void workspaceManagerDone(void* data, ext_workspace_manager_v1* /*manager*/) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceManagerDone();
}

void workspaceManagerFinished(void* data, ext_workspace_manager_v1* /*manager*/) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->onWorkspaceManagerFinished();
}

const ext_workspace_manager_v1_listener kWorkspaceManagerListener = {
    .workspace_group = workspaceManagerWorkspaceGroup,
    .workspace = workspaceManagerWorkspace,
    .done = workspaceManagerDone,
    .finished = workspaceManagerFinished,
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

void WaylandConnection::setPointerEventCallback(PointerEventCallback callback) {
    m_pointerEventCallback = std::move(callback);
}

void WaylandConnection::setCursorShape(std::uint32_t serial, std::uint32_t shape) {
    if (m_cursorShapeDevice != nullptr) {
        wp_cursor_shape_device_v1_set_shape(m_cursorShapeDevice, serial, shape);
    }
}

void WaylandConnection::activateWorkspace(const std::string& id) {
    if (m_workspaceManager == nullptr) {
        return;
    }

    for (const auto& [handle, ws] : m_workspaces) {
        if (ws.id == id) {
            ext_workspace_handle_v1_activate(handle);
            ext_workspace_manager_v1_commit(m_workspaceManager);
            logInfo("workspace: activating \"{}\"", ws.name);
            return;
        }
    }
}

void WaylandConnection::handleSeatCapabilities(void* data, wl_seat* seat, std::uint32_t caps) {
    auto* self = static_cast<WaylandConnection*>(data);

    const bool hasPointer = (caps & WL_SEAT_CAPABILITY_POINTER) != 0;

    if (hasPointer && self->m_pointer == nullptr) {
        self->m_pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(self->m_pointer, &kPointerListener, self);
        logInfo("pointer: bound");

        if (self->m_cursorShapeManager != nullptr) {
            self->m_cursorShapeDevice = wp_cursor_shape_manager_v1_get_pointer(
                self->m_cursorShapeManager, self->m_pointer);
            logInfo("pointer: cursor-shape-v1 available");
        }
    } else if (!hasPointer && self->m_pointer != nullptr) {
        if (self->m_cursorShapeDevice != nullptr) {
            wp_cursor_shape_device_v1_destroy(self->m_cursorShapeDevice);
            self->m_cursorShapeDevice = nullptr;
        }
        wl_pointer_destroy(self->m_pointer);
        self->m_pointer = nullptr;
        logInfo("pointer: released");
    }
}

void WaylandConnection::handleSeatName(void* /*data*/, wl_seat* /*seat*/, const char* /*name*/) {}

void WaylandConnection::handlePointerEnter(void* data, wl_pointer* /*pointer*/, std::uint32_t serial,
                                            wl_surface* surface, std::int32_t sx, std::int32_t sy) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->m_pendingPointerEvents.push_back(PointerEvent{
        .type = PointerEvent::Type::Enter,
        .serial = serial,
        .surface = surface,
        .sx = wl_fixed_to_double(sx),
        .sy = wl_fixed_to_double(sy),
    });
}

void WaylandConnection::handlePointerLeave(void* data, wl_pointer* /*pointer*/, std::uint32_t serial,
                                            wl_surface* surface) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->m_pendingPointerEvents.push_back(PointerEvent{
        .type = PointerEvent::Type::Leave,
        .serial = serial,
        .surface = surface,
    });
}

void WaylandConnection::handlePointerMotion(void* data, wl_pointer* /*pointer*/, std::uint32_t time,
                                             std::int32_t sx, std::int32_t sy) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->m_pendingPointerEvents.push_back(PointerEvent{
        .type = PointerEvent::Type::Motion,
        .sx = wl_fixed_to_double(sx),
        .sy = wl_fixed_to_double(sy),
        .time = time,
    });
}

void WaylandConnection::handlePointerButton(void* data, wl_pointer* /*pointer*/, std::uint32_t serial,
                                             std::uint32_t time, std::uint32_t button, std::uint32_t state) {
    auto* self = static_cast<WaylandConnection*>(data);
    self->m_pendingPointerEvents.push_back(PointerEvent{
        .type = PointerEvent::Type::Button,
        .serial = serial,
        .time = time,
        .button = button,
        .state = state,
    });
}

void WaylandConnection::handlePointerFrame(void* data, wl_pointer* /*pointer*/) {
    auto* self = static_cast<WaylandConnection*>(data);
    if (self->m_pointerEventCallback) {
        for (const auto& event : self->m_pendingPointerEvents) {
            self->m_pointerEventCallback(event);
        }
    }
    self->m_pendingPointerEvents.clear();
}

void WaylandConnection::setOutputChangeCallback(ChangeCallback callback) {
    m_outputChangeCallback = std::move(callback);
}

void WaylandConnection::setWorkspaceChangeCallback(ChangeCallback callback) {
    m_workspaceChangeCallback = std::move(callback);
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

bool WaylandConnection::hasExtWorkspaceManager() const noexcept {
    return m_workspaceManager != nullptr;
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
    const auto sizeBefore = self->m_outputs.size();
    std::erase_if(self->m_outputs, [name](const WaylandOutput& output) {
        return output.name == name;
    });
    if (self->m_outputs.size() != sizeBefore && self->m_outputChangeCallback) {
        self->m_outputChangeCallback();
    }
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
        wl_seat_add_listener(m_seat, &kSeatListener, this);
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
        const auto bindVersion = std::min(version, kLayerShellVersion);
        m_layerShell = static_cast<zwlr_layer_shell_v1*>(
            wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, bindVersion));
        return;
    }

    if (interfaceName == zxdg_output_manager_v1_interface.name) {
        const auto bindVersion = std::min(version, kXdgOutputManagerVersion);
        m_xdgOutputManager = static_cast<zxdg_output_manager_v1*>(
            wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, bindVersion));
        return;
    }

    if (interfaceName == ext_workspace_manager_v1_interface.name) {
        m_hasExtWorkspaceGlobal = true;
        const auto bindVersion = std::min(version, kExtWorkspaceManagerVersion);
        m_workspaceManager = static_cast<ext_workspace_manager_v1*>(
            wl_registry_bind(registry, name, &ext_workspace_manager_v1_interface, bindVersion));
        ext_workspace_manager_v1_add_listener(m_workspaceManager, &kWorkspaceManagerListener, this);
        return;
    }

    if (interfaceName == wp_cursor_shape_manager_v1_interface.name) {
        const auto bindVersion = std::min(version, kCursorShapeManagerVersion);
        m_cursorShapeManager = static_cast<wp_cursor_shape_manager_v1*>(
            wl_registry_bind(registry, name, &wp_cursor_shape_manager_v1_interface, bindVersion));
        return;
    }

    if (interfaceName == wl_output_interface.name) {
        const auto bindVersion = std::min(version, kOutputVersion);
        auto* output = static_cast<wl_output*>(
            wl_registry_bind(registry, name, &wl_output_interface, bindVersion));
        m_outputs.push_back(WaylandOutput{
            .name = name,
            .interfaceName = interfaceName,
            .connectorName = {},
            .description = {},
            .version = version,
            .output = output,
        });
        wl_output_add_listener(output, &kOutputListener, this);
        if (m_outputChangeCallback) {
            m_outputChangeCallback();
        }
    }
}

WaylandOutput* WaylandConnection::findOutputByWl(wl_output* wlOutput) {
    for (auto& out : m_outputs) {
        if (out.output == wlOutput) {
            return &out;
        }
    }
    return nullptr;
}

void WaylandConnection::onWorkspaceGroupCreated(ext_workspace_group_handle_v1* group) {
    if (group == nullptr) {
        return;
    }
    m_workspaceGroups.push_back(WorkspaceGroup{.handle = group, .outputs = {}, .workspaces = {}});
    ext_workspace_group_handle_v1_add_listener(group, &kWorkspaceGroupListener, this);
}

void WaylandConnection::onWorkspaceGroupRemoved(ext_workspace_group_handle_v1* group) {
    std::erase_if(m_workspaceGroups, [group](const auto& g) { return g.handle == group; });
    if (group != nullptr) {
        ext_workspace_group_handle_v1_destroy(group);
    }
}

void WaylandConnection::onWorkspaceGroupOutputEnter(ext_workspace_group_handle_v1* group, wl_output* output) {
    for (auto& g : m_workspaceGroups) {
        if (g.handle == group) {
            g.outputs.push_back(output);
            return;
        }
    }
}

void WaylandConnection::onWorkspaceGroupOutputLeave(ext_workspace_group_handle_v1* group, wl_output* output) {
    for (auto& g : m_workspaceGroups) {
        if (g.handle == group) {
            std::erase(g.outputs, output);
            return;
        }
    }
}

void WaylandConnection::onWorkspaceGroupWorkspaceEnter(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
    for (auto& g : m_workspaceGroups) {
        if (g.handle == group) {
            g.workspaces.push_back(workspace);
            return;
        }
    }
}

void WaylandConnection::onWorkspaceGroupWorkspaceLeave(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace) {
    for (auto& g : m_workspaceGroups) {
        if (g.handle == group) {
            std::erase(g.workspaces, workspace);
            return;
        }
    }
}

void WaylandConnection::onWorkspaceCreated(ext_workspace_handle_v1* workspace) {
    if (workspace == nullptr) {
        return;
    }
    m_workspaces.emplace(workspace, WaylandConnection::Workspace{});
    ext_workspace_handle_v1_add_listener(workspace, &kWorkspaceListener, this);
}

void WaylandConnection::onWorkspaceIdChanged(ext_workspace_handle_v1* workspace, const char* id) {
    const auto it = m_workspaces.find(workspace);
    if (it == m_workspaces.end()) {
        return;
    }
    it->second.id = id != nullptr ? id : "";
}

void WaylandConnection::onWorkspaceNameChanged(ext_workspace_handle_v1* workspace, const char* name) {
    const auto it = m_workspaces.find(workspace);
    if (it == m_workspaces.end()) {
        return;
    }
    it->second.name = name != nullptr ? name : "";
}

void WaylandConnection::onWorkspaceCoordinatesChanged(ext_workspace_handle_v1* workspace, wl_array* coordinates) {
    const auto it = m_workspaces.find(workspace);
    if (it == m_workspaces.end()) {
        return;
    }
    
    it->second.coordinates.clear();
    if (coordinates != nullptr) {
        const auto* coords = static_cast<std::uint32_t*>(coordinates->data);
        const auto count = coordinates->size / sizeof(std::uint32_t);
        it->second.coordinates.assign(coords, coords + count);
    }
}

void WaylandConnection::onWorkspaceStateChanged(ext_workspace_handle_v1* workspace, std::uint32_t state) {
    const auto it = m_workspaces.find(workspace);
    if (it == m_workspaces.end()) {
        return;
    }

    const bool is_active = (state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE) != 0;
    if (it->second.active != is_active) {
        it->second.active = is_active;
        if (is_active) {
            const std::string label = it->second.name.empty() ? "(unnamed)" : it->second.name;
            logInfo("workspace active: {}", label);
        }
        if (m_workspaceChangeCallback) {
            m_workspaceChangeCallback();
        }
    }
}

void WaylandConnection::onWorkspaceRemoved(ext_workspace_handle_v1* workspace) {
    m_workspaces.erase(workspace);
    if (workspace != nullptr) {
        ext_workspace_handle_v1_destroy(workspace);
    }
}

void WaylandConnection::onWorkspaceManagerDone() {
    if (m_workspaceChangeCallback) {
        m_workspaceChangeCallback();
    }
}

void WaylandConnection::onWorkspaceManagerFinished() {
    m_workspaceManager = nullptr;
    m_workspaces.clear();
    m_workspaceGroups.clear();
}

void WaylandConnection::cleanup() {
    for (auto& [workspace, _] : m_workspaces) {
        if (workspace != nullptr) {
            ext_workspace_handle_v1_destroy(workspace);
        }
    }
    m_workspaces.clear();

    for (auto& group : m_workspaceGroups) {
        if (group.handle != nullptr) {
            ext_workspace_group_handle_v1_destroy(group.handle);
        }
    }
    m_workspaceGroups.clear();

    if (m_workspaceManager != nullptr) {
        ext_workspace_manager_v1_stop(m_workspaceManager);
        ext_workspace_manager_v1_destroy(m_workspaceManager);
        m_workspaceManager = nullptr;
    }

    if (m_xdgOutputManager != nullptr) {
        zxdg_output_manager_v1_destroy(m_xdgOutputManager);
        m_xdgOutputManager = nullptr;
    }

    if (m_layerShell != nullptr) {
        zwlr_layer_shell_v1_destroy(m_layerShell);
        m_layerShell = nullptr;
    }

    if (m_cursorShapeDevice != nullptr) {
        wp_cursor_shape_device_v1_destroy(m_cursorShapeDevice);
        m_cursorShapeDevice = nullptr;
    }

    if (m_cursorShapeManager != nullptr) {
        wp_cursor_shape_manager_v1_destroy(m_cursorShapeManager);
        m_cursorShapeManager = nullptr;
    }

    if (m_pointer != nullptr) {
        wl_pointer_destroy(m_pointer);
        m_pointer = nullptr;
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
    m_hasExtWorkspaceGlobal = false;
}

std::vector<WaylandConnection::Workspace> WaylandConnection::workspaces() const {
    // Deduplicate by name -- ext-workspace reports per output group,
    // so the same logical workspace appears multiple times. Sort by coordinates.
    std::vector<Workspace> result;
    std::vector<ext_workspace_handle_v1*> seen;
    
    // Iterate through groups to collect all workspaces
    for (const auto& group : m_workspaceGroups) {
        for (auto* handle : group.workspaces) {
            // Skip if we've already added this workspace
            if (std::find(seen.begin(), seen.end(), handle) != seen.end()) {
                continue;
            }
            
            auto it = m_workspaces.find(handle);
            if (it != m_workspaces.end() && !it->second.name.empty()) {
                result.push_back(Workspace{.id = it->second.id, .name = it->second.name, .coordinates = it->second.coordinates, .active = it->second.active});
                seen.push_back(handle);
            }
        }
    }
    
    // Add workspaces that aren't in any group (shouldn't happen, but handle it)
    for (const auto& [handle, ws] : m_workspaces) {
        if (ws.name.empty() || std::find(seen.begin(), seen.end(), handle) != seen.end()) {
            continue;
        }
        result.push_back(Workspace{.id = ws.id, .name = ws.name, .coordinates = ws.coordinates, .active = ws.active});
    }
    
    // Sort by workspace coordinates (lexicographic multi-dimensional)
    std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) {
        return a.coordinates < b.coordinates;
    });
    
    return result;
}

std::vector<WaylandConnection::Workspace> WaylandConnection::workspaces(wl_output* output) const {
    // Collect workspace handles that belong to groups containing this output
    // Sort by coordinates for proper ordering
    std::vector<ext_workspace_handle_v1*> handles;
    for (const auto& group : m_workspaceGroups) {
        bool hasOutput = std::find(group.outputs.begin(), group.outputs.end(), output) != group.outputs.end();
        if (hasOutput) {
            handles.insert(handles.end(), group.workspaces.begin(), group.workspaces.end());
        }
    }

    std::vector<Workspace> result;
    for (auto* handle : handles) {
        auto it = m_workspaces.find(handle);
        if (it != m_workspaces.end() && !it->second.name.empty()) {
            result.push_back(Workspace{.id = it->second.id, .name = it->second.name, .coordinates = it->second.coordinates, .active = it->second.active});
        }
    }

    // Sort by workspace coordinates (lexicographic multi-dimensional)
    std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) {
        return a.coordinates < b.coordinates;
    });

    return result;
}

void WaylandConnection::logStartupSummary() const {
    logInfo("wayland connected compositor={} shm={} layer-shell={} xdg-output={} ext-workspace={} outputs={}",
        m_compositor != nullptr ? "yes" : "no",
        m_shm != nullptr ? "yes" : "no",
        hasLayerShell() ? "yes" : "no",
        hasXdgOutputManager() ? "yes" : "no",
        hasExtWorkspaceManager() ? "yes" : "no",
        m_outputs.size());

    for (const auto& output : m_outputs) {
        logInfo("output {} global={} scale={} mode={}x{} desc=\"{}\"",
            output.connectorName, output.name, output.scale,
            output.width, output.height, output.description);
    }
}

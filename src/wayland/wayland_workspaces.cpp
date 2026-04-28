#include "wayland/wayland_workspaces.h"

#include "compositors/ext_workspace/ext_workspace_backend.h"
#include "compositors/hyprland/hyprland_workspace_backend.h"
#include "compositors/mango/mango_workspace_backend.h"
#include "compositors/output_backend.h"
#include "compositors/sway/sway_workspace_backend.h"
#include "core/log.h"
#include "util/string_utils.h"

#include <string>

namespace {

  constexpr Logger kLog("workspace");

} // namespace

WaylandWorkspaces::WaylandWorkspaces() {
  m_extBackend = std::make_unique<ExtWorkspaceBackend>();
  m_mangoBackend = std::make_unique<MangoWorkspaceBackend>();
  m_hyprlandBackend = std::make_unique<HyprlandWorkspaceBackend>([](wl_output* /*output*/) { return std::string{}; });
  m_swayBackend = std::make_unique<SwayWorkspaceBackend>([](wl_output* /*output*/) { return std::string{}; });
  m_outputBackends.push_back(m_mangoBackend.get());
}

WaylandWorkspaces::~WaylandWorkspaces() = default;

void WaylandWorkspaces::bindExtWorkspace(ext_workspace_manager_v1* manager) {
  if (m_extBackend != nullptr) {
    m_extBackend->bind(manager);
  }
}

void WaylandWorkspaces::bindMangoWorkspace(zdwl_ipc_manager_v2* manager) {
  if (m_mangoBackend != nullptr) {
    m_mangoBackend->bind(manager);
  }
}

void WaylandWorkspaces::setSwayOutputNameResolver(std::function<std::string(wl_output*)> resolver) {
  if (m_swayBackend != nullptr) {
    m_swayBackend->setOutputNameResolver(std::move(resolver));
  }
}

void WaylandWorkspaces::setHyprlandOutputNameResolver(std::function<std::string(wl_output*)> resolver) {
  if (m_hyprlandBackend != nullptr) {
    m_hyprlandBackend->setOutputNameResolver(std::move(resolver));
  }
}

void WaylandWorkspaces::initialize(std::string_view compositorHint) {
  if (StringUtils::containsInsensitive(compositorHint, "hyprland") ||
      StringUtils::containsInsensitive(compositorHint, "hypr")) {
    if (m_hyprlandBackend != nullptr && (m_hyprlandBackend->isAvailable() || m_hyprlandBackend->connectSocket())) {
      setActiveBackend(m_hyprlandBackend.get());
      return;
    }
  }
  if (StringUtils::containsInsensitive(compositorHint, "mango")) {
    if (m_mangoBackend != nullptr && m_mangoBackend->isAvailable()) {
      setActiveBackend(m_mangoBackend.get());
      return;
    }
  }
  if (StringUtils::containsInsensitive(compositorHint, "sway")) {
    if (m_swayBackend != nullptr && (m_swayBackend->isAvailable() || m_swayBackend->connectSocket())) {
      setActiveBackend(m_swayBackend.get());
      return;
    }
  }

  if (m_extBackend != nullptr && m_extBackend->isAvailable()) {
    setActiveBackend(m_extBackend.get());
    return;
  }
  if (m_hyprlandBackend != nullptr && (m_hyprlandBackend->isAvailable() || m_hyprlandBackend->connectSocket())) {
    setActiveBackend(m_hyprlandBackend.get());
    return;
  }
  if (m_mangoBackend != nullptr && m_mangoBackend->isAvailable()) {
    setActiveBackend(m_mangoBackend.get());
    return;
  }
  if (m_swayBackend != nullptr && (m_swayBackend->isAvailable() || m_swayBackend->connectSocket())) {
    setActiveBackend(m_swayBackend.get());
    return;
  }

  setActiveBackend(nullptr);
}

void WaylandWorkspaces::onOutputAdded(wl_output* output) {
  for (auto* backend : m_outputBackends) {
    if (backend != nullptr) {
      backend->onOutputAdded(output);
    }
  }
}

void WaylandWorkspaces::onOutputRemoved(wl_output* output) {
  for (auto* backend : m_outputBackends) {
    if (backend != nullptr) {
      backend->onOutputRemoved(output);
    }
  }
}

void WaylandWorkspaces::setChangeCallback(ChangeCallback callback) {
  m_changeCallback = std::move(callback);
  auto wrapper = [this]() { notifyChanged(); };
  if (m_extBackend != nullptr) {
    m_extBackend->setChangeCallback(wrapper);
  }
  if (m_mangoBackend != nullptr) {
    m_mangoBackend->setChangeCallback(wrapper);
  }
  if (m_hyprlandBackend != nullptr) {
    m_hyprlandBackend->setChangeCallback(wrapper);
  }
  if (m_swayBackend != nullptr) {
    m_swayBackend->setChangeCallback(wrapper);
  }
}

void WaylandWorkspaces::activate(const std::string& id) {
  if (m_activeBackend != nullptr) {
    m_activeBackend->activate(id);
  }
}

void WaylandWorkspaces::activateForOutput(wl_output* output, const std::string& id) {
  if (m_activeBackend != nullptr) {
    m_activeBackend->activateForOutput(output, id);
  }
}

void WaylandWorkspaces::activateForOutput(wl_output* output, const Workspace& workspace) {
  if (m_activeBackend != nullptr) {
    m_activeBackend->activateForOutput(output, workspace);
  }
}

void WaylandWorkspaces::cleanup() {
  if (m_swayBackend != nullptr) {
    m_swayBackend->cleanup();
  }
  if (m_hyprlandBackend != nullptr) {
    m_hyprlandBackend->cleanup();
  }
  if (m_mangoBackend != nullptr) {
    m_mangoBackend->cleanup();
  }
  if (m_extBackend != nullptr) {
    m_extBackend->cleanup();
  }
  m_activeBackend = nullptr;
}

int WaylandWorkspaces::pollFd() const noexcept { return m_activeBackend != nullptr ? m_activeBackend->pollFd() : -1; }

short WaylandWorkspaces::pollEvents() const noexcept {
  return m_activeBackend != nullptr ? m_activeBackend->pollEvents() : static_cast<short>(POLLIN);
}

int WaylandWorkspaces::pollTimeoutMs() const noexcept {
  return m_activeBackend != nullptr ? m_activeBackend->pollTimeoutMs() : -1;
}

void WaylandWorkspaces::dispatchPoll(short revents) {
  if (m_activeBackend != nullptr) {
    m_activeBackend->dispatchPoll(revents);
  }
}

const char* WaylandWorkspaces::backendName() const noexcept {
  return m_activeBackend != nullptr ? m_activeBackend->backendName() : "none";
}

std::vector<Workspace> WaylandWorkspaces::all() const {
  return m_activeBackend != nullptr ? m_activeBackend->all() : std::vector<Workspace>{};
}

std::vector<Workspace> WaylandWorkspaces::forOutput(wl_output* output) const {
  return m_activeBackend != nullptr ? m_activeBackend->forOutput(output) : std::vector<Workspace>{};
}

void WaylandWorkspaces::setActiveBackend(WorkspaceBackend* backend) {
  m_activeBackend = backend;
  kLog.info("workspace backend={}", backendName());
}

void WaylandWorkspaces::notifyChanged() const {
  if (m_changeCallback) {
    m_changeCallback();
  }
}

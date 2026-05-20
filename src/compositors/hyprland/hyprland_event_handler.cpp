#include "compositors/hyprland/hyprland_event_handler.h"

#include "compositors/hyprland/hyprland_runtime.h"

namespace compositors::hyprland {

  HyprlandEventHandler::HyprlandEventHandler(HyprlandRuntime& runtime) : m_runtime(runtime) {
    m_runtime.registerEventHandler(this);
  }

  HyprlandEventHandler::~HyprlandEventHandler() { m_runtime.unregisterEventHandler(this); }

} // namespace compositors::hyprland

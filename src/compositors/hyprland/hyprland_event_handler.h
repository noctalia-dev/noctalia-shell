#pragma once

#include <string_view>

namespace compositors::hyprland {

  class HyprlandRuntime;

  class HyprlandEventHandler {
  public:
    explicit HyprlandEventHandler(HyprlandRuntime& runtime);
    virtual ~HyprlandEventHandler();

    virtual void handleEvent(std::string_view event, std::string_view data) = 0;
    virtual void notifyCleanup() {};
    virtual void notifyChanged() {};

  protected:
    HyprlandRuntime& m_runtime;
  };

} // namespace compositors::hyprland

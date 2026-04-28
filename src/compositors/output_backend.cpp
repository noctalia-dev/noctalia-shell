#include "compositors/output_backend.h"

#include "compositors/compositor_detect.h"
#include "compositors/ext_workspace_output_backend.h"
#include "compositors/hyprland/hyprland_output_backend.h"
#include "compositors/mango/mango_output_backend.h"
#include "compositors/niri/niri_output_backend.h"
#include "compositors/sway/sway_output_backend.h"

namespace compositors {

  bool setOutputPower(WaylandConnection& wayland, bool on) {
    switch (detect()) {
    case CompositorKind::Hyprland:
      return hyprland::setOutputPower(on);
    case CompositorKind::Niri:
      return niri::setOutputPower(on);
    case CompositorKind::Sway:
      return sway::setOutputPower(on);
    case CompositorKind::Mango:
      return mango::setOutputPower(wayland, on);
    case CompositorKind::Unknown:
      return ext_workspace::setOutputPower(on);
    }
    return false;
  }

} // namespace compositors

#pragma once

#include "shell/desktop/desktop_widgets_controller.h"
#include "shell/desktop/widget_transform.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <string>

namespace desktop_widgets {

  inline std::string outputKey(const WaylandOutput& output) {
    if (!output.connectorName.empty()) {
      return output.connectorName;
    }
    return std::to_string(output.name);
  }

  inline const WaylandOutput* resolveEffectiveOutput(const WaylandConnection& wayland,
                                                     const std::string& requestedOutput) {
    const auto& outputs = wayland.outputs();
    const WaylandOutput* primary = nullptr;
    for (const auto& output : outputs) {
      if (!output.done || output.output == nullptr) {
        continue;
      }
      if (primary == nullptr) {
        primary = &output;
      }
      if (!requestedOutput.empty() && outputKey(output) == requestedOutput) {
        return &output;
      }
    }
    return primary;
  }

  inline float outputLogicalWidth(const WaylandOutput& output) {
    if (output.logicalWidth > 0) {
      return static_cast<float>(output.logicalWidth);
    }
    return static_cast<float>(std::max(1, output.width / std::max(1, output.scale)));
  }

  inline float outputLogicalHeight(const WaylandOutput& output) {
    if (output.logicalHeight > 0) {
      return static_cast<float>(output.logicalHeight);
    }
    return static_cast<float>(std::max(1, output.height / std::max(1, output.scale)));
  }

  // Single source of truth for desktop widget coordinate clamping. Edit mode, default mode, and
  // snapshot normalization all route through here so the visibility rule stays identical. Resolves
  // the widget's effective output, then constrains state.cx/cy so that at least
  // kDesktopWidgetMinVisibleFraction of the widget's transformed AABB remains on screen.
  inline const WaylandOutput* clampStateToOutput(const WaylandConnection& wayland, DesktopWidgetState& state,
                                                 float intrinsicWidth, float intrinsicHeight) {
    const WaylandOutput* output = resolveEffectiveOutput(wayland, state.outputName);
    if (output == nullptr) {
      return nullptr;
    }
    const WidgetTransformClampResult clamped = clampWidgetCenterToOutput(
        state.cx, state.cy, intrinsicWidth, intrinsicHeight, state.scale, state.rotationRad,
        outputLogicalWidth(*output), outputLogicalHeight(*output), kDesktopWidgetMinVisibleFraction);
    state.cx = clamped.cx;
    state.cy = clamped.cy;
    return output;
  }

} // namespace desktop_widgets

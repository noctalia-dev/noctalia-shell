#pragma once

#include "shell/desktop/desktop_widgets_controller.h"
#include "shell/desktop/widget_transform.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <string>

namespace desktop_widgets {

  // Base content scale for a widget: the UI scale, times any legacy (schema v1) scale while the
  // tile is still unsized. Once the tile has an explicit box, the content-fit derived from it in
  // DesktopWidget::layout() takes over and the legacy scale no longer applies.
  inline float widgetContentScale(float baseUiScale, const DesktopWidgetState& state) {
    const bool boxed = state.boxWidth > 0.0f && state.boxHeight > 0.0f;
    const float legacy = boxed ? 1.0f : std::max(0.01f, state.legacyScale);
    return std::max(0.01f, baseUiScale) * legacy;
  }

  inline std::string outputKey(const WaylandOutput& output) {
    if (!output.connectorName.empty()) {
      return output.connectorName;
    }
    return std::to_string(output.name);
  }

  inline const WaylandOutput* findOutputByKey(const WaylandConnection& wayland, const std::string& key) {
    if (key.empty()) {
      return nullptr;
    }
    for (const auto& output : wayland.outputs()) {
      if (!output.done || output.output == nullptr) {
        continue;
      }
      if (outputKey(output) == key) {
        return &output;
      }
    }
    return nullptr;
  }

  inline const WaylandOutput*
  resolveEffectiveOutput(const WaylandConnection& wayland, const std::string& requestedOutput) {
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
    if (!requestedOutput.empty()) {
      return nullptr;
    }
    return primary;
  }

  inline const WaylandOutput* resolveStateOutput(const WaylandConnection& wayland, const DesktopWidgetState& state) {
    if (state.outputName.empty()) {
      return resolveEffectiveOutput(wayland, state.outputName);
    }
    return findOutputByKey(wayland, state.outputName);
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
  // kDesktopWidgetMinVisibleFraction of the widget's rotated AABB remains on screen. The caller
  // passes the widget's current box size as intrinsicWidth/intrinsicHeight, so no extra scale
  // multiplier is applied here.
  inline const WaylandOutput* clampStateToOutput(
      const WaylandConnection& wayland, DesktopWidgetState& state, float intrinsicWidth, float intrinsicHeight
  ) {
    const WaylandOutput* output = resolveStateOutput(wayland, state);
    if (output == nullptr) {
      return nullptr;
    }
    const WidgetTransformClampResult clamped = clampWidgetCenterToOutput(
        state.cx, state.cy, intrinsicWidth, intrinsicHeight, 1.0f, state.rotationRad, outputLogicalWidth(*output),
        outputLogicalHeight(*output), kDesktopWidgetMinVisibleFraction
    );
    state.cx = clamped.cx;
    state.cy = clamped.cy;
    return output;
  }

} // namespace desktop_widgets

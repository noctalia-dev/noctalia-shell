#pragma once

#include "config/config_types.h"

#include <string_view>

// Shared layout snapshot for desktop and lockscreen widget editors.
using WidgetsEditorSnapshot = DesktopWidgetsConfig;

struct BackgroundWidgetsEditorProfile {
  std::string_view logSection;
  std::string_view layerNamespace;
  std::string_view widgetIdPrefix;
  bool showLockscreenLoginPreview = false;

  [[nodiscard]] static BackgroundWidgetsEditorProfile desktop();
  [[nodiscard]] static BackgroundWidgetsEditorProfile lockscreen();
};

[[nodiscard]] inline WidgetsEditorSnapshot toWidgetsEditorSnapshot(const LockscreenWidgetsConfig& config) {
  return WidgetsEditorSnapshot{
      .enabled = config.enabled,
      .schemaVersion = config.schemaVersion,
      .grid = config.grid,
      .widgets = config.widgets,
  };
}

[[nodiscard]] inline LockscreenWidgetsConfig fromWidgetsEditorSnapshot(const WidgetsEditorSnapshot& snapshot) {
  return LockscreenWidgetsConfig{
      .enabled = snapshot.enabled,
      .schemaVersion = snapshot.schemaVersion,
      .grid = snapshot.grid,
      .widgets = snapshot.widgets,
  };
}

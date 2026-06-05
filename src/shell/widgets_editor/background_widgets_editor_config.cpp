#include "shell/widgets_editor/background_widgets_editor_config.h"

BackgroundWidgetsEditorProfile BackgroundWidgetsEditorProfile::desktop() {
  return BackgroundWidgetsEditorProfile{
      .logSection = "desktop",
      .layerNamespace = "noctalia-desktop-widgets-editor",
      .widgetIdPrefix = "desktop-widget-",
      .showLockscreenLoginPreview = false,
  };
}

BackgroundWidgetsEditorProfile BackgroundWidgetsEditorProfile::lockscreen() {
  return BackgroundWidgetsEditorProfile{
      .logSection = "lockscreen",
      .layerNamespace = "noctalia-lockscreen-widgets-editor",
      .widgetIdPrefix = "lockscreen-widget-",
      .showLockscreenLoginPreview = true,
  };
}

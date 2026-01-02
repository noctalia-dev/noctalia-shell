import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Media
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  enabled: ProgramCheckerService.gpuScreenRecorderAvailable
  icon: "camera-video"
  hot: ScreenRecorderService.isRecording
  tooltipText: I18n.tr("quickSettings.screenRecorder.tooltip.action")
  onClicked: {
    ScreenRecorderService.toggleRecording();
    if (!ScreenRecorderService.isRecording) {
      PanelService.getPanel("controlCenterPanel", screen)?.close;
    }
  }

  onRightClicked: {
    var settingsPanel = PanelService.getPanel("settingsPanel", screen);
    settingsPanel.requestedTab = SettingsPanel.Tab.ScreenRecorder;
    settingsPanel.open();
  }
}

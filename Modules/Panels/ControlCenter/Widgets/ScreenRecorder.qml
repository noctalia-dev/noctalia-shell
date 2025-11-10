import QtQuick.Layouts
import Quickshell
import qs.Commons
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
    ScreenRecorderService.toggleRecording()
    if (!ScreenRecorderService.isRecording) {
      PanelService.getPanel("controlCenterPanel", screen)?.close
    }
  }
}

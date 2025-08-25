import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Screen Recording Indicator
NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  visible: ScreenRecorderService.isRecording
  icon: "videocam"
  tooltipText: "Screen Recording Active\nClick To Stop Recording"
  sizeMultiplier: 0.8
  colorBg: Color.mPrimary
  colorFg: Color.mOnPrimary
  anchors.verticalCenter: parent.verticalCenter
  onClicked: ScreenRecorderService.toggleRecording()
}

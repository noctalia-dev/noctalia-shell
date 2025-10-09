import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Screen Recording Indicator
NIconButton {
  id: root

  property real scaling: 1.0

  icon: "camera-video"
  tooltipText: ScreenRecorderService.isRecording ? I18n.tr("tooltips.click-to-stop-recording") : I18n.tr("tooltips.click-to-start-recording")
  tooltipDirection: BarService.getTooltipDirection()
  compact: (Settings.data.bar.density === "compact")
  baseSize: Style.capsuleHeight
  colorBg: ScreenRecorderService.isRecording ? Color.mPrimary : (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: ScreenRecorderService.isRecording ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  function handleClick() {
    if (!ScreenRecorderService.isAvailable) {
      ToastService.showError(I18n.tr("toast.recording.not-installed"), I18n.tr("toast.recording.not-installed-desc"), 7000)
      return
    }
    ScreenRecorderService.toggleRecording()
  }

  onClicked: handleClick()
}

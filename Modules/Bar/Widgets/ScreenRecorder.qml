import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Services.Media
import qs.Services.System
import qs.Widgets

// Screen Recording Indicator
NIconButton {
  id: root

  property ShellScreen screen

  icon: "camera-video"
  tooltipText: ScreenRecorderService.isRecording ? I18n.tr("tooltips.click-to-stop-recording") : I18n.tr("tooltips.click-to-start-recording")
  tooltipDirection: BarService.getTooltipDirection()
  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  colorBg: ScreenRecorderService.isRecording ? Color.mPrimary : (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: ScreenRecorderService.isRecording ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  function handleClick() {
    if (!ScreenRecorderService.isAvailable) {
      ToastService.showError(I18n.tr("toast.recording.not-installed"), I18n.tr("toast.recording.not-installed-desc"))
      return
    }
    ScreenRecorderService.toggleRecording()
  }

  onClicked: handleClick()
}

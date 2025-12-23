import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Media
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Screen Recording Indicator
NIconButton {
  id: root

  property ShellScreen screen

  icon: ScreenRecorderService.isPending ? "" : "camera-video"
  tooltipText: ScreenRecorderService.isRecording ? I18n.tr("tooltips.click-to-stop-recording") : I18n.tr("tooltips.click-to-start-recording")
  tooltipDirection: BarService.getTooltipDirection()
  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: ScreenRecorderService.isRecording ? Color.mPrimary : Style.capsuleColor
  colorFg: ScreenRecorderService.isRecording ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  function handleClick() {
    if (!ScreenRecorderService.isAvailable) {
      ToastService.showError(I18n.tr("toast.recording.not-installed"), I18n.tr("toast.recording.not-installed-desc"));
      return;
    }
    ScreenRecorderService.toggleRecording();
  }

  onClicked: handleClick()

  onRightClicked: {
    var settingsPanel = PanelService.getPanel("settingsPanel", screen);
    settingsPanel.requestedTab = SettingsPanel.Tab.ScreenRecorder;
    settingsPanel.open();
  }

  // Custom spinner shown only during pending start
  NIcon {
    id: pendingSpinner
    icon: "loader-2"
    visible: ScreenRecorderService.isPending
    pointSize: {
      switch (root.density) {
      case "compact":
        return Math.max(1, root.width * 0.65);
      default:
        return Math.max(1, root.width * 0.48);
      }
    }
    applyUiScale: root.applyUiScale
    color: root.enabled && root.hovering ? colorFgHover : colorFg
    anchors.centerIn: parent
    transformOrigin: Item.Center

    RotationAnimation on rotation {
      running: ScreenRecorderService.isPending
      from: 0
      to: 360
      duration: Style.animationSlow
      loops: Animation.Infinite
      onStopped: pendingSpinner.rotation = 0
    }
  }
}

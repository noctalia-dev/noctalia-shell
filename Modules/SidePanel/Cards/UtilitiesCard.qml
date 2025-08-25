import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.SettingsPanel
import qs.Services
import qs.Widgets

// Utilities: record & wallpaper
NBox {

  property real spacing: 0

  Layout.fillWidth: true
  Layout.preferredWidth: 1
  implicitHeight: utilRow.implicitHeight + Style.marginM * 2 * scaling
  RowLayout {
    id: utilRow
    anchors.fill: parent
    anchors.margins: Style.marginS * scaling
    spacing: spacing
    Item {
      Layout.fillWidth: true
    }
    // Screen Recorder
    NIconButton {
      icon: "videocam"
      tooltipText: ScreenRecorderService.isRecording ? "Stop Screen Recording" : "Start Screen Recording"
      colorBg: ScreenRecorderService.isRecording ? Color.mPrimary : Color.mSurfaceVariant
      colorFg: ScreenRecorderService.isRecording ? Color.mOnPrimary : Color.mPrimary
      onClicked: {
        ScreenRecorderService.toggleRecording()
      }
    }

    // Idle Inhibitor
    NIconButton {
      icon: "coffee"
      tooltipText: IdleInhibitorService.isInhibited ? "Disable Keep Awake" : "Enable Keep Awake"
      colorBg: IdleInhibitorService.isInhibited ? Color.mPrimary : Color.mSurfaceVariant
      colorFg: IdleInhibitorService.isInhibited ? Color.mOnPrimary : Color.mPrimary
      onClicked: {
        IdleInhibitorService.manualToggle()
      }
    }

    // Wallpaper
    NIconButton {
      icon: "image"
      tooltipText: "Open Wallpaper Selector"
      onClicked: {
        var settingsPanel = PanelService.getPanel("settingsPanel")
        settingsPanel.requestedTab = SettingsPanel.Tab.WallpaperSelector
        settingsPanel.open(screen)
      }
    }

    Item {
      Layout.fillWidth: true
    }
  }
}

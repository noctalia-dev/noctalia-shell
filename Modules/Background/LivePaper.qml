import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Multimedia
import qs.Services.UI

/**
 * LivePaper — projectM Milkdrop visualization as desktop background.
 *
 * One PanelWindow per screen at WlrLayer.Background.
 * Preset selection is driven by ProjectMService (shared across all screens
 * and the lock screen for coherent visualization).
 */
Variants {
  id: livePaperVariants
  model: Quickshell.screens

  delegate: Loader {
    required property ShellScreen modelData

    active: modelData && Settings.data.wallpaper.livePaperEnabled

    sourceComponent: PanelWindow {
      id: win
      screen: modelData

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-livepaper-" + (screen?.name || "unknown")

      anchors {
        bottom: true
        top: true
        right: true
        left: true
      }

      color: "transparent"

      ProjectMItem {
        id: projM
        anchors.fill: parent
        running: true
        autoPresets: false
        darken: 0.6
        meshWidth: 24
        meshHeight: 18
        fps: 30

        Component.onCompleted: {
          if (ProjectMService.currentPreset !== "")
            requestPreset(ProjectMService.currentPreset)
        }
      }

      Connections {
        target: ProjectMService
        function onCurrentPresetChanged() {
          projM.requestPreset(ProjectMService.currentPreset)
        }
      }
    }
  }
}

import QtQuick
import Quickshell
import QtQuick.Effects
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Loader {
  active: CompositorService.isNiri && Settings.data.wallpaper.enabled && Settings.data.wallpaper.overviewEnabled

  sourceComponent: Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: panelWindow

      required property ShellScreen modelData
      property string wallpaper: ""
      property bool overviewIsSeen: false

      Component.onCompleted: {
        if (modelData) {
          Logger.d("Overview", "Loading overview for Niri on", modelData.name)
        }
        setWallpaperInitial()
      }

      Component.onDestruction: {
        // Clean up resources to prevent memory leak when overviewEnabled is toggled off
        timerDisableFx.stop()
        bgImage.layer.enabled = false
        bgImage.source = ""
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            wallpaper = path
          }
        }
      }

      Connections {
        target: CompositorService.backend
        function onOverviewActiveChanged() {
          if (CompositorService.backend.overviewActive) {
            overviewIsSeen = true
            timerDisableFx.stop()
          } else {
            timerDisableFx.restart()
          }
        }
      }

      // Use to disable effects when overview is no longer necessary.
      Timer {
        id: timerDisableFx
        interval: 2000
        onTriggered: {
          overviewIsSeen = false
        }
      }

      function setWallpaperInitial() {
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial)
          return
        }
        const wallpaperPath = WallpaperService.getWallpaper(modelData.name)
        if (wallpaperPath && wallpaperPath !== wallpaper) {
          wallpaper = wallpaperPath
        }
      }

      color: Color.transparent
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-overview-" + (screen?.name || "unknown")

      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      Image {
        id: bgImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: wallpaper
        smooth: false
        mipmap: false
        cache: false
        asynchronous: true
        visible: overviewIsSeen

        // Image is heavily blurred, so use low resolution to save memory
        sourceSize: Qt.size(1280, 720)

        layer.enabled: overviewIsSeen
        layer.smooth: false
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 32
        }

        Rectangle {
          anchors.fill: parent
          color: Settings.data.colorSchemes.darkMode ? Color.mSurface : Color.mOnSurface
          opacity: 0.8
        }
      }
    }
  }
}

import QtQuick
import QtQuick.Effects
import Quickshell
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
      property string cachedWallpaper: ""

      Component.onCompleted: {
        if (modelData) {
          Logger.d("Overview", "Loading overview for Niri on", modelData.name);
        }
        setWallpaperInitial();
      }

      Component.onDestruction: {
        // Clean up resources to prevent memory leak when overviewEnabled is toggled off
        bgImage.layer.enabled = false;
        bgImage.source = "";
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            wallpaper = path;
          }
        }
      }

      function setWallpaperInitial() {
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }
        const wallpaperPath = WallpaperService.getWallpaper(modelData.name);
        if (wallpaperPath && wallpaperPath !== wallpaper) {
          wallpaper = wallpaperPath;
        }
      }

      // Request cached wallpaper when source changes
      onWallpaperChanged: {
        if (!wallpaper)
          return;
        // Use 1280x720 for overview since it's heavily blurred anyway
        ImageCacheService.getFullscreen(wallpaper, modelData.name, 1280, 720, function (path, success) {
          cachedWallpaper = path;
        });
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
        source: cachedWallpaper
        smooth: true
        mipmap: false
        cache: false
        asynchronous: true

        layer.enabled: true
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

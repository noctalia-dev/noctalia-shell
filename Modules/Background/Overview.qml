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
      property bool isSolidColor: false
      property color solidColor: Settings.data.wallpaper.solidColor

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

        // Check if we're in solid color mode
        if (Settings.data.wallpaper.useSolidColor) {
          var solidPath = WallpaperService.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
          wallpaper = solidPath;
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

        // Check if this is a solid color path
        if (WallpaperService.isSolidColorPath(wallpaper)) {
          isSolidColor = true;
          var colorStr = WallpaperService.getSolidColor(wallpaper);
          solidColor = colorStr;
          cachedWallpaper = "";
          return;
        }

        isSolidColor = false;
        // Use 1280x720 for overview since it's heavily blurred anyway
        ImageCacheService.getLarge(wallpaper, 1280, 720, function (path, success) {
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

      // Solid color background
      Rectangle {
        anchors.fill: parent
        visible: isSolidColor
        color: solidColor

        Rectangle {
          anchors.fill: parent
          color: Settings.data.colorSchemes.darkMode ? Color.mSurface : Color.mOnSurface
          opacity: 0.8
        }
      }

      // Image background
      Image {
        id: bgImage
        anchors.fill: parent
        visible: !isSolidColor
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

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
      property string pendingWallpaper: ""
      property bool isSolidColor: false
      property bool useQtBlur: false // Fallback when ImageMagick not available
      property color solidColor: Settings.data.wallpaper.solidColor
      // Watch the actual tint color value, not just darkMode setting, since colors reload asynchronously
      property color tintColor: Settings.data.colorSchemes.darkMode ? Color.mSurface : Color.mOnSurface

      Component.onCompleted: {
        if (modelData) {
          Logger.d("Overview", "Loading overview for Niri on", modelData.name);
        }
        setWallpaperInitial();
      }

      Component.onDestruction: {
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

      function requestBlurredOverview() {
        requestBlurredOverviewWithTint(tintColor.toString(), Settings.data.colorSchemes.darkMode);
      }

      function requestBlurredOverviewWithTint(tint, isDarkMode) {
        if (!wallpaper || isSolidColor)
          return;

        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const targetWidth = Math.round(modelData.width * compositorScale);
        const targetHeight = Math.round(modelData.height * compositorScale);

        // Start fade out, then request new image
        if (cachedWallpaper) {
          fadeOutAnim.start();
        }

        ImageCacheService.getBlurredOverview(wallpaper, targetWidth, targetHeight, tint, isDarkMode, function (path, success) {
          if (path) {
            useQtBlur = !success; // Use Qt blur fallback if ImageMagick failed
            pendingWallpaper = path;
            // If fade out is done or wasn't needed, apply immediately
            if (!fadeOutAnim.running) {
              applyPendingWallpaper();
            }
          }
        });
      }

      function applyPendingWallpaper() {
        if (pendingWallpaper) {
          cachedWallpaper = pendingWallpaper;
          pendingWallpaper = "";
          fadeInAnim.start();
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
        requestBlurredOverview();
      }

      // Watch for color reloads - use the actual Color properties directly to avoid stale values
      Connections {
        target: Color
        function onMSurfaceChanged() {
          if (!isSolidColor && wallpaper && Settings.data.colorSchemes.darkMode) {
            requestBlurredOverviewWithTint(Color.mSurface.toString(), true);
          }
        }
        function onMOnSurfaceChanged() {
          if (!isSolidColor && wallpaper && !Settings.data.colorSchemes.darkMode) {
            requestBlurredOverviewWithTint(Color.mOnSurface.toString(), false);
          }
        }
      }

      color: "transparent"
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
          color: tintColor
        }
      }

      // Image background (pre-blurred and tinted by ImageMagick, or Qt fallback)
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

        // Qt blur fallback when ImageMagick not available
        layer.enabled: useQtBlur
        layer.smooth: false
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 32
        }

        // Tint overlay for Qt blur fallback
        Rectangle {
          anchors.fill: parent
          visible: useQtBlur
          color: tintColor
          opacity: 0.6
        }

        NumberAnimation on opacity {
          id: fadeOutAnim
          running: false
          from: 1
          to: 0
          duration: 200
          easing.type: Easing.OutQuad
          onFinished: applyPendingWallpaper()
        }

        NumberAnimation on opacity {
          id: fadeInAnim
          running: false
          from: 0
          to: 1
          duration: 200
          easing.type: Easing.InQuad
        }
      }
    }
  }
}

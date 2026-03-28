import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Power
import qs.Services.UI

Item {
  id: root
  anchors.fill: parent

  required property ShellScreen screen

  // Cached wallpaper path - exposed for parent components
  property string resolvedWallpaperPath: ""

  // Enter / exit transtion value
  property real transitionProgress: 1.0

  readonly property color tintColor: Settings.data.colorSchemes.darkMode ? Color.mSurface : Color.mOnSurface
  readonly property bool useEffects: !PowerProfileService.noctaliaPerformanceMode || !Settings.data.noctaliaPerformance.disableWallpaper
  readonly property bool useScreencopy: Settings.data.general.lockScreenCopyBg
  readonly property bool useWallpaper: Settings.data.wallpaper.enabled && resolvedWallpaperPath !== ""

  // Request preprocessed wallpaper when lock screen becomes active or dimensions change
  Component.onCompleted: {
    if (screen) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  onWidthChanged: {
    if (screen && width > 0 && height > 0) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  onHeightChanged: {
    if (screen && width > 0 && height > 0) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  // Listen for wallpaper changes
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      if (screen && screenName === screen.name) {
        Qt.callLater(requestCachedWallpaper);
      }
    }
  }

  // Listen for display scale changes
  Connections {
    target: CompositorService
    function onDisplayScalesChanged() {
      if (screen && width > 0 && height > 0) {
        Qt.callLater(requestCachedWallpaper);
      }
    }
  }

  function requestCachedWallpaper() {
    if (!screen || width <= 0 || height <= 0) {
      return;
    }

    // Check for solid color mode first
    if (Settings.data.wallpaper.useSolidColor) {
      resolvedWallpaperPath = "";
      return;
    }

    const originalPath = WallpaperService.getWallpaper(screen.name) || "";
    if (originalPath === "") {
      resolvedWallpaperPath = "";
      return;
    }

    // Handle solid color paths
    if (WallpaperService.isSolidColorPath(originalPath)) {
      resolvedWallpaperPath = "";
      return;
    }

    if (!ImageCacheService || !ImageCacheService.initialized) {
      // Fallback to original if services not ready
      resolvedWallpaperPath = originalPath;
      return;
    }

    const compositorScale = CompositorService.getDisplayScale(screen.name);
    const targetWidth = Math.round(width * compositorScale);
    const targetHeight = Math.round(height * compositorScale);
    if (targetWidth <= 0 || targetHeight <= 0) {
      return;
    }

    // Don't set resolvedWallpaperPath until cache is ready
    // This prevents loading the original huge image
    ImageCacheService.getLarge(originalPath, targetWidth, targetHeight, function (cachedPath, success) {
      if (success) {
        resolvedWallpaperPath = cachedPath;
      } else {
        // Only fall back to original if caching failed
        resolvedWallpaperPath = originalPath;
      }
    });
  }

  // Opaque black at the very bottom to prevent white flash
  Rectangle {
    anchors.fill: parent
    color: "black"
  }

  // A copy of the screen to use as background
  // Also used as fade in / fade out backdrop
  ScreencopyView {
    id: lockBgScreencopy
    visible: useEffects && (useScreencopy || useWallpaper)
    anchors.fill: parent
    captureSource: screen
  }

  // If using a solid color wallpaper
  Rectangle {
    anchors.fill: parent
    opacity: (Settings.data.wallpaper.useSolidColor && useEffects) ? transitionProgress : 0.0
    color: Settings.data.wallpaper.solidColor
  }

  // If using an image wallpaper
  Image {
    id: lockBgImage
    visible: false // rendered with effects below
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    source: resolvedWallpaperPath
    cache: false
    smooth: true
    mipmap: false
    antialiasing: true
  }

  // Applies the image wallpaper or screen copy with effects
  MultiEffect {
    id: lockBgRender
    anchors.fill: parent
    opacity: transitionProgress
    visible: useEffects && (useScreencopy || useWallpaper)
    source: useScreencopy ? lockBgScreencopy : lockBgImage

    blurEnabled: Settings.data.general.lockScreenBlur > 0
    blur: Settings.data.general.lockScreenBlur
    blurMax: 128

    Rectangle {
      anchors.fill: parent
      color: tintColor
      opacity: Settings.data.general.lockScreenTint
    }
  }

  Rectangle {
    visible: !Settings.data.wallpaper.useSolidColor
    anchors.fill: parent
    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: Qt.alpha(Color.mShadow, 0.4)
      }
      GradientStop {
        position: 0.3
        color: Qt.alpha(Color.mShadow, 0.2)
      }
      GradientStop {
        position: 0.7
        color: Qt.alpha(Color.mShadow, 0.25)
      }
      GradientStop {
        position: 1.0
        color: Qt.alpha(Color.mShadow, 0.5)
      }
    }
  }

  // Screen corners for lock screen
  Item {
    anchors.fill: parent
    visible: Settings.data.general.showScreenCorners

    property color cornerColor: Settings.data.general.forceBlackScreenCorners ? "black" : Color.mSurface
    property real cornerRadius: Style.screenRadius
    property real cornerSize: Style.screenRadius

    // Top-left concave corner
    Canvas {
      anchors.top: parent.top
      anchors.left: parent.left
      width: parent.cornerSize
      height: parent.cornerSize
      antialiasing: true
      renderTarget: Canvas.FramebufferObject
      smooth: false

      onPaint: {
        const ctx = getContext("2d");
        if (!ctx)
          return;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        ctx.fillStyle = parent.cornerColor;
        ctx.fillRect(0, 0, width, height);

        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.arc(width, height, parent.cornerRadius, 0, 2 * Math.PI);
        ctx.fill();
      }

      onWidthChanged: if (available)
                        requestPaint()
      onHeightChanged: if (available)
                         requestPaint()
    }

    // Top-right concave corner
    Canvas {
      anchors.top: parent.top
      anchors.right: parent.right
      width: parent.cornerSize
      height: parent.cornerSize
      antialiasing: true
      renderTarget: Canvas.FramebufferObject
      smooth: true

      onPaint: {
        const ctx = getContext("2d");
        if (!ctx)
          return;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        ctx.fillStyle = parent.cornerColor;
        ctx.fillRect(0, 0, width, height);

        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.arc(0, height, parent.cornerRadius, 0, 2 * Math.PI);
        ctx.fill();
      }

      onWidthChanged: if (available)
                        requestPaint()
      onHeightChanged: if (available)
                         requestPaint()
    }

    // Bottom-left concave corner
    Canvas {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: parent.cornerSize
      height: parent.cornerSize
      antialiasing: true
      renderTarget: Canvas.FramebufferObject
      smooth: true

      onPaint: {
        const ctx = getContext("2d");
        if (!ctx)
          return;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        ctx.fillStyle = parent.cornerColor;
        ctx.fillRect(0, 0, width, height);

        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.arc(width, 0, parent.cornerRadius, 0, 2 * Math.PI);
        ctx.fill();
      }

      onWidthChanged: if (available)
                        requestPaint()
      onHeightChanged: if (available)
                         requestPaint()
    }

    // Bottom-right concave corner
    Canvas {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: parent.cornerSize
      height: parent.cornerSize
      antialiasing: true
      renderTarget: Canvas.FramebufferObject
      smooth: true

      onPaint: {
        const ctx = getContext("2d");
        if (!ctx)
          return;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        ctx.fillStyle = parent.cornerColor;
        ctx.fillRect(0, 0, width, height);

        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.arc(0, 0, parent.cornerRadius, 0, 2 * Math.PI);
        ctx.fill();
      }

      onWidthChanged: if (available)
                        requestPaint()
      onHeightChanged: if (available)
                         requestPaint()
    }
  }
}

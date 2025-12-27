import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Variants {
  id: backgroundVariants
  model: Quickshell.screens

  delegate: Loader {

    required property ShellScreen modelData

    active: modelData && Settings.data.wallpaper.enabled

    sourceComponent: PanelWindow {
      id: root

      // Internal state management
      property string transitionType: "fade"
      property real transitionProgress: 0
      property bool isStartupTransition: true

      readonly property real edgeSmoothness: Settings.data.wallpaper.transitionEdgeSmoothness
      readonly property var allTransitions: WallpaperService.allTransitions
      readonly property bool transitioning: transitionAnimation.running

      // Wipe direction: 0=left, 1=right, 2=up, 3=down
      property real wipeDirection: 0

      // Disc
      property real discCenterX: 0.5
      property real discCenterY: 0.5

      // Stripe
      property real stripesCount: 16
      property real stripesAngle: 0

      // Used to debounce wallpaper changes
      property string futureWallpaper: ""

      // Fillmode default is "crop"
      property real fillMode: WallpaperService.getFillModeUniform()
      property vector4d fillColor: Qt.vector4d(Settings.data.wallpaper.fillColor.r, Settings.data.wallpaper.fillColor.g, Settings.data.wallpaper.fillColor.b, 1.0)

      Component.onCompleted: setWallpaperInitial()

      Component.onDestruction: {
        transitionAnimation.stop();
        debounceTimer.stop();
        shaderLoader.active = false;
        currentWallpaper.source = "";
        nextWallpaper.source = "";
      }

      Connections {
        target: Settings.data.wallpaper
        function onFillModeChanged() {
          fillMode = WallpaperService.getFillModeUniform();
        }
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            // Request preprocessed wallpaper from cache service
            requestPreprocessedWallpaper(path);
          }
        }
      }

      Connections {
        target: CompositorService
        function onDisplayScalesChanged() {
          // Re-request preprocessed wallpaper at new dimensions
          if (isStartupTransition) {
            return;
          }
          const currentPath = WallpaperService.getWallpaper(modelData.name);
          if (currentPath) {
            requestPreprocessedWallpaper(currentPath);
          }
        }
      }

      color: Color.transparent
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-wallpaper-" + (screen?.name || "unknown")

      anchors {
        bottom: true
        top: true
        right: true
        left: true
      }

      Timer {
        id: debounceTimer
        interval: 333
        running: false
        repeat: false
        onTriggered: {
          changeWallpaper();
        }
      }

      Image {
        id: currentWallpaper

        source: ""
        smooth: true
        mipmap: false
        visible: false
        cache: false
        asynchronous: true
        onStatusChanged: {
          if (status === Image.Error) {
            Logger.w("Current wallpaper failed to load:", source);
          }
        }
      }

      Image {
        id: nextWallpaper

        property bool pendingTransition: false

        source: ""
        smooth: true
        mipmap: false
        visible: false
        cache: false
        asynchronous: true
        onStatusChanged: {
          if (status === Image.Error) {
            Logger.w("Next wallpaper failed to load:", source);
            pendingTransition = false;
          } else if (status === Image.Ready) {
            if (pendingTransition) {
              pendingTransition = false;
              currentWallpaper.asynchronous = false;
              transitionAnimation.start();
            }
          }
        }
      }

      // Dynamic shader loader - only loads the active transition shader
      Loader {
        id: shaderLoader
        anchors.fill: parent
        active: true

        sourceComponent: {
          switch (transitionType) {
          case "wipe":
            return wipeShaderComponent;
          case "disc":
            return discShaderComponent;
          case "stripes":
            return stripesShaderComponent;
          case "fade":
          case "none":
          default:
            return fadeShaderComponent;
          }
        }
      }

      // Fade or None transition shader component
      Component {
        id: fadeShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: currentWallpaper
          property variant source2: nextWallpaper
          property real progress: root.transitionProgress

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: source1.sourceSize.width
          property real imageHeight1: source1.sourceSize.height
          property real imageWidth2: source2.sourceSize.width
          property real imageHeight2: source2.sourceSize.height
          property real screenWidth: width
          property real screenHeight: height

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_fade.frag.qsb")
        }
      }

      // Wipe transition shader component
      Component {
        id: wipeShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: currentWallpaper
          property variant source2: nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real direction: root.wipeDirection

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: source1.sourceSize.width
          property real imageHeight1: source1.sourceSize.height
          property real imageWidth2: source2.sourceSize.width
          property real imageHeight2: source2.sourceSize.height
          property real screenWidth: width
          property real screenHeight: height

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_wipe.frag.qsb")
        }
      }

      // Disc reveal transition shader component
      Component {
        id: discShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: currentWallpaper
          property variant source2: nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real centerX: root.discCenterX
          property real centerY: root.discCenterY

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: source1.sourceSize.width
          property real imageHeight1: source1.sourceSize.height
          property real imageWidth2: source2.sourceSize.width
          property real imageHeight2: source2.sourceSize.height
          property real screenWidth: width
          property real screenHeight: height

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_disc.frag.qsb")
        }
      }

      // Diagonal stripes transition shader component
      Component {
        id: stripesShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: currentWallpaper
          property variant source2: nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real stripeCount: root.stripesCount
          property real angle: root.stripesAngle

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: source1.sourceSize.width
          property real imageHeight1: source1.sourceSize.height
          property real imageWidth2: source2.sourceSize.width
          property real imageHeight2: source2.sourceSize.height
          property real screenWidth: width
          property real screenHeight: height

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_stripes.frag.qsb")
        }
      }

      // Animation for the transition progress
      NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        // The stripes shader feels faster visually, we make it a bit slower here.
        duration: transitionType == "stripes" ? Settings.data.wallpaper.transitionDuration * 1.6 : Settings.data.wallpaper.transitionDuration
        easing.type: Easing.InOutCubic
        onFinished: {
          // Assign new image to current BEFORE clearing to prevent flicker
          const tempSource = nextWallpaper.source;
          currentWallpaper.source = tempSource;
          transitionProgress = 0.0;

          // Now clear nextWallpaper after currentWallpaper has the new source
          // Force complete cleanup to free texture memory
          Qt.callLater(() => {
                         nextWallpaper.source = "";
                         Qt.callLater(() => {
                                        currentWallpaper.asynchronous = true;
                                      });
                       });
        }
      }

      // ------------------------------------------------------
      function setWallpaperInitial() {
        // On startup, defer assigning wallpaper until the services are ready
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }
        if (!ImageCacheService || !ImageCacheService.initialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }

        const wallpaperPath = WallpaperService.getWallpaper(modelData.name);
        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const targetWidth = Math.round(modelData.width * compositorScale);
        const targetHeight = Math.round(modelData.height * compositorScale);

        ImageCacheService.getFullscreen(wallpaperPath, modelData.name, targetWidth, targetHeight, function (cachedPath, success) {
          if (success) {
            futureWallpaper = cachedPath;
          } else {
            // Fallback to original
            futureWallpaper = wallpaperPath;
          }
          performStartupTransition();
        });
      }

      // ------------------------------------------------------
      function requestPreprocessedWallpaper(originalPath) {
        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const targetWidth = Math.round(modelData.width * compositorScale);
        const targetHeight = Math.round(modelData.height * compositorScale);

        ImageCacheService.getFullscreen(originalPath, modelData.name, targetWidth, targetHeight, function (cachedPath, success) {
          if (success) {
            futureWallpaper = cachedPath;
          } else {
            futureWallpaper = originalPath;
          }
          debounceTimer.restart();
        });
      }

      // ------------------------------------------------------
      function setWallpaperImmediate(source) {
        transitionAnimation.stop();
        transitionProgress = 0.0;

        // Clear nextWallpaper completely to free texture memory
        nextWallpaper.source = "";
        nextWallpaper.sourceSize = undefined;

        currentWallpaper.source = "";

        Qt.callLater(() => {
                       currentWallpaper.source = source;
                     });
      }

      // ------------------------------------------------------
      function setWallpaperWithTransition(source) {
        if (source === currentWallpaper.source) {
          return;
        }

        if (transitioning) {
          // We are interrupting a transition - handle cleanup properly
          transitionAnimation.stop();
          transitionProgress = 0;

          // Assign nextWallpaper to currentWallpaper BEFORE clearing to prevent flicker
          const newCurrentSource = nextWallpaper.source;
          currentWallpaper.source = newCurrentSource;

          // Now clear nextWallpaper after current has the new source
          Qt.callLater(() => {
                         nextWallpaper.source = "";

                         // Now set the next wallpaper after a brief delay
                         Qt.callLater(() => {
                                        nextWallpaper.source = source;
                                        currentWallpaper.asynchronous = false;
                                        transitionAnimation.start();
                                      });
                       });
          return;
        }

        nextWallpaper.source = source;
        if (nextWallpaper.status === Image.Ready) {
          currentWallpaper.asynchronous = false;
          transitionAnimation.start();
        } else {
          nextWallpaper.pendingTransition = true;
        }
      }

      // ------------------------------------------------------
      // Main method that actually trigger the wallpaper change
      function changeWallpaper() {
        // Get the transitionType from the settings
        transitionType = Settings.data.wallpaper.transitionType;

        if (transitionType == "random") {
          var index = Math.floor(Math.random() * allTransitions.length);
          transitionType = allTransitions[index];
        }

        // Ensure the transition type really exists
        if (transitionType !== "none" && !allTransitions.includes(transitionType)) {
          transitionType = "fade";
        }

        //Logger.i("Background", "New wallpaper: ", futureWallpaper, "On:", modelData.name, "Transition:", transitionType)
        switch (transitionType) {
        case "none":
          setWallpaperImmediate(futureWallpaper);
          break;
        case "wipe":
          wipeDirection = Math.random() * 4;
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "disc":
          discCenterX = Math.random();
          discCenterY = Math.random();
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "stripes":
          stripesCount = Math.round(Math.random() * 20 + 4);
          stripesAngle = Math.random() * 360;
          setWallpaperWithTransition(futureWallpaper);
          break;
        default:
          setWallpaperWithTransition(futureWallpaper);
          break;
        }
      }

      // ------------------------------------------------------
      // Dedicated function for startup animation
      function performStartupTransition() {
        // Get the transitionType from the settings
        transitionType = Settings.data.wallpaper.transitionType;

        if (transitionType == "random") {
          var index = Math.floor(Math.random() * allTransitions.length);
          transitionType = allTransitions[index];
        }

        // Ensure the transition type really exists
        if (transitionType !== "none" && !allTransitions.includes(transitionType)) {
          transitionType = "fade";
        }

        // Apply transitionType so the shader loader picks the correct shader
        this.transitionType = transitionType;

        switch (transitionType) {
        case "none":
          setWallpaperImmediate(futureWallpaper);
          break;
        case "wipe":
          wipeDirection = Math.random() * 4;
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "disc":
          // Force center origin for elegant startup animation
          discCenterX = 0.5;
          discCenterY = 0.5;
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "stripes":
          stripesCount = Math.round(Math.random() * 20 + 4);
          stripesAngle = Math.random() * 360;
          setWallpaperWithTransition(futureWallpaper);
          break;
        default:
          setWallpaperWithTransition(futureWallpaper);
          break;
        }
        // Mark startup transition complete
        isStartupTransition = false;
      }
    }
  }
}

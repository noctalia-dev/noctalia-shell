import QtQuick
import QtMultimedia
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

      // Track current sources for video detection
      property string currentSource: ""
      property string nextSource: ""
      
      // Track which video player is currently active (true = currentVideoPlayer, false = nextVideoPlayer)
      property bool usingPrimaryVideoPlayer: true

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
        currentSource = "";
        nextSource = "";
        currentVideoPlayer.waitingForTransition = false;
        currentVideoPlayer.stop();
        currentVideoPlayer.source = "";
        nextVideoPlayer.waitingForTransition = false;
        nextVideoPlayer.stop();
        nextVideoPlayer.source = "";
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
            // Update wallpaper display
            // Set wallpaper immediately on startup
            futureWallpaper = path;
            debounceTimer.restart();
          }
        }
      }

      Connections {
        target: CompositorService
        function onDisplayScalesChanged() {
          // Recalculate image sizes without interrupting startup transition
          if (isStartupTransition) {
            return;
          }
          recalculateImageSizes();
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

        property bool dimensionsCalculated: false

        source: ""
        smooth: true
        mipmap: false
        visible: false
        cache: false
        asynchronous: true
        sourceSize: undefined
        onStatusChanged: {
          if (status === Image.Error) {
            Logger.w("Current wallpaper failed to load:", source);
          } else if (status === Image.Ready && !dimensionsCalculated) {
            dimensionsCalculated = true;
            const optimalSize = calculateOptimalWallpaperSize(implicitWidth, implicitHeight);
            if (optimalSize !== false) {
              sourceSize = optimalSize;
            }
          }
        }
        onSourceChanged: {
          dimensionsCalculated = false;
          sourceSize = undefined;
        }
      }

      Image {
        id: nextWallpaper

        property bool dimensionsCalculated: false

        source: ""
        smooth: true
        mipmap: false
        visible: false
        cache: false
        asynchronous: true
        sourceSize: undefined
        onStatusChanged: {
          if (status === Image.Error) {
            Logger.w("Next wallpaper failed to load:", source);
          } else if (status === Image.Ready && !dimensionsCalculated) {
            dimensionsCalculated = true;
            const optimalSize = calculateOptimalWallpaperSize(implicitWidth, implicitHeight);
            if (optimalSize !== false) {
              sourceSize = optimalSize;
            }
          }
        }
        onSourceChanged: {
          dimensionsCalculated = false;
          sourceSize = undefined;
        }
      }

      // Video support - current video
      MediaPlayer {
        id: currentVideoPlayer
        source: ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
          muted: true
        }
        videoOutput: currentVideoOutput

        property bool waitingForTransition: false

        onPlaybackStateChanged: {
          // Start transition once video is actually playing
          if (waitingForTransition && playbackState === MediaPlayer.PlayingState) {
            waitingForTransition = false;
            Qt.callLater(() => {
                           if (!transitioning) {
                             transitionAnimation.start();
                           }
                         });
          }
        }
      }

      VideoOutput {
        id: currentVideoOutput
        anchors.fill: parent
        visible: false
      }

      ShaderEffectSource {
        id: currentVideoTexture
        width: parent.width
        height: parent.height
        sourceItem: currentVideoOutput
        hideSource: true
        live: true
        visible: false
      }

      // Video support - next video
      MediaPlayer {
        id: nextVideoPlayer
        source: ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
          muted: true
        }
        videoOutput: nextVideoOutput

        property bool waitingForTransition: false

        onPlaybackStateChanged: {
          // Start transition once video is actually playing
          if (waitingForTransition && playbackState === MediaPlayer.PlayingState) {
            waitingForTransition = false;
            Qt.callLater(() => {
                           if (!transitioning) {
                             transitionAnimation.start();
                           }
                         });
          }
        }
      }

      VideoOutput {
        id: nextVideoOutput
        anchors.fill: parent
        visible: false
      }

      ShaderEffectSource {
        id: nextVideoTexture
        width: parent.width
        height: parent.height
        sourceItem: nextVideoOutput
        hideSource: true
        live: true
        visible: false
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

          property variant source1: root.isVideoWallpaper(root.currentSource) ? (root.usingPrimaryVideoPlayer ? currentVideoTexture : nextVideoTexture) : currentWallpaper
          property variant source2: root.isVideoWallpaper(root.nextSource) ? (root.usingPrimaryVideoPlayer ? nextVideoTexture : currentVideoTexture) : nextWallpaper
          property real progress: root.transitionProgress

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.width : currentWallpaper.sourceSize.width
          property real imageHeight1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.height : currentWallpaper.sourceSize.height
          property real imageWidth2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.width : nextWallpaper.sourceSize.width
          property real imageHeight2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.height : nextWallpaper.sourceSize.height
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

          property variant source1: root.isVideoWallpaper(root.currentSource) ? (root.usingPrimaryVideoPlayer ? currentVideoTexture : nextVideoTexture) : currentWallpaper
          property variant source2: root.isVideoWallpaper(root.nextSource) ? (root.usingPrimaryVideoPlayer ? nextVideoTexture : currentVideoTexture) : nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real direction: root.wipeDirection

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.width : currentWallpaper.sourceSize.width
          property real imageHeight1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.height : currentWallpaper.sourceSize.height
          property real imageWidth2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.width : nextWallpaper.sourceSize.width
          property real imageHeight2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.height : nextWallpaper.sourceSize.height
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

          property variant source1: root.isVideoWallpaper(root.currentSource) ? (root.usingPrimaryVideoPlayer ? currentVideoTexture : nextVideoTexture) : currentWallpaper
          property variant source2: root.isVideoWallpaper(root.nextSource) ? (root.usingPrimaryVideoPlayer ? nextVideoTexture : currentVideoTexture) : nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real centerX: root.discCenterX
          property real centerY: root.discCenterY

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.width : currentWallpaper.sourceSize.width
          property real imageHeight1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.height : currentWallpaper.sourceSize.height
          property real imageWidth2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.width : nextWallpaper.sourceSize.width
          property real imageHeight2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.height : nextWallpaper.sourceSize.height
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

          property variant source1: root.isVideoWallpaper(root.currentSource) ? (root.usingPrimaryVideoPlayer ? currentVideoTexture : nextVideoTexture) : currentWallpaper
          property variant source2: root.isVideoWallpaper(root.nextSource) ? (root.usingPrimaryVideoPlayer ? nextVideoTexture : currentVideoTexture) : nextWallpaper
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real stripeCount: root.stripesCount
          property real angle: root.stripesAngle

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.width : currentWallpaper.sourceSize.width
          property real imageHeight1: root.isVideoWallpaper(root.currentSource) ? currentVideoTexture.height : currentWallpaper.sourceSize.height
          property real imageWidth2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.width : nextWallpaper.sourceSize.width
          property real imageHeight2: root.isVideoWallpaper(root.nextSource) ? nextVideoTexture.height : nextWallpaper.sourceSize.height
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
          // Handle video/image transition completion
          const nextIsVideo = isVideoWallpaper(root.nextSource);
          const currentIsVideo = isVideoWallpaper(root.currentSource);

          if (nextIsVideo) {
            // Swap video player roles instead of copying sources
            usingPrimaryVideoPlayer = !usingPrimaryVideoPlayer;
            currentSource = root.nextSource;
            nextSource = "";
            currentWallpaper.source = "";
            
            // Clean up the now-inactive video player (the old current)
            Qt.callLater(() => {
                           if (usingPrimaryVideoPlayer) {
                             // currentVideoPlayer is now active, clean up nextVideoPlayer
                             nextVideoPlayer.waitingForTransition = false;
                             nextVideoPlayer.stop();
                             nextVideoPlayer.source = "";
                           } else {
                             // nextVideoPlayer is now active, clean up currentVideoPlayer
                             currentVideoPlayer.stop();
                             currentVideoPlayer.source = "";
                           }
                         });
          } else {
            // Transfer next image to current
            const tempSource = nextWallpaper.source;
            currentWallpaper.source = tempSource;
            currentSource = root.nextSource;
            nextSource = "";
            
            // Stop both video players when switching to image
            Qt.callLater(() => {
                           currentVideoPlayer.stop();
                           currentVideoPlayer.source = "";
                           nextVideoPlayer.waitingForTransition = false;
                           nextVideoPlayer.stop();
                           nextVideoPlayer.source = "";
                         });
          }

          transitionProgress = 0.0;

          // Now clear nextWallpaper after currentWallpaper has the new source
          // Force complete cleanup to free texture memory (~18-25MB per monitor)
          Qt.callLater(() => {
                         nextWallpaper.source = "";
                         nextWallpaper.sourceSize = undefined;
                         Qt.callLater(() => {
                                        currentWallpaper.asynchronous = true;
                                      });
                       });
        }
      }

      // ------------------------------------------------------
      // Helper function to detect if a path is a video file
      function isVideoWallpaper(path) {
        if (!path)
          return false;
        const pathStr = path.toString().toLowerCase();
        return pathStr.endsWith(".mp4");
      }

      // ------------------------------------------------------
      function calculateOptimalWallpaperSize(wpWidth, wpHeight) {
        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const screenWidth = modelData.width * compositorScale;
        const screenHeight = modelData.height * compositorScale;
        if (wpWidth <= screenWidth || wpHeight <= screenHeight || wpWidth <= 0 || wpHeight <= 0) {
          // Do not resize if wallpaper is smaller than one of the screen dimension
          return;
        }

        const imageAspectRatio = wpWidth / wpHeight;
        var dim = Qt.size(0, 0);
        if (screenWidth >= screenHeight) {
          const w = Math.min(screenWidth, wpWidth);
          dim = Qt.size(Math.round(w), Math.round(w / imageAspectRatio));
        } else {
          const h = Math.min(screenHeight, wpHeight);
          dim = Qt.size(Math.round(h * imageAspectRatio), Math.round(h));
        }

        Logger.d("Background", `Wallpaper resized on ${modelData.name} ${screenWidth}x${screenHeight} @ ${compositorScale}x`, "src:", wpWidth, wpHeight, "dst:", dim.width, dim.height);
        return dim;
      }

      // ------------------------------------------------------
      function recalculateImageSizes() {
        // Re-evaluate and apply optimal sourceSize for both images when ready
        if (currentWallpaper.status === Image.Ready) {
          const optimal = calculateOptimalWallpaperSize(currentWallpaper.implicitWidth, currentWallpaper.implicitHeight);
          if (optimal !== undefined && optimal !== false) {
            currentWallpaper.sourceSize = optimal;
          } else {
            currentWallpaper.sourceSize = undefined;
          }
        }

        if (nextWallpaper.status === Image.Ready) {
          const optimal2 = calculateOptimalWallpaperSize(nextWallpaper.implicitWidth, nextWallpaper.implicitHeight);
          if (optimal2 !== undefined && optimal2 !== false) {
            nextWallpaper.sourceSize = optimal2;
          } else {
            nextWallpaper.sourceSize = undefined;
          }
        }
      }

      // ------------------------------------------------------
      function setWallpaperInitial() {
        // On startup, defer assigning wallpaper until the service cache is ready, retries every tick
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }

        const wallpaperPath = WallpaperService.getWallpaper(modelData.name);

        futureWallpaper = wallpaperPath;
        performStartupTransition();
      }

      // ------------------------------------------------------
      function setWallpaperImmediate(source) {
        transitionAnimation.stop();
        transitionProgress = 0.0;

        // Stop and clear video players
        nextVideoPlayer.waitingForTransition = false;
        nextVideoPlayer.stop();
        nextVideoPlayer.source = "";
        nextSource = "";
        currentVideoPlayer.waitingForTransition = false;
        currentVideoPlayer.stop();
        currentVideoPlayer.source = "";

        // Clear nextWallpaper completely to free texture memory
        nextWallpaper.source = "";
        nextWallpaper.sourceSize = undefined;

        currentWallpaper.source = "";
        currentSource = "";
        
        // Reset to primary player
        usingPrimaryVideoPlayer = true;

        Qt.callLater(() => {
                       if (isVideoWallpaper(source)) {
                         currentSource = source;
                         currentVideoPlayer.source = source;
                         currentVideoPlayer.play();
                       } else {
                         currentSource = source;
                         currentWallpaper.source = source;
                       }
                     });
      }

      // ------------------------------------------------------
      function setWallpaperWithTransition(source) {
        if (source === root.currentSource) {
          return;
        }

        if (transitioning) {
          // We are interrupting a transition - handle cleanup properly
          transitionAnimation.stop();
          transitionProgress = 0;

          // Handle video/image transitions during interruption
          const nextIsVideo = isVideoWallpaper(root.nextSource);

          if (nextIsVideo) {
            // Swap to use the next video as current
            usingPrimaryVideoPlayer = !usingPrimaryVideoPlayer;
            currentSource = root.nextSource;
            nextSource = "";
            currentWallpaper.source = "";
            
            // Clean up the now-inactive player
            if (usingPrimaryVideoPlayer) {
              nextVideoPlayer.waitingForTransition = false;
            } else {
              currentVideoPlayer.waitingForTransition = false;
            }
          } else {
            // Transfer next image to current
            const newCurrentSource = nextWallpaper.source;
            currentWallpaper.source = newCurrentSource;
            currentSource = root.nextSource;
            nextWallpaper.source = "";
            nextSource = "";
          }

          // Now set the new next wallpaper after a brief delay
          Qt.callLater(() => {
                         if (isVideoWallpaper(source)) {
                           nextSource = source;
                           // Load into inactive player
                           if (usingPrimaryVideoPlayer) {
                             nextVideoPlayer.waitingForTransition = true;
                             nextVideoPlayer.source = source;
                             nextVideoPlayer.play();
                           } else {
                             currentVideoPlayer.waitingForTransition = true;
                             currentVideoPlayer.source = source;
                             currentVideoPlayer.play();
                           }
                         } else {
                           nextSource = source;
                           nextWallpaper.source = source;
                           currentWallpaper.asynchronous = false;
                           Qt.callLater(() => {
                                          transitionAnimation.start();
                                        });
                         }
                       });
          return;
        }

        // Start new transition
        if (isVideoWallpaper(source)) {
          nextSource = source;
          // Load video into the inactive player
          if (usingPrimaryVideoPlayer) {
            nextVideoPlayer.waitingForTransition = true;
            nextVideoPlayer.source = source;
            nextVideoPlayer.play();
          } else {
            currentVideoPlayer.waitingForTransition = true;
            currentVideoPlayer.source = source;
            currentVideoPlayer.play();
          }
        } else {
          nextSource = source;
          nextWallpaper.source = source;
          currentWallpaper.asynchronous = false;
          transitionAnimation.start();
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

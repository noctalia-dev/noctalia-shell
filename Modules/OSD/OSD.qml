import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

// Unified OSD component
// Loader activates only when showing OSD, deactivates when hidden to save resources
Variants {
  model: Quickshell.screens.filter(screen => (Settings.data.osd.monitors.includes(screen.name) || (Settings.data.osd.monitors.length === 0)) && Settings.data.osd.enabled)

  delegate: Loader {
    id: root

    required property ShellScreen modelData

    // Access the notification model from the service
    property ListModel notificationModel: NotificationService.activeList

    // Loader is only active when actually showing something
    active: false

    // Current OSD display state
    property string currentOSDType: "" // "volume", "inputVolume", "brightness", or ""

    // Volume properties
    readonly property real currentVolume: AudioService.volume
    readonly property bool isMuted: AudioService.muted
    property bool volumeInitialized: false
    property bool muteInitialized: false

    // Input volume properties
    readonly property real currentInputVolume: AudioService.inputVolume
    readonly property bool isInputMuted: AudioService.inputMuted
    property bool inputAudioInitialized: false

    // Brightness properties
    property real lastUpdatedBrightness: 0
    readonly property real currentBrightness: lastUpdatedBrightness
    property bool brightnessInitialized: false

    // Get appropriate icon based on current OSD type
    function getIcon() {
      if (currentOSDType === "volume") {
        if (AudioService.muted) {
          return "volume-mute"
        }
        return (AudioService.volume <= Number.EPSILON) ? "volume-zero" : (AudioService.volume <= 0.5) ? "volume-low" : "volume-high"
      } else if (currentOSDType === "inputVolume") {
        if (AudioService.inputMuted) {
          return "microphone-off"
        }
        return "microphone"
      } else if (currentOSDType === "brightness") {
        return currentBrightness <= 0.5 ? "brightness-low" : "brightness-high"
      }
      return ""
    }

    // Get current value (0-1 range)
    function getCurrentValue() {
      if (currentOSDType === "volume") {
        return isMuted ? 0 : currentVolume
      } else if (currentOSDType === "inputVolume") {
        return isInputMuted ? 0 : currentInputVolume
      } else if (currentOSDType === "brightness") {
        return currentBrightness
      }
      return 0
    }

    // Get maximum value for current OSD type
    function getMaxValue() {
      if (currentOSDType === "volume" || currentOSDType === "inputVolume") {
        return Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
      } else if (currentOSDType === "brightness") {
        return 1.0
      }
      return 1.0
    }

    // Get display percentage
    function getDisplayPercentage() {
      if (currentOSDType === "volume") {
        if (isMuted)
          return "0%"
        const max = getMaxValue()
        const pct = Math.round(Math.min(max, currentVolume) * 100)
        return pct + "%"
      } else if (currentOSDType === "inputVolume") {
        if (isInputMuted)
          return "0%"
        const max = getMaxValue()
        const pct = Math.round(Math.min(max, currentInputVolume) * 100)
        return pct + "%"
      } else if (currentOSDType === "brightness") {
        const pct = Math.round(Math.min(1.0, currentBrightness) * 100)
        return pct + "%"
      }
      return ""
    }

    // Get progress bar color
    function getProgressColor() {
      if (currentOSDType === "volume") {
        if (isMuted)
          return Color.mError
        return Color.mPrimary
      } else if (currentOSDType === "inputVolume") {
        if (isInputMuted)
          return Color.mError
        return Color.mPrimary
      }
      return Color.mPrimary
    }

    // Get icon color
    function getIconColor() {
      if ((currentOSDType === "volume" && isMuted) || (currentOSDType === "inputVolume" && isInputMuted)) {
        return Color.mError
      }
      return Color.mOnSurface
    }

    sourceComponent: PanelWindow {
      id: panel
      screen: modelData

      readonly property string location: (Settings.data.osd && Settings.data.osd.location) ? Settings.data.osd.location : "top_right"
      readonly property bool isTop: (location === "top") || (location.length >= 3 && location.substring(0, 3) === "top")
      readonly property bool isBottom: (location === "bottom") || (location.length >= 6 && location.substring(0, 6) === "bottom")
      readonly property bool isLeft: (location.indexOf("_left") >= 0) || (location === "left")
      readonly property bool isRight: (location.indexOf("_right") >= 0) || (location === "right")
      readonly property bool isCentered: (location === "top" || location === "bottom")
      readonly property bool verticalMode: (location === "left" || location === "right")
      readonly property int hWidth: Math.round(420 * Style.uiScaleRatio)
      readonly property int hHeight: Math.round(84 * Style.uiScaleRatio)
      readonly property int vWidth: Math.round(92 * Style.uiScaleRatio)
      readonly property int vHeight: Math.round(380 * Style.uiScaleRatio)

      // Ensure an even width to keep the vertical bar perfectly centered
      readonly property int barThickness: {
        const base = Math.max(8, Math.round(8 * Style.uiScaleRatio))
        return (base % 2 === 0) ? base : base + 1
      }

      // Anchor selection based on location (window edges)
      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      // Margins depending on bar position and chosen location
      margins.top: {
        if (!(anchors.top))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "top") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0
          return Style.barHeight + base + floatExtraV
        }
        return base
      }

      margins.bottom: {
        if (!(anchors.bottom))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "bottom") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0
          return Style.barHeight + base + floatExtraV
        }
        return base
      }

      margins.left: {
        if (!(anchors.left))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "left") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
          return Style.barHeight + base + floatExtraH
        }
        return base
      }

      margins.right: {
        if (!(anchors.right))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "right") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
          return Style.barHeight + base + floatExtraH
        }
        return base
      }

      implicitWidth: verticalMode ? vWidth : hWidth
      implicitHeight: verticalMode ? vHeight : hHeight

      color: Color.transparent

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.layer: (Settings.data.osd && Settings.data.osd.overlayLayer) ? WlrLayer.Overlay : WlrLayer.Top
      exclusionMode: PanelWindow.ExclusionMode.Ignore

      Item {
        id: osdItem
        anchors.fill: parent
        visible: false
        opacity: 0
        scale: 0.85 // initial scale for a little zoom effect

        Behavior on opacity {
          NumberAnimation {
            id: opacityAnimation
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on scale {
          NumberAnimation {
            id: scaleAnimation
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Timer {
          id: hideTimer
          interval: Settings.data.osd.autoHideMs
          onTriggered: osdItem.hide()
        }

        // Timer to handle visibility after animations complete
        Timer {
          id: visibilityTimer
          interval: Style.animationNormal + 50 // Add small buffer
          onTriggered: {
            osdItem.visible = false
            root.currentOSDType = ""
            // Deactivate the loader when done
            root.active = false
          }
        }

        // Background rectangle (source for the effect)
        Rectangle {
          id: background
          anchors.fill: parent
          anchors.margins: Style.marginM * 2
          radius: Style.radiusL
          color: Color.mSurface
          border.color: Color.mOutline
          border.width: {
            const bw = Math.max(2, Style.borderM)
            return (bw % 2 === 0) ? bw : bw + 1
          }
        }

        // MultiEffect applied to background only
        NDropShadows {
          anchors.fill: background
          source: background
        }

        // Content loader on top of the background (not affected by MultiEffect)
        Loader {
          id: contentLoader
          anchors.fill: parent
          anchors.margins: Style.marginL * 2
          active: true
          sourceComponent: panel.verticalMode ? verticalContent : horizontalContent
        }

        Component {
          id: horizontalContent
          Item {
            anchors.fill: parent

            RowLayout {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.marginL
              spacing: Style.marginM

              NIcon {
                icon: root.getIcon()
                color: root.getIconColor()
                pointSize: Style.fontSizeXL
                Layout.alignment: Qt.AlignVCenter

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.InOutQuad
                  }
                }
              }

              // Progress bar with calculated width
              Rectangle {
                Layout.fillWidth: true
                height: panel.barThickness
                radius: Math.round(panel.barThickness / 2)
                color: Color.mSurfaceVariant
                width: parent.width * 0.6

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width * Math.min(1.0, root.getCurrentValue() / root.getMaxValue())
                  radius: parent.radius
                  color: root.getProgressColor()

                  Behavior on width {
                    NumberAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.InOutQuad
                    }
                  }
                  Behavior on color {
                    ColorAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }

              // Percentage text
              NText {
                text: root.getDisplayPercentage()
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
                family: Settings.data.ui.fontFixed
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                Layout.preferredWidth: Math.round(50 * Style.uiScaleRatio)
              }
            }
          }
        }

        Component {
          id: verticalContent
          Item {
            anchors.fill: parent

            ColumnLayout {
              // Ensure inner padding respects the rounded corners; avoid clipping the icon/text
              property int vMargin: {
                const styleMargin = Style.marginL
                const cornerGuard = Math.round(osdItem.radius)
                return Math.max(styleMargin, cornerGuard)
              }
              property int vMarginTop: Math.round(Math.max(osdItem.radius, Style.marginS))
              property int balanceDelta: Style.marginS
              anchors.fill: parent
              anchors.topMargin: vMargin
              anchors.bottomMargin: vMargin
              spacing: Style.marginS

              // Percentage text at top
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(20 * Style.uiScaleRatio)
                NText {
                  id: percentText
                  text: root.getDisplayPercentage()
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeS
                  family: Settings.data.ui.fontFixed
                  width: Math.round(50 * Style.uiScaleRatio)
                  height: parent.height
                  anchors.centerIn: parent
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // Progress bar
              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true // Fill remaining space between text and icon
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: panel.barThickness
                  radius: Math.round(panel.barThickness / 2)
                  color: Color.mSurfaceVariant

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * Math.min(1.0, root.getCurrentValue() / root.getMaxValue())
                    radius: parent.radius
                    color: root.getProgressColor()

                    Behavior on height {
                      NumberAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.InOutQuad
                      }
                    }
                    Behavior on color {
                      ColorAnimation {
                        duration: Style.animationNormal
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }
                }
              }

              // Icon at bottom
              NIcon {
                icon: root.getIcon()
                color: root.getIconColor()
                pointSize: Style.fontSizeL
                Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.InOutQuad
                  }
                }
              }
            }
          }
        }

        function show() {
          // Cancel any pending hide operations
          hideTimer.stop()
          visibilityTimer.stop()

          // Make visible and animate in
          osdItem.visible = true
          // Use Qt.callLater to ensure the visible change is processed before animation
          Qt.callLater(() => {
                         osdItem.opacity = 1
                         osdItem.scale = 1.0
                       })

          // Start the auto-hide timer
          hideTimer.start()
        }

        function hide() {
          hideTimer.stop()
          visibilityTimer.stop()

          // Start fade out animation
          osdItem.opacity = 0
          osdItem.scale = 0.85 // Less dramatic scale change for smoother effect

          // Delay hiding the element until after animation completes
          visibilityTimer.start()
        }

        function hideImmediately() {
          hideTimer.stop()
          visibilityTimer.stop()
          osdItem.opacity = 0
          osdItem.scale = 0.85
          osdItem.visible = false
          root.currentOSDType = ""
          root.active = false
        }
      }

      function showOSD() {
        osdItem.show()
      }
    }

    // Volume change monitoring
    Connections {
      target: AudioService

      function onVolumeChanged() {
        if (volumeInitialized) {
          showOSD("volume")
        }
      }

      function onMutedChanged() {
        if (muteInitialized) {
          showOSD("volume")
        }
      }

      function onInputVolumeChanged() {
        if (!inputAudioInitialized) {
          return
        }
        showOSD("inputVolume")
      }

      function onInputMutedChanged() {
        if (!inputAudioInitialized) {
          return
        }
        showOSD("inputVolume")
      }
    }

    // Timer to initialize volume/mute flags after services are ready
    Timer {
      id: initTimer
      interval: 500
      running: true
      onTriggered: {
        volumeInitialized = true
        muteInitialized = true
        inputAudioInitialized = true
        // Brightness initializes on first change to avoid showing OSD on startup
        connectBrightnessMonitors()
      }
    }

    // Brightness change monitoring
    Connections {
      target: BrightnessService

      function onMonitorsChanged() {
        connectBrightnessMonitors()
      }
    }

    function disconnectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        monitor.brightnessUpdated.disconnect(onBrightnessChanged)
      }
    }

    function connectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        // Disconnect first to avoid duplicate connections
        monitor.brightnessUpdated.disconnect(onBrightnessChanged)
        monitor.brightnessUpdated.connect(onBrightnessChanged)
      }
    }

    function onBrightnessChanged(newBrightness) {
      root.lastUpdatedBrightness = newBrightness

      if (!brightnessInitialized) {
        brightnessInitialized = true
        return
      }

      showOSD("brightness")
    }

    function showOSD(type) {
      // Update the current OSD type
      currentOSDType = type

      // Activate the loader if not already active
      if (!root.active) {
        root.active = true
      }

      // Show the OSD (may need to wait for loader to create the item)
      if (root.item) {
        root.item.showOSD()
      } else {
        // If item not ready yet, wait for it
        Qt.callLater(() => {
                       if (root.item) {
                         root.item.showOSD()
                       }
                     })
      }
    }

    function hideOSD() {
      if (root.item && root.item.osdItem) {
        root.item.osdItem.hideImmediately()
      } else if (root.active) {
        // If loader is active but item isn't ready, just deactivate
        root.active = false
      }
    }
  }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Location
import qs.Services.Media
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

Loader {
  id: root
  active: false

  // Track if the visualizer should be shown (lockscreen active + media playing + non-compact mode)
  readonly property bool needsCava: root.active && !Settings.data.general.compactLockScreen && Settings.data.audio.visualizerType !== "" && Settings.data.audio.visualizerType !== "none"

  onActiveChanged: {
    if (root.active && root.needsCava) {
      CavaService.registerComponent("lockscreen");
    } else {
      CavaService.unregisterComponent("lockscreen");
    }
  }

  onNeedsCavaChanged: {
    if (root.needsCava) {
      CavaService.registerComponent("lockscreen");
    } else {
      CavaService.unregisterComponent("lockscreen");
    }
  }

  Component.onCompleted: {
    // Register with panel service
    PanelService.lockScreen = this;
  }

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: root.active = false
  }

  function scheduleUnloadAfterUnlock() {
    unloadAfterUnlockTimer.start();
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      LockContext {
        id: lockContext
        onUnlocked: {
          lockSession.locked = false;
          root.scheduleUnloadAfterUnlock();
          lockContext.currentText = "";
        }
        onFailed: {
          lockContext.currentText = "";
        }
      }

      WlSessionLock {
        id: lockSession
        locked: root.active

        WlSessionLockSurface {
          id: lockSurface
          readonly property var now: Time.now

          // Shield state - shows "press any key" before starting auth
          // This defers fingerprint/PAM initialization until user interaction,
          // which helps fprintd stabilize after suspend/resume
          property bool shieldActive: true

          // Dismiss shield and start authentication
          function dismissShield() {
            if (!shieldActive)
              return;
            shieldActive = false;
            passwordInput.forceActiveFocus();
            // Start fingerprint auth if available
            if (FingerprintService.ready && !lockContext.pamStarted && !lockContext.unlockInProgress) {
              lockContext.startFingerprintAuth();
            }
          }

          // TODO: Future enhancement - add launch flags to control shield behavior:
          //   --no-shield    Skip shield, start auth immediately (for manual lock)
          //   --shield       Force shield (for suspend/resume)
          // This allows different behavior for:
          //   - Manual lock (Super+L): skip shield for instant fingerprint
          //   - Suspend/resume: show shield to let fprintd stabilize

          Item {
            id: batteryIndicator
            property bool initializationComplete: false
            Timer {
              interval: 500
              running: true
              onTriggered: batteryIndicator.initializationComplete = true
            }

            readonly property var bluetoothDevice: BatteryService.findBluetoothBatteryDevice()
            readonly property bool hasBluetoothBattery: bluetoothDevice && bluetoothDevice.batteryAvailable && bluetoothDevice.battery !== undefined
            readonly property var battery: BatteryService.findLaptopBattery()
            readonly property bool isDevicePresent: {
              if (hasBluetoothBattery) {
                return bluetoothDevice.connected === true;
              }
              if (battery) {
                return (battery.type === UPowerDeviceType.Battery && battery.isPresent !== undefined) ? battery.isPresent : (battery.ready && battery.percentage !== undefined);
              }
              return false;
            }
            property bool isReady: initializationComplete && isDevicePresent && (hasBluetoothBattery || (battery && battery.ready && battery.percentage !== undefined))
            property real percent: isReady ? (hasBluetoothBattery ? (bluetoothDevice.battery * 100) : (battery.percentage * 100)) : 0
            property bool charging: isReady ? (hasBluetoothBattery ? false : (battery ? battery.state === UPowerDeviceState.Charging : false)) : false
            property bool batteryVisible: isReady && percent > 0 && BatteryService.hasAnyBattery()
          }

          Item {
            id: keyboardLayout
            property string currentLayout: KeyboardLayoutService.currentLayout
          }

          // Cached wallpaper path
          property string resolvedWallpaperPath: ""

          // Request preprocessed wallpaper when lock screen becomes active or dimensions change
          Component.onCompleted: {
            Logger.i("LockScreen", "lockSurface loaded");
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

          // Background - solid color or black fallback
          Rectangle {
            anchors.fill: parent
            color: Settings.data.wallpaper.useSolidColor ? Settings.data.wallpaper.solidColor : "#000000"
          }

          Image {
            id: lockBgImage
            visible: source !== "" && Settings.data.wallpaper.enabled && !Settings.data.wallpaper.useSolidColor
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: resolvedWallpaperPath
            cache: false
            smooth: true
            mipmap: false
            antialiasing: true
          }

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.alpha(Color.mShadow, 0.8)
              }
              GradientStop {
                position: 0.3
                color: Qt.alpha(Color.mShadow, 0.4)
              }
              GradientStop {
                position: 0.7
                color: Qt.alpha(Color.mShadow, 0.5)
              }
              GradientStop {
                position: 1.0
                color: Qt.alpha(Color.mShadow, 0.9)
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

          Item {
            anchors.fill: parent
            focus: true

            // Key handler for shield dismissal
            Keys.onPressed: function (event) {
              if (lockSurface.shieldActive) {
                lockSurface.dismissShield();

                // If this is a printable character (not Enter, Escape, etc), insert it into the password input
                if (event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Escape && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                  passwordInput.text = event.text;
                }

                event.accepted = true;
              }
            }

            // Mouse area for shield dismissal and focus handling
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: lockSurface.shieldActive ? Qt.LeftButton : Qt.NoButton
              onClicked: {
                if (lockSurface.shieldActive) {
                  lockSurface.dismissShield();
                }
              }
              onPositionChanged: {
                if (!lockSurface.shieldActive && passwordInput) {
                  passwordInput.forceActiveFocus();
                }
              }
            }

            // Time, Date, and User Profile Container
            Rectangle {
              width: Math.max(500, contentRow.implicitWidth + 32)
              height: Math.max(120, contentRow.implicitHeight + 32)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 100
              radius: Style.radiusL
              color: Color.mSurface
              border.color: Qt.alpha(Color.mOutline, 0.2)
              border.width: 1

              RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 32

                // Left side: Avatar
                Rectangle {
                  Layout.preferredWidth: 70
                  Layout.preferredHeight: 70
                  Layout.alignment: Qt.AlignVCenter
                  radius: width / 2
                  color: "transparent"

                  Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.color: Qt.alpha(Color.mPrimary, 0.8)
                    border.width: 2

                    SequentialAnimation on border.color {
                      loops: Animation.Infinite
                      ColorAnimation {
                        to: Qt.alpha(Color.mPrimary, 1.0)
                        duration: 2000
                        easing.type: Easing.InOutQuad
                      }
                      ColorAnimation {
                        to: Qt.alpha(Color.mPrimary, 0.8)
                        duration: 2000
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }

                  NImageRounded {
                    anchors.centerIn: parent
                    width: 66
                    height: 66
                    radius: width / 2
                    imagePath: Settings.preprocessPath(Settings.data.general.avatarImage)
                    fallbackIcon: "person"

                    SequentialAnimation on scale {
                      loops: Animation.Infinite
                      NumberAnimation {
                        to: 1.02
                        duration: 4000
                        easing.type: Easing.InOutQuad
                      }
                      NumberAnimation {
                        to: 1.0
                        duration: 4000
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }
                }

                // Center: User Info Column (left-aligned text)
                ColumnLayout {
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2

                  // Welcome back + Username on one line
                  NText {
                    text: I18n.tr("system.welcome-back") + " " + HostService.displayName + "!"
                    pointSize: Style.fontSizeXXL
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignLeft
                  }

                  // Date below
                  NText {
                    text: {
                      var lang = I18n.locale.name.split("_")[0];
                      var formats = {
                        "de": "dddd, d. MMMM",
                        "en": "dddd, MMMM d",
                        "es": "dddd, d 'de' MMMM",
                        "fr": "dddd d MMMM",
                        "ja": "yyyy年M月d日 dddd",
                        "nl": "dddd d MMMM",
                        "pt": "dddd, d 'de' MMMM",
                        "zh": "yyyy年M月d日 dddd"
                      };
                      return I18n.locale.toString(Time.now, formats[lang] || "dddd, d MMMM");
                    }
                    pointSize: Style.fontSizeXL
                    color: Color.mOnSurfaceVariant
                    horizontalAlignment: Text.AlignLeft
                  }
                }

                // Spacer to push time to the right
                Item {
                  Layout.fillWidth: true
                }

                // Clock
                NClock {
                  now: Time.now
                  clockStyle: Settings.data.location.analogClockInCalendar ? "analog" : "digital"
                  Layout.preferredWidth: 70
                  Layout.preferredHeight: 70
                  Layout.alignment: Qt.AlignVCenter
                  backgroundColor: Color.mSurface
                  clockColor: Color.mOnSurface
                  secondHandColor: Color.mPrimary
                  hoursFontSize: Style.fontSizeL
                  minutesFontSize: Style.fontSizeL
                }
              }
            }

            // Shield prompt - shown before auth starts
            Rectangle {
              visible: lockSurface.shieldActive
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: parent.height * 0.4
              width: shieldText.width + 24
              height: shieldText.height + 12
              radius: height / 2
              color: Qt.alpha(Color.mSurface, 0.6)

              layer.enabled: true
              layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Color.mShadow, 0.4)
                shadowBlur: 0.3
                shadowVerticalOffset: 2
              }

              NText {
                id: shieldText
                anchors.centerIn: parent
                text: I18n.tr("lock-screen.press-to-unlock")
                pointSize: Style.fontSizeL
                font.weight: Font.Medium
                color: Qt.alpha(Color.mOnSurface, 0.8)
              }
            }

            // Delay timer for fingerprint indicator (prevents flash when lid check dismisses quickly)
            Timer {
              id: fingerprintShowTimer
              interval: 300
              repeat: false
              property bool shouldShow: false
              onTriggered: shouldShow = lockContext.showFingerprintIndicator
            }

            // Reset fingerprint show state when shield becomes active
            Connections {
              target: lockSurface
              function onShieldActiveChanged() {
                if (lockSurface.shieldActive) {
                  fingerprintShowTimer.stop();
                  fingerprintShowTimer.shouldShow = false;
                }
              }
            }

            // Start delay timer when fingerprint indicator should show
            Connections {
              target: lockContext
              function onShowFingerprintIndicatorChanged() {
                if (lockContext.showFingerprintIndicator && !lockSurface.shieldActive) {
                  fingerprintShowTimer.start();
                } else {
                  fingerprintShowTimer.stop();
                  fingerprintShowTimer.shouldShow = false;
                }
              }
            }

            // Fingerprint status indicator (icon only, with failure animation)
            Rectangle {
              id: fingerprintIndicator
              width: 50
              height: 50
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 340 : 420) * Style.uiScaleRatio
              radius: width / 2
              // Use hardcoded red for error to ensure visibility in all color schemes (including monochrome)
              color: showingError ? Qt.alpha("#F44336", 0.25) : Color.mSurfaceVariant
              border.color: showingError ? "#F44336" : Qt.alpha(Color.mPrimary, 0.3)
              border.width: showingError ? 2 : 1
              visible: !lockSurface.shieldActive && fingerprintShowTimer.shouldShow
              opacity: visible ? 1.0 : 0.0

              property bool showingError: false

              NIcon {
                id: fingerprintIcon
                anchors.centerIn: parent
                icon: "fingerprint"
                pointSize: Style.fontSizeXXL
                color: fingerprintIndicator.showingError ? "#F44336" : Color.mPrimary

                Behavior on color {
                  ColorAnimation {
                    duration: 150
                  }
                }
              }

              // Shake animation on error
              SequentialAnimation {
                id: shakeAnimation
                NumberAnimation {
                  target: fingerprintIndicator
                  property: "anchors.horizontalCenterOffset"
                  to: -5
                  duration: 50
                }
                NumberAnimation {
                  target: fingerprintIndicator
                  property: "anchors.horizontalCenterOffset"
                  to: 5
                  duration: 50
                }
                NumberAnimation {
                  target: fingerprintIndicator
                  property: "anchors.horizontalCenterOffset"
                  to: -5
                  duration: 50
                }
                NumberAnimation {
                  target: fingerprintIndicator
                  property: "anchors.horizontalCenterOffset"
                  to: 5
                  duration: 50
                }
                NumberAnimation {
                  target: fingerprintIndicator
                  property: "anchors.horizontalCenterOffset"
                  to: 0
                  duration: 50
                }
                onFinished: fingerprintIndicator.showingError = false
              }

              // Watch for fingerprint failure signal from lockContext
              Connections {
                target: lockContext
                function onFingerprintFailed() {
                  Logger.i("LockScreen", "===== SHAKE: Fingerprint failed, starting animation");
                  fingerprintIndicator.showingError = true;
                  shakeAnimation.restart();
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: 300
                  easing.type: Easing.OutCubic
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: 150
                }
              }

              Behavior on border.color {
                ColorAnimation {
                  duration: 150
                }
              }
            }

            // Error notification
            Rectangle {
              width: errorRowLayout.implicitWidth + Style.marginXL * 1.5
              height: 50
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 280 : 360) * Style.uiScaleRatio
              radius: Style.radiusL
              color: Color.mError
              border.color: Color.mError
              border.width: 1
              visible: !lockSurface.shieldActive && lockContext.showFailure && lockContext.errorMessage
              opacity: visible ? 1.0 : 0.0

              RowLayout {
                id: errorRowLayout
                anchors.centerIn: parent
                spacing: 10

                NIcon {
                  icon: "alert-circle"
                  pointSize: Style.fontSizeXL
                  color: Color.mOnError
                }

                NText {
                  text: lockContext.errorMessage || "Authentication failed"
                  color: Color.mOnError
                  pointSize: Style.fontSizeL
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: 300
                  easing.type: Easing.OutCubic
                }
              }
            }

            // Compact status indicators container (compact mode only)
            Rectangle {
              width: {
                var hasBattery = batteryIndicator.isReady && BatteryService.hasAnyBattery();
                var hasKeyboard = keyboardLayout.currentLayout !== "Unknown";

                if (hasBattery && hasKeyboard) {
                  return 200;
                } else if (hasBattery || hasKeyboard) {
                  return 120;
                } else {
                  return 0;
                }
              }
              height: 40
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 96 + (Settings.data.general.compactLockScreen ? 116 : 220)
              topLeftRadius: Style.radiusL
              topRightRadius: Style.radiusL
              color: Color.mSurface
              visible: !lockSurface.shieldActive && Settings.data.general.compactLockScreen && ((batteryIndicator.isReady && BatteryService.hasAnyBattery()) || keyboardLayout.currentLayout !== "Unknown")

              RowLayout {
                anchors.centerIn: parent
                spacing: 16

                // Battery indicator
                RowLayout {
                  spacing: 6
                  visible: batteryIndicator.isReady && BatteryService.hasAnyBattery()

                  NIcon {
                    icon: BatteryService.getIcon(Math.round(batteryIndicator.percent), batteryIndicator.charging, batteryIndicator.isReady)
                    pointSize: Style.fontSizeM
                    color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurfaceVariant
                  }

                  NText {
                    text: Math.round(batteryIndicator.percent) + "%"
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                  }
                }

                // Keyboard layout indicator
                RowLayout {
                  spacing: 6
                  visible: keyboardLayout.currentLayout !== "Unknown"

                  NIcon {
                    icon: "keyboard"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: keyboardLayout.currentLayout
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                    elide: Text.ElideRight
                  }
                }
              }
            }

            // Bottom container with weather, password input and controls
            Rectangle {
              id: bottomContainer

              // Support for removing the session/power buttons at the bottom.
              readonly property int deltaY: Settings.data.general.showSessionButtonsOnLockScreen ? 0 : (Settings.data.general.compactLockScreen ? 36 : 48) + 14

              height: {
                let calcHeight = Settings.data.general.compactLockScreen ? 120 : 220;
                if (!Settings.data.general.showSessionButtonsOnLockScreen) {
                  calcHeight -= bottomContainer.deltaY;
                }
                return calcHeight;
              }
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 100 + bottomContainer.deltaY
              radius: Style.radiusL
              color: Color.mSurface
              visible: !lockSurface.shieldActive

              // Measure text widths to determine minimum button width (for container width calculation)
              Item {
                id: buttonRowTextMeasurer
                visible: false
                property real iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                property real fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                property real spacing: 6
                property real padding: 18 // Approximate horizontal padding per button

                // Measure all button text widths
                NText {
                  id: logoutText
                  text: I18n.tr("common.logout")
                  font.pointSize: buttonRowTextMeasurer.fontSize
                }
                NText {
                  id: suspendText
                  text: I18n.tr("common.suspend")
                  font.pointSize: buttonRowTextMeasurer.fontSize
                }
                NText {
                  id: hibernateText
                  text: Settings.data.general.showHibernateOnLockScreen ? I18n.tr("common.hibernate") : ""
                  font.pointSize: buttonRowTextMeasurer.fontSize
                }
                NText {
                  id: rebootText
                  text: I18n.tr("common.reboot")
                  font.pointSize: buttonRowTextMeasurer.fontSize
                }
                NText {
                  id: shutdownText
                  text: I18n.tr("common.shutdown")
                  font.pointSize: buttonRowTextMeasurer.fontSize
                }

                // Calculate maximum width needed
                property real maxTextWidth: Math.max(logoutText.implicitWidth, Math.max(suspendText.implicitWidth, Math.max(hibernateText.implicitWidth, Math.max(rebootText.implicitWidth, shutdownText.implicitWidth))))
                property real minButtonWidth: maxTextWidth + iconSize + spacing + padding
              }

              // Calculate minimum width based on button requirements
              // Button row needs: margins + buttons (4 or 5 depending on hibernate visibility) + spacings + margins
              // Plus ColumnLayout margins (14 on each side = 28 total)
              // Add extra buffer to ensure password input has proper padding
              property int buttonCount: Settings.data.general.showHibernateOnLockScreen ? 5 : 4
              property int spacingCount: buttonCount - 1
              property real minButtonRowWidth: buttonRowTextMeasurer.minButtonWidth > 0 ? (buttonCount * buttonRowTextMeasurer.minButtonWidth) + (spacingCount * 10) + 40 + (2 * Style.marginM) + 28 + (2 * Style.marginM) : 750
              width: Math.max(750, minButtonRowWidth)

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                // Top info row
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 65
                  spacing: 18
                  visible: !Settings.data.general.compactLockScreen

                  // Media widget with visualizer
                  Rectangle {
                    Layout.preferredWidth: 220
                    // Expand to take remaining space when weather is hidden
                    Layout.fillWidth: !(Settings.data.location.weatherEnabled && LocationService.data.weather !== null)
                    Layout.preferredHeight: 50
                    radius: Style.radiusL
                    color: "transparent"
                    clip: true
                    visible: MediaService.currentPlayer && MediaService.canPlay

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "linear"
                      z: 0
                      sourceComponent: NLinearSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "mirrored"
                      z: 0
                      sourceComponent: NMirroredSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "wave"
                      z: 0
                      sourceComponent: NWaveSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: 8
                      spacing: 8
                      z: 1

                      Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: Math.min(Style.radiusL, width / 2)
                        color: "transparent"
                        clip: true

                        NImageRounded {
                          anchors.fill: parent
                          anchors.margins: 2
                          radius: Math.min(Style.radiusL, width / 2)
                          imagePath: MediaService.trackArtUrl
                          fallbackIcon: "disc"
                          fallbackIconSize: Style.fontSizeM
                          borderColor: Color.mOutline
                          borderWidth: Style.borderS
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                          text: MediaService.trackTitle || "No media"
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        NText {
                          text: MediaService.trackArtist || ""
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }

                  Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.rightMargin: 4
                    color: Qt.alpha(Color.mOutline, 0.3)
                    visible: MediaService.currentPlayer && MediaService.canPlay
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM
                    visible: !(MediaService.currentPlayer && MediaService.canPlay)
                  }

                  // Current weather
                  RowLayout {
                    visible: Settings.data.location.weatherEnabled && LocationService.data.weather !== null
                    Layout.preferredWidth: 180
                    spacing: 8

                    NIcon {
                      Layout.alignment: Qt.AlignVCenter
                      icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode)
                      pointSize: Style.fontSizeXXXL
                      color: Color.mPrimary
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        NText {
                          text: {
                            var temp = LocationService.data.weather.current_weather.temperature;
                            var suffix = "C";
                            if (Settings.data.location.useFahrenheit) {
                              temp = LocationService.celsiusToFahrenheit(temp);
                              suffix = "F";
                            }
                            temp = Math.round(temp);
                            return temp + "°" + suffix;
                          }
                          pointSize: Style.fontSizeXL
                          font.weight: Style.fontWeightBold
                          color: Color.mOnSurface
                        }

                        NText {
                          text: {
                            var wind = LocationService.data.weather.current_weather.windspeed;
                            var unit = "km/h";
                            if (Settings.data.location.useFahrenheit) {
                              wind = wind * 0.621371; // Convert km/h to mph
                              unit = "mph";
                            }
                            wind = Math.round(wind);
                            return wind + " " + unit;
                          }
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                        }
                      }

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        NText {
                          text: Settings.data.location.name.split(",")[0]
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          visible: !Settings.data.location.hideWeatherCityName
                        }

                        NText {
                          text: (LocationService.data.weather.current && LocationService.data.weather.current.relativehumidity_2m) ? LocationService.data.weather.current.relativehumidity_2m + "% humidity" : ""
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                        }
                      }
                    }
                  }

                  // Forecast
                  RowLayout {
                    visible: Settings.data.location.weatherEnabled && LocationService.data.weather !== null
                    Layout.preferredWidth: 260
                    Layout.rightMargin: 8
                    spacing: 4

                    Repeater {
                      model: MediaService.currentPlayer && MediaService.canPlay ? 3 : 4
                      delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        NText {
                          text: {
                            var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"));
                            return I18n.locale.toString(weatherDate, "ddd");
                          }
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }

                        NIcon {
                          Layout.alignment: Qt.AlignHCenter
                          icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
                          pointSize: Style.fontSizeXL
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: {
                            var max = LocationService.data.weather.daily.temperature_2m_max[index];
                            var min = LocationService.data.weather.daily.temperature_2m_min[index];
                            if (Settings.data.location.useFahrenheit) {
                              max = LocationService.celsiusToFahrenheit(max);
                              min = LocationService.celsiusToFahrenheit(min);
                            }
                            max = Math.round(max);
                            min = Math.round(min);
                            return max + "°/" + min + "°";
                          }
                          pointSize: Style.fontSizeM
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }
                      }
                    }
                  }

                  Item {
                    Layout.fillWidth: batteryIndicator.isReady && BatteryService.hasAnyBattery()
                  }

                  // Battery and Keyboard Layout (full mode only)
                  ColumnLayout {
                    Layout.alignment: (batteryIndicator.isReady && BatteryService.hasAnyBattery()) ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignVCenter
                    spacing: 8
                    visible: (batteryIndicator.isReady && BatteryService.hasAnyBattery()) || keyboardLayout.currentLayout !== "Unknown"

                    // Battery
                    RowLayout {
                      spacing: 4
                      visible: batteryIndicator.isReady && BatteryService.hasAnyBattery()

                      NIcon {
                        icon: BatteryService.getIcon(Math.round(batteryIndicator.percent), batteryIndicator.charging, batteryIndicator.isReady)
                        pointSize: Style.fontSizeM
                        color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: Math.round(batteryIndicator.percent) + "%"
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM
                      }
                    }

                    // Keyboard Layout
                    RowLayout {
                      spacing: 4
                      visible: keyboardLayout.currentLayout !== "Unknown"

                      NIcon {
                        icon: "keyboard"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurfaceVariant
                      }

                      NText {
                        text: keyboardLayout.currentLayout
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                // Password input
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: Style.iRadiusL
                    color: Color.mSurface
                    border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
                    border.width: passwordInput.activeFocus ? 2 : 1

                    property bool passwordVisible: false

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 18
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 14

                      NIcon {
                        icon: "lock"
                        pointSize: Style.fontSizeL
                        color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      // Hidden input that receives actual text
                      TextInput {
                        id: passwordInput
                        width: 0
                        height: 0
                        visible: false

                        font.pointSize: Style.fontSizeM
                        color: Color.mPrimary
                        echoMode: parent.parent.passwordVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        text: lockContext.currentText
                        onTextChanged: {
                          lockContext.currentText = text;
                          // Dismiss shield when user starts typing
                          if (lockSurface.shieldActive && text.length > 0) {
                            lockSurface.dismissShield();
                          }
                        }

                        Keys.onPressed: function (event) {
                          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            lockContext.tryUnlock();
                          }
                        }

                        Component.onCompleted: {
                          if (!lockSurface.shieldActive) {
                            forceActiveFocus();
                          }
                        }
                      }

                      Row {
                        spacing: 0

                        Rectangle {
                          width: 2
                          height: 20
                          color: Color.mPrimary
                          visible: passwordInput.activeFocus && passwordInput.text.length === 0
                          anchors.verticalCenter: parent.verticalCenter

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: passwordInput.activeFocus && passwordInput.text.length === 0
                            NumberAnimation {
                              to: 0
                              duration: 530
                            }
                            NumberAnimation {
                              to: 1
                              duration: 530
                            }
                          }
                        }

                        // Password display - show dots or actual text based on passwordVisible
                        Item {
                          width: Math.min(passwordDisplayContent.width, 550)
                          height: 20
                          visible: passwordInput.text.length > 0 && !parent.parent.parent.passwordVisible
                          anchors.verticalCenter: parent.verticalCenter
                          clip: true

                          Row {
                            id: passwordDisplayContent
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                              model: passwordInput.text.length

                              NIcon {
                                icon: "circle-filled"
                                pointSize: Style.fontSizeS
                                color: Color.mPrimary
                                opacity: 1.0
                              }
                            }
                          }
                        }

                        NText {
                          text: passwordInput.text
                          color: Color.mPrimary
                          pointSize: Style.fontSizeM
                          visible: passwordInput.text.length > 0 && parent.parent.parent.passwordVisible
                          anchors.verticalCenter: parent.verticalCenter
                          elide: Text.ElideRight
                          width: Math.min(implicitWidth, 550)
                        }

                        Rectangle {
                          width: 2
                          height: 20
                          color: Color.mPrimary
                          visible: passwordInput.activeFocus && passwordInput.text.length > 0
                          anchors.verticalCenter: parent.verticalCenter

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: passwordInput.activeFocus && passwordInput.text.length > 0
                            NumberAnimation {
                              to: 0
                              duration: 530
                            }
                            NumberAnimation {
                              to: 1
                              duration: 530
                            }
                          }
                        }
                      }
                    }

                    // Eye button to toggle password visibility
                    Rectangle {
                      anchors.right: submitButton.left
                      anchors.rightMargin: 4
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36
                      height: 36
                      radius: Math.min(Style.iRadiusL, width / 2)
                      color: eyeButtonArea.containsMouse ? Color.mPrimary : "transparent"
                      visible: passwordInput.text.length > 0
                      enabled: !lockContext.unlockInProgress

                      NIcon {
                        anchors.centerIn: parent
                        icon: parent.parent.passwordVisible ? "eye-off" : "eye"
                        pointSize: Style.fontSizeM
                        color: eyeButtonArea.containsMouse ? Color.mOnPrimary : Color.mOnSurfaceVariant

                        Behavior on color {
                          ColorAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                          }
                        }
                      }

                      MouseArea {
                        id: eyeButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: parent.parent.passwordVisible = !parent.parent.passwordVisible
                      }

                      Behavior on color {
                        ColorAnimation {
                          duration: 200
                          easing.type: Easing.OutCubic
                        }
                      }
                    }

                    // Submit button
                    Rectangle {
                      id: submitButton
                      anchors.right: parent.right
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36
                      height: 36
                      radius: Math.min(Style.iRadiusL, width / 2)
                      color: submitButtonArea.containsMouse ? Color.mPrimary : "transparent"
                      border.color: Color.mPrimary
                      border.width: Style.borderS
                      enabled: !lockContext.unlockInProgress || lockContext.waitingForPassword

                      NIcon {
                        anchors.centerIn: parent
                        icon: "arrow-forward"
                        pointSize: Style.fontSizeM
                        color: submitButtonArea.containsMouse ? Color.mOnPrimary : Color.mPrimary

                        Behavior on color {
                          ColorAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                          }
                        }
                      }

                      MouseArea {
                        id: submitButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: lockContext.tryUnlock()
                      }

                      Behavior on color {
                        ColorAnimation {
                          duration: 200
                          easing.type: Easing.OutCubic
                        }
                      }
                    }

                    Behavior on border.color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }
                }

                // Session control buttons
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                  spacing: 0
                  visible: Settings.data.general.showSessionButtonsOnLockScreen

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }

                  NButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                    icon: "logout"
                    text: I18n.tr("common.logout")
                    outlined: true
                    backgroundColor: Color.mOnSurfaceVariant
                    textColor: Color.mOnPrimary
                    hoverColor: Color.mPrimary
                    fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                    iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                    fontWeight: Style.fontWeightMedium
                    horizontalAlignment: Qt.AlignHCenter
                    buttonRadius: Style.radiusL
                    onClicked: CompositorService.logout()
                  }

                  Item {
                    Layout.preferredWidth: 10
                  }

                  NButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                    icon: "suspend"
                    text: I18n.tr("common.suspend")
                    outlined: true
                    backgroundColor: Color.mOnSurfaceVariant
                    textColor: Color.mOnPrimary
                    hoverColor: Color.mPrimary
                    fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                    iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                    fontWeight: Style.fontWeightMedium
                    horizontalAlignment: Qt.AlignHCenter
                    buttonRadius: Style.radiusL
                    onClicked: CompositorService.suspend()
                  }

                  Item {
                    Layout.preferredWidth: 10
                    visible: Settings.data.general.showHibernateOnLockScreen
                  }

                  NButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                    icon: "hibernate"
                    text: I18n.tr("common.hibernate")
                    outlined: true
                    backgroundColor: Color.mOnSurfaceVariant
                    textColor: Color.mOnPrimary
                    hoverColor: Color.mPrimary
                    fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                    iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                    fontWeight: Style.fontWeightMedium
                    horizontalAlignment: Qt.AlignHCenter
                    buttonRadius: Style.radiusL
                    visible: Settings.data.general.showHibernateOnLockScreen
                    onClicked: CompositorService.hibernate()
                  }

                  Item {
                    Layout.preferredWidth: 10
                  }

                  NButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                    icon: "reboot"
                    text: I18n.tr("common.reboot")
                    outlined: true
                    backgroundColor: Color.mOnSurfaceVariant
                    textColor: Color.mOnPrimary
                    hoverColor: Color.mPrimary
                    fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                    iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                    fontWeight: Style.fontWeightMedium
                    horizontalAlignment: Qt.AlignHCenter
                    buttonRadius: Style.radiusL
                    onClicked: CompositorService.reboot()
                  }

                  Item {
                    Layout.preferredWidth: 10
                  }

                  NButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                    icon: "shutdown"
                    text: I18n.tr("common.shutdown")
                    outlined: true
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    hoverColor: Color.mError
                    fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
                    iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                    fontWeight: Style.fontWeightMedium
                    horizontalAlignment: Qt.AlignHCenter
                    buttonRadius: Style.radiusL
                    onClicked: CompositorService.shutdown()
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }
                }
              }
            }
          }

          // Reset state when lock screen activates
          Connections {
            target: lockSession
            function onLockedChanged() {
              if (lockSession.locked) {
                lockContext.resetForNewSession();
                // Reset shield state - user must interact before auth starts
                // This gives fprintd time to stabilize after suspend/resume
                lockSurface.shieldActive = true;
                // Re-detect fingerprint device (handles device unplugging between locks)
                FingerprintService.refresh();
              }
            }
          }
        }
      }
    }
  }
}

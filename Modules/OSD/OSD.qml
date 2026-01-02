import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

// Unified OSD component that displays volume, input volume, and brightness changes
Variants {
  id: osd

  // Do not change the order or it will break settings.
  enum Type {
    Volume,
    InputVolume,
    Brightness,
    LockKey,
    CustomText
  }

  model: Quickshell.screens.filter(screen => (Settings.data.osd.monitors.includes(screen.name) || Settings.data.osd.monitors.length === 0) && Settings.data.osd.enabled)

  delegate: Loader {
    id: root

    required property ShellScreen modelData

    active: false

    // OSD State
    property int currentOSDType: -1 // OSD.Type enum value, -1 means none
    property bool startupComplete: false
    property real currentBrightness: 0
    property string customText: ""
    property string customIcon: ""

    // Lock Key States
    property string lastLockKeyChanged: ""  // "caps", "num", "scroll", or ""

    // Current values (computed properties)
    readonly property real currentVolume: AudioService.volume
    readonly property bool isMuted: AudioService.muted
    readonly property real currentInputVolume: AudioService.inputVolume
    readonly property bool isInputMuted: AudioService.inputMuted
    readonly property real epsilon: 0.005

    // LockKey OSD enabled state (reactive to settings)
    readonly property bool lockKeyOSDEnabled: {
      const enabledTypes = Settings.data.osd.enabledTypes || [];
      if (enabledTypes.length === 0)
        return false;
      return enabledTypes.includes(OSD.Type.LockKey);
    }

    readonly property var validIcons: {
      const iconKeys = Object.keys(Icons.icons);
      const aliasKeys = Object.keys(Icons.aliases);
      return new Set([...iconKeys, ...aliasKeys]);
    }

    function getIcon() {
      switch (currentOSDType) {
      case OSD.Type.Volume:
        if (isMuted)
          return "volume-mute";
        // Show volume-x icon when volume is effectively 0% (within rounding threshold)
        if (currentVolume < root.epsilon)
          return "volume-x";
        return currentVolume <= 0.5 ? "volume-low" : "volume-high";
      case OSD.Type.InputVolume:
        return isInputMuted ? "microphone-off" : "microphone";
      case OSD.Type.Brightness:
        // Show sun-off icon when brightness is effectively 0% (within rounding threshold)
        if (currentBrightness < root.epsilon)
          return "sun-off";
        return currentBrightness <= 0.5 ? "brightness-low" : "brightness-high";
      case OSD.Type.LockKey:
        return "keyboard";
      case OSD.Type.CustomText:
        return root.customIcon || "info-circle";
      default:
        return "";
      }
    }

    function getCurrentValue() {
      switch (currentOSDType) {
      case OSD.Type.Volume:
        return isMuted ? 0 : currentVolume;
      case OSD.Type.InputVolume:
        return isInputMuted ? 0 : currentInputVolume;
      case OSD.Type.Brightness:
        return currentBrightness;
      case OSD.Type.LockKey:
        return 1.0; // Always show 100% when showing lock key status
      case OSD.Type.CustomText:
        return 1.0;
      default:
        return 0;
      }
    }

    function getMaxValue() {
      if (currentOSDType === OSD.Type.Volume || currentOSDType === OSD.Type.InputVolume) {
        return Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
      }
      return 1.0;
    }

    function getDisplayPercentage() {
      if (currentOSDType === OSD.Type.LockKey) {
        // For lock keys, return the pre-determined status text
        return lastLockKeyChanged;
      }
      if (currentOSDType === OSD.Type.CustomText) {
        return customText;
      }

      const value = getCurrentValue();
      const max = getMaxValue();
      if ((currentOSDType === OSD.Type.Volume || currentOSDType === OSD.Type.InputVolume) && Settings.data.audio.volumeOverdrive) {
        const pct = Math.round(value * 100);
        return pct + "%";
      }
      const pct = Math.round(Math.min(max, value) * 100);
      return pct + "%";
    }

    function getProgressColor() {
      const isMutedState = (currentOSDType === OSD.Type.Volume && isMuted) || (currentOSDType === OSD.Type.InputVolume && isInputMuted);
      if (isMutedState) {
        return Color.mError;
      }
      // When volumeOverdrive is enabled, show error color if volume is above 100%
      if ((currentOSDType === OSD.Type.Volume || currentOSDType === OSD.Type.InputVolume) && Settings.data.audio.volumeOverdrive) {
        const value = getCurrentValue();
        if (value > 1.0) {
          return Color.mError;
        }
      }
      // For lock keys, use a different color to indicate the lock state
      if (currentOSDType === OSD.Type.LockKey) {
        // Check the specific lock key that was changed
        if (lastLockKeyChanged.startsWith("CAPS")) {
          return LockKeysService.capsLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        } else if (lastLockKeyChanged.startsWith("NUM")) {
          return LockKeysService.numLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        } else if (lastLockKeyChanged.startsWith("SCROLL")) {
          return LockKeysService.scrollLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        }
      }
      if (currentOSDType === OSD.Type.CustomText) {
        return Color.mPrimary;
      }
      return Color.mPrimary;
    }

    function getIconColor() {
      const isMutedState = (currentOSDType === OSD.Type.Volume && isMuted) || (currentOSDType === OSD.Type.InputVolume && isInputMuted);
      if (isMutedState)
        return Color.mError;

      if (currentOSDType === OSD.Type.LockKey) {
        // Check the specific lock key that was changed
        if (lastLockKeyChanged.startsWith("CAPS")) {
          return LockKeysService.capsLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        } else if (lastLockKeyChanged.startsWith("NUM")) {
          return LockKeysService.numLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        } else if (lastLockKeyChanged.startsWith("SCROLL")) {
          return LockKeysService.scrollLockOn ? Color.mPrimary : Color.mOnSurfaceVariant;
        }
      }

      return Color.mOnSurface;
    }

    // Brightness Handling
    function connectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        const monitor = BrightnessService.monitors[i];
        monitor.brightnessUpdated.disconnect(onBrightnessChanged);
        monitor.brightnessUpdated.connect(onBrightnessChanged);
      }
    }

    function onBrightnessChanged(newBrightness) {
      root.currentBrightness = newBrightness;
      // Don't show OSD if brightness panel is open
      var brightnessPanel = PanelService.getPanel("brightnessPanel", root.modelData);
      if (brightnessPanel && brightnessPanel.isPanelOpen) {
        return;
      }
      showOSD(OSD.Type.Brightness);
    }

    // Check if a specific OSD type is enabled
    function isTypeEnabled(type) {
      const enabledTypes = Settings.data.osd.enabledTypes || [];
      // If enabledTypes is empty, no types are enabled (no OSD will be shown)
      if (enabledTypes.length === 0)
        return false;
      return enabledTypes.includes(type);
    }

    // OSD Display Control
    function showOSD(type) {
      // Ignore all OSD requests during startup period
      if (!startupComplete)
        return;

      // Check if this OSD type is enabled
      if (!isTypeEnabled(type))
        return;

      currentOSDType = type;

      if (!root.active) {
        root.active = true;
      }

      if (root.item) {
        root.item.showOSD();
      } else {
        Qt.callLater(() => {
                       if (root.item)
                       root.item.showOSD();
                     });
      }
    }

    function hideOSD() {
      if (root.item?.osdItem) {
        root.item.osdItem.hideImmediately();
      } else if (root.active) {
        root.active = false;
      }
    }

    // Signal Connections
    Connections {
      target: OSDService

      function onShowCustomText(text, icon) {
        root.customText = text;

        if (icon && root.validIcons.has(icon)) {
          root.customIcon = icon;
        } else {
          if (icon) {
            Logger.w("OSD", "Invalid custom icon name received: '" + icon + "'. Falling back to default.");
          }
          root.customIcon = "info-circle";
        }
        showOSD(OSD.Type.CustomText);
      }
    }

    // AudioService monitoring
    Connections {
      target: AudioService

      function onVolumeChanged() {
        showOSD(OSD.Type.Volume);
      }

      function onMutedChanged() {
        if (AudioService.consumeOutputOSDSuppression())
          return;
        showOSD(OSD.Type.Volume);
      }

      function onInputVolumeChanged() {
        if (AudioService.hasInput)
          showOSD(OSD.Type.InputVolume);
      }

      function onInputMutedChanged() {
        if (!AudioService.hasInput)
          return;
        if (AudioService.consumeInputOSDSuppression())
          return;
        showOSD(OSD.Type.InputVolume);
      }

      // Refresh OSD when device changes to ensure correct volume is displayed
      function onSinkChanged() {
        // If volume OSD is currently showing, refresh it to show new device's volume
        if (root.currentOSDType === OSD.Type.Volume) {
          Qt.callLater(() => {
                         showOSD(OSD.Type.Volume);
                       });
        }
      }

      function onSourceChanged() {
        // If input volume OSD is currently showing, refresh it to show new device's volume
        if (root.currentOSDType === OSD.Type.InputVolume) {
          Qt.callLater(() => {
                         showOSD(OSD.Type.InputVolume);
                       });
        }
      }
    }

    // Brightness monitoring
    Connections {
      target: BrightnessService
      function onMonitorsChanged() {
        connectBrightnessMonitors();
      }
    }

    // LockKeys monitoring with a cleaner approach
    // Only connect when LockKey OSD is enabled to avoid starting the service unnecessarily
    Connections {
      target: root.lockKeyOSDEnabled ? LockKeysService : null

      function onCapsLockChanged(active) {
        root.lastLockKeyChanged = active ? "CAPS ON" : "CAPS OFF";
        root.showOSD(OSD.Type.LockKey);
      }

      function onNumLockChanged(active) {
        root.lastLockKeyChanged = active ? "NUM ON" : "NUM OFF";
        root.showOSD(OSD.Type.LockKey);
      }

      function onScrollLockChanged(active) {
        root.lastLockKeyChanged = active ? "SCROLL ON" : "SCROLL OFF";
        root.showOSD(OSD.Type.LockKey);
      }
    }

    // Startup timer - connect brightness monitors and enable OSD after 2 seconds
    Timer {
      id: startupTimer
      interval: 2000
      running: true
      onTriggered: {
        connectBrightnessMonitors();
        root.startupComplete = true;
      }
    }

    // Visual Component
    sourceComponent: PanelWindow {
      id: panel
      screen: modelData

      // Position configuration
      readonly property string location: Settings.data.osd?.location || "top_right"
      readonly property bool isTop: location === "top" || location.startsWith("top")
      readonly property bool isBottom: location === "bottom" || location.startsWith("bottom")
      readonly property bool isLeft: location.includes("_left") || location === "left"
      readonly property bool isRight: location.includes("_right") || location === "right"
      readonly property bool verticalMode: location === "left" || location === "right"

      // Hidden text element for measuring lock key text width
      NText {
        id: lockKeyTextMetrics
        visible: false
        text: root.getDisplayPercentage()
        pointSize: Style.fontSizeM
        family: Settings.data.ui.fontFixed
        font.weight: Style.fontWeightMedium
        elide: Text.ElideNone
        wrapMode: Text.NoWrap
      }

      NText {
        id: customTextMetrics
        visible: false
        text: root.customText
        pointSize: Style.fontSizeM
        family: Settings.data.ui.fontFixed
        font.weight: Style.fontWeightMedium
        elide: Text.ElideNone
        wrapMode: Text.NoWrap
      }

      // Dimensions
      readonly property bool isShortMode: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText
      readonly property int longHWidth: Math.round(320 * Style.uiScaleRatio)
      readonly property int longHHeight: Math.round(72 * Style.uiScaleRatio)
      readonly property int shortHWidth: Math.round(180 * Style.uiScaleRatio)
      readonly property int longVWidth: Math.round(80 * Style.uiScaleRatio)
      readonly property int longVHeight: Math.round(280 * Style.uiScaleRatio)
      readonly property int shortVHeight: Math.round(180 * Style.uiScaleRatio)

      // Dynamic width for horizontal custom text based on text length
      readonly property int customTextHWidth: {
        if (root.currentOSDType !== OSD.Type.CustomText || verticalMode) {
          return shortHWidth;
        }
        const textWidth = Math.ceil(customTextMetrics.contentWidth || 0);
        if (textWidth === 0) {
          // Fallback if measurement not ready
          return longHWidth;
        }
        const iconWidth = Style.fontSizeXL * Style.uiScaleRatio;
        const margins = Style.marginL * 2; // Left and right content margins
        const spacing = Style.marginM; // Spacing between icon and text
        const bgMargins = Style.marginM * 1.5 * 2; // Background margins
        const totalWidth = textWidth + iconWidth + margins + spacing + bgMargins;
        // Ensure minimum width and add some buffer
        return Math.max(shortHWidth, Math.round(totalWidth * 1.1));
      }

      // Dynamic width for horizontal lock keys based on text length
      // Explicitly bind to contentWidth to ensure reactivity
      readonly property int lockKeyHWidth: {
        if (root.currentOSDType !== OSD.Type.LockKey || verticalMode) {
          return shortHWidth;
        }
        const text = root.getDisplayPercentage();
        if (!text) {
          return shortHWidth;
        }
        // Access contentWidth to create binding dependency
        const textWidth = Math.ceil(lockKeyTextMetrics.contentWidth || 0);
        if (textWidth === 0) {
          // Fallback: estimate based on text length if measurement not ready
          const fontSize = Style.fontSizeM * Settings.data.ui.fontFixedScale * Style.uiScaleRatio;
          const estimatedWidth = text.length * fontSize * 0.6;
          const iconWidth = Style.fontSizeXL * Style.uiScaleRatio;
          const margins = Style.marginL * 2;
          const spacing = Style.marginM;
          const bgMargins = Style.marginM * 1.5 * 2;
          return Math.max(shortHWidth, Math.round((estimatedWidth + iconWidth + margins + spacing + bgMargins) * 1.1));
        }
        const iconWidth = Style.fontSizeXL * Style.uiScaleRatio;
        const margins = Style.marginL * 2; // Left and right content margins
        const spacing = Style.marginM; // Spacing between icon and text
        const bgMargins = Style.marginM * 1.5 * 2; // Background margins
        const totalWidth = textWidth + iconWidth + margins + spacing + bgMargins;
        // Ensure minimum width and add some buffer
        return Math.max(shortHWidth, Math.round(totalWidth * 1.1));
      }

      // Dynamic height for vertical lock keys based on text length
      readonly property int lockKeyVHeight: {
        if (root.currentOSDType !== OSD.Type.LockKey || !verticalMode) {
          return shortVHeight;
        }
        const text = root.getDisplayPercentage();
        const charCount = text ? text.length : 0;
        if (charCount === 0) {
          return shortVHeight;
        }
        // Calculate height: font size * char count + margins + icon space
        // Font size M (11pt) scaled, plus some spacing between chars
        const fontSize = Style.fontSizeM * Settings.data.ui.fontFixedScale * Style.uiScaleRatio;
        const charHeight = fontSize * 1.3; // Add 30% for line height (matches Layout.preferredHeight)
        const textHeight = charCount * charHeight;
        // Background margins (Style.marginM * 1.5 * 2 for top and bottom)
        const bgMargins = Style.marginM * 1.5 * 2;
        // Content margins (Style.marginL * 2 for top and bottom)
        const contentMargins = Style.marginL * 2;
        // Icon size: fontSizeXL scaled, with extra space for icon rendering and padding
        const iconSize = Style.fontSizeXL * Style.uiScaleRatio * 1.8; // Add 80% for icon rendering and padding
        // Spacing between text and icon (Style.marginM for lock keys)
        const textIconSpacing = Style.marginM;
        // Add extra buffer to ensure everything fits comfortably
        const buffer = Style.marginL;
        const totalHeight = textHeight + bgMargins + contentMargins + iconSize + textIconSpacing + buffer;
        // Ensure minimum height and add extra padding for safety
        return Math.max(shortVHeight, Math.round(totalHeight * 1.1));
      }

      readonly property int customTextVHeight: {
        if (root.currentOSDType !== OSD.Type.CustomText || !verticalMode) {
          return shortVHeight;
        }
        const text = root.customText;
        const charCount = text ? text.length : 0;
        if (charCount === 0) {
          return shortVHeight;
        }
        const fontSize = Style.fontSizeM * Settings.data.ui.fontFixedScale * Style.uiScaleRatio;
        const charHeight = fontSize * 1.3;
        const textHeight = charCount * charHeight;
        const bgMargins = Style.marginM * 1.5 * 2;
        const contentMargins = Style.marginL * 2;
        const iconSize = Style.fontSizeXL * Style.uiScaleRatio * 1.8;
        const textIconSpacing = Style.marginM;
        const buffer = Style.marginL;
        const totalHeight = textHeight + bgMargins + contentMargins + iconSize + textIconSpacing + buffer;
        return Math.max(shortVHeight, Math.round(totalHeight * 1.1));
      }

      readonly property int barThickness: {
        const base = Math.max(8, Math.round(8 * Style.uiScaleRatio));
        return base % 2 === 0 ? base : base + 1;
      }

      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      function calculateMargin(isAnchored, position) {
        if (!isAnchored)
          return 0;

        let base = Style.marginM;
        if (Settings.data.bar.position === position) {
          const isVertical = position === "top" || position === "bottom";
          const floatExtra = Math.ceil(Settings.data.bar.floating ? (isVertical ? Settings.data.bar.marginVertical : Settings.data.bar.marginHorizontal) * Style.marginXL : 0);
          return Style.barHeight + base + floatExtra;
        }
        return base;
      }

      margins.top: calculateMargin(anchors.top, "top")
      margins.bottom: calculateMargin(anchors.bottom, "bottom")
      margins.left: calculateMargin(anchors.left, "left")
      margins.right: calculateMargin(anchors.right, "right")

      implicitWidth: verticalMode ? longVWidth : (root.currentOSDType === OSD.Type.CustomText ? customTextHWidth : (isShortMode ? lockKeyHWidth : longHWidth))
      implicitHeight: verticalMode ? (root.currentOSDType === OSD.Type.CustomText ? customTextVHeight : (isShortMode ? lockKeyVHeight : longVHeight)) : longHHeight
      color: Color.transparent

      WlrLayershell.namespace: "noctalia-osd-" + (screen?.name || "unknown")
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.layer: Settings.data.osd?.overlayLayer ? WlrLayer.Overlay : WlrLayer.Top
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      Item {
        id: osdItem
        anchors.fill: parent
        visible: false
        opacity: 0
        scale: 0.85

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Timer {
          id: hideTimer
          interval: Settings.data.osd.autoHideMs
          onTriggered: osdItem.hide()
        }

        Timer {
          id: visibilityTimer
          interval: Style.animationNormal + 50
          onTriggered: {
            osdItem.visible = false;
            root.currentOSDType = -1;
            root.lastLockKeyChanged = "";
            root.customText = "";
            root.customIcon = "";
            root.active = false;
          }
        }

        Rectangle {
          id: background
          anchors.fill: parent
          anchors.margins: Style.marginM * 1.5
          radius: Style.radiusL
          color: Qt.alpha(Color.mSurface, Settings.data.osd.backgroundOpacity || 1.0)
          border.color: Qt.alpha(Color.mOutline, Settings.data.osd.backgroundOpacity || 1.0)
          border.width: {
            const bw = Math.max(2, Style.borderM);
            return bw % 2 === 0 ? bw : bw + 1;
          }
        }

        NDropShadow {
          anchors.fill: background
          source: background
          autoPaddingEnabled: true
        }

        Loader {
          id: contentLoader
          anchors.fill: background
          anchors.margins: Style.marginM
          active: true
          sourceComponent: panel.verticalMode ? verticalContent : horizontalContent
        }

        Component {
          id: horizontalContent
          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.marginL
            anchors.rightMargin: Style.marginL
            spacing: Style.marginM

            TextMetrics {
              id: percentageMetrics
              font.family: Settings.data.ui.fontFixed
              font.weight: Style.fontWeightMedium
              font.pointSize: Style.fontSizeS * (Settings.data.ui.fontFixedScale * Style.uiScaleRatio)
              text: "150%"
            }

            // Common Icon for all types
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

            // Lock Key or Custom Status Text (replaces progress bar)
            NText {
              visible: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText
              text: root.getDisplayPercentage()
              color: root.getProgressColor()
              pointSize: Style.fontSizeM
              family: Settings.data.ui.fontFixed
              font.weight: Style.fontWeightMedium
              elide: Text.ElideNone
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              Layout.alignment: Qt.AlignVCenter
            }

            // Progress Bar for Volume/Brightness
            Rectangle {
              visible: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              height: panel.barThickness
              radius: Math.min(Style.iRadiusL, panel.barThickness / 2)
              color: Color.mSurfaceVariant

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

            // Percentage Text for Volume/Brightness
            NText {
              visible: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText
              text: root.getDisplayPercentage()
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              family: Settings.data.ui.fontFixed
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              horizontalAlignment: Text.AlignRight
              verticalAlignment: Text.AlignVCenter
              Layout.fillWidth: false
              Layout.preferredWidth: Math.ceil(percentageMetrics.width) + Math.round(8 * Style.uiScaleRatio)
              Layout.maximumWidth: Math.ceil(percentageMetrics.width) + Math.round(8 * Style.uiScaleRatio)
              Layout.minimumWidth: Math.ceil(percentageMetrics.width)
            }
          }
        }

        Component {
          id: verticalContent
          ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Style.marginL
            anchors.bottomMargin: Style.marginL
            spacing: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText ? Style.marginM : Style.marginS
            clip: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText

            ColumnLayout {
              id: textVerticalLayout
              visible: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText
              Layout.fillWidth: true
              Layout.fillHeight: false
              Layout.alignment: Qt.AlignHCenter
              spacing: 0

              property var verticalTextChars: []

              function updateVerticalTextChars() {
                const text = root.getDisplayPercentage();
                const chars = [];
                for (let i = 0; i < text.length; i++) {
                  chars.push(text[i]);
                }
                verticalTextChars = chars;
              }

              Component.onCompleted: updateVerticalTextChars()

              Connections {
                target: root
                function onLastLockKeyChangedChanged() {
                  if (root.currentOSDType === OSD.Type.LockKey) {
                    textVerticalLayout.updateVerticalTextChars();
                  }
                }
                function onCustomTextChanged() {
                  if (root.currentOSDType === OSD.Type.CustomText) {
                    textVerticalLayout.updateVerticalTextChars();
                  }
                }
                function onCurrentOSDTypeChanged() {
                  if (root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText) {
                    textVerticalLayout.updateVerticalTextChars();
                  }
                }
              }

              Repeater {
                model: textVerticalLayout.verticalTextChars

                NText {
                  text: modelData || ""
                  color: root.getProgressColor()
                  pointSize: Style.fontSizeM
                  family: Settings.data.ui.fontFixed
                  font.weight: Style.fontWeightMedium
                  Layout.fillWidth: true
                  Layout.preferredHeight: {
                    const fontSize = Style.fontSizeM * Settings.data.ui.fontFixedScale * Style.uiScaleRatio;
                    return Math.round(fontSize * 1.3);
                  }
                  Layout.alignment: Qt.AlignHCenter
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }

            NText {
              visible: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText
              text: root.getDisplayPercentage()
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              family: Settings.data.ui.fontFixed
              font.weight: Style.fontWeightRegular
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignHCenter
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              Layout.preferredHeight: Math.round(20 * Style.uiScaleRatio)
            }

            Item {
              visible: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText
              Layout.fillWidth: true
              Layout.fillHeight: root.currentOSDType !== OSD.Type.LockKey && root.currentOSDType !== OSD.Type.CustomText

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: panel.barThickness
                radius: Math.min(Style.iRadiusL, panel.barThickness / 2)
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

            NIcon {
              icon: root.getIcon()
              color: root.getIconColor()
              pointSize: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText ? Style.fontSizeXL : Style.fontSizeL
              Layout.alignment: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText ? Qt.AlignHCenter : (Qt.AlignHCenter | Qt.AlignBottom)
              Layout.preferredHeight: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText ? (Style.fontSizeXL * Style.uiScaleRatio * 1.5) : -1
              Layout.minimumHeight: root.currentOSDType === OSD.Type.LockKey || root.currentOSDType === OSD.Type.CustomText ? (Style.fontSizeXL * Style.uiScaleRatio) : 0

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.InOutQuad
                }
              }
            }
          }
        }

        function show() {
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.visible = true;

          Qt.callLater(() => {
                         osdItem.opacity = 1;
                         osdItem.scale = 1.0;
                       });

          hideTimer.start();
        }

        function hide() {
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.opacity = 0;
          osdItem.scale = 0.85;
          visibilityTimer.start();
        }

        function hideImmediately() {
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.opacity = 0;
          osdItem.scale = 0.85;
          osdItem.visible = false;
          root.currentOSDType = -1;
          root.active = false;
        }
      }

      function showOSD() {
        osdItem.show();
      }
    }
  }
}

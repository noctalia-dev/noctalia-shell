import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  readonly property bool largeButtonsStyle: Settings.data.sessionMenu.largeButtonsStyle || false
  readonly property bool largeButtonsLayout: Settings.data.sessionMenu.largeButtonsLayout || "grid"
  readonly property bool showBlurBackground: Settings.data.sessionMenu.showBlurBackground || false

  // Make panel background transparent for large buttons style
  panelBackgroundColor: (largeButtonsStyle || showBlurBackground) ? "transparent" : Color.mSurface

  preferredWidth: largeButtonsStyle ? 0 : Math.round(440 * Style.uiScaleRatio)
  preferredWidthRatio: largeButtonsStyle ? 1.0 : 0
  preferredHeight: {
    if (largeButtonsStyle) {
      return 0; // Use ratio instead
    }
    var headerHeight = Settings.data.sessionMenu.showHeader ? Style.baseWidgetSize * 0.6 : 0;

    var dividerHeight = Settings.data.sessionMenu.showHeader ? Style.marginS : 0;
    var buttonHeight = Style.baseWidgetSize * 1.3 * Style.uiScaleRatio;
    var buttonSpacing = Style.marginS;
    var enabledCount = powerOptions.length;

    var headerSpacing = Settings.data.sessionMenu.showHeader ? (Style.marginL * 2) : 0;
    var baseHeight = (Style.marginL * 4) + headerHeight + dividerHeight + headerSpacing;
    var buttonsHeight = enabledCount > 0 ? (buttonHeight * enabledCount) + (buttonSpacing * (enabledCount - 1)) : 0;

    return Math.round(baseHeight + buttonsHeight);
  }
  preferredHeightRatio: largeButtonsStyle ? 1.0 : 0

  // Positioning - large buttons style is always centered and fullscreen
  readonly property string panelPosition: Settings.data.sessionMenu.position

  panelAnchorHorizontalCenter: largeButtonsStyle || panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: largeButtonsStyle || panelPosition === "center"
  panelAnchorLeft: !largeButtonsStyle && panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: !largeButtonsStyle && panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: !largeButtonsStyle && panelPosition.startsWith("bottom_")
  panelAnchorTop: !largeButtonsStyle && panelPosition.startsWith("top_")

  // SessionMenu handle it's own closing logic
  property bool closeWithEscape: false

  // Timer properties
  readonly property int timerDuration: Settings.data.sessionMenu.countdownDuration
  property string pendingAction: ""
  property bool timerActive: false
  property int timeRemaining: 0

  // Navigation properties
  property int selectedIndex: -1
  property bool ignoreMouseHover: true // Transient flag, should always be true on init

  // Global mouse tracking for movement detection across delegates
  property real globalLastMouseX: 0
  property real globalLastMouseY: 0
  property bool globalMouseInitialized: false
  property bool mouseTrackingReady: false // Delay tracking until panel is settled

  Timer {
    id: mouseTrackingDelayTimer
    interval: Style.animationNormal + 50 // Wait for panel animation to complete + safety margin
    repeat: false
    onTriggered: {
      root.mouseTrackingReady = true;
      root.globalMouseInitialized = false; // Reset so we get fresh initial position
    }
  }

  // Action metadata mapping
  readonly property var actionMetadata: {
    "lock": {
      "icon": "lock",
      "title": I18n.tr("common.lock"),
      "isShutdown": false
    },
    "suspend": {
      "icon": "suspend",
      "title": I18n.tr("common.suspend"),
      "isShutdown": false
    },
    "hibernate": {
      "icon": "hibernate",
      "title": I18n.tr("common.hibernate"),
      "isShutdown": false
    },
    "reboot": {
      "icon": "reboot",
      "title": I18n.tr("common.reboot"),
      "isShutdown": false
    },
    "rebootToUefi": {
      "icon": "reboot",
      "title": I18n.tr("common.reboot-to-uefi"),
      "isShutdown": false
    },
    "logout": {
      "icon": "logout",
      "title": I18n.tr("common.logout"),
      "isShutdown": false
    },
    "shutdown": {
      "icon": "shutdown",
      "title": I18n.tr("common.shutdown"),
      "isShutdown": true
    }
  }

  // Build powerOptions from settings, filtering enabled ones and adding metadata
  // _powerOptionsVersion forces re-evaluation when settings change
  property int _powerOptionsVersion: 0
  property var powerOptions: {
    // Reference version to trigger re-evaluation
    void (_powerOptionsVersion);
    var options = [];
    var settingsOptions = Settings.data.sessionMenu.powerOptions || [];

    for (var i = 0; i < settingsOptions.length; i++) {
      var settingOption = settingsOptions[i];
      if (settingOption.enabled && actionMetadata[settingOption.action]) {
        var metadata = actionMetadata[settingOption.action];
        options.push({
                       "action": settingOption.action,
                       "icon": metadata.icon,
                       "title": metadata.title,
                       "isShutdown": metadata.isShutdown,
                       "countdownEnabled": settingOption.countdownEnabled !== undefined ? settingOption.countdownEnabled : true,
                       "command": settingOption.command || "",
                       "keybind": settingOption.keybind || ""
                     });
      }
    }

    return options;
  }

  Connections {
    target: Settings.data.sessionMenu
    function onPowerOptionsChanged() {
      root._powerOptionsVersion++;
    }
  }

  // Lifecycle handlers
  onOpened: {
    selectedIndex = -1;
    ignoreMouseHover = true;
    globalMouseInitialized = false;
    mouseTrackingReady = false;
    mouseTrackingDelayTimer.restart();
  }

  onClosed: {
    cancelTimer();
    selectedIndex = -1;
    ignoreMouseHover = true;
  }

  // Timer management
  function startTimer(action) {
    // Check if global countdown is disabled
    if (!Settings.data.sessionMenu.enableCountdown) {
      executeAction(action);
      return;
    }

    // Check per-item countdown setting
    var option = null;
    for (var i = 0; i < powerOptions.length; i++) {
      if (powerOptions[i].action === action) {
        option = powerOptions[i];
        break;
      }
    }

    // If this specific action has countdown disabled, execute immediately
    if (option && option.countdownEnabled === false) {
      executeAction(action);
      return;
    }

    if (timerActive && pendingAction === action) {
      // Second click - execute immediately
      executeAction(action);
      return;
    }

    pendingAction = action;
    timeRemaining = timerDuration;
    timerActive = true;
    countdownTimer.start();
  }

  function cancelTimer() {
    timerActive = false;
    pendingAction = "";
    timeRemaining = 0;
    countdownTimer.stop();
  }

  function executeAction(action) {
    // Stop timer but don't reset other properties yet
    countdownTimer.stop();

    // Use default behavior or custom command handled by CompositorService
    switch (action) {
    case "lock":
      CompositorService.lock();
      break;
    case "suspend":
      // Check if we should lock before suspending
      if (Settings.data.general.lockOnSuspend) {
        CompositorService.lockAndSuspend();
      } else {
        CompositorService.suspend();
      }
      break;
    case "hibernate":
      CompositorService.hibernate();
      break;
    case "reboot":
      CompositorService.reboot();
      break;
    case "rebootToUefi":
      CompositorService.rebootToUefi();
      break;
    case "logout":
      CompositorService.logout();
      break;
    case "shutdown":
      CompositorService.shutdown();
      break;
    }

    // Reset timer state and close panel
    cancelTimer();
    root.close();
  }

  // Navigation functions
  function selectNextWrapped() {
    if (powerOptions.length > 0) {
      if (selectedIndex < 0) {
        selectedIndex = 0;
      } else {
        selectedIndex = (selectedIndex + 1) % powerOptions.length;
      }
    }
  }

  function selectPreviousWrapped() {
    if (powerOptions.length > 0) {
      if (selectedIndex < 0) {
        selectedIndex = powerOptions.length - 1;
      } else {
        selectedIndex = (((selectedIndex - 1) % powerOptions.length) + powerOptions.length) % powerOptions.length;
      }
    }
  }

  function selectFirst() {
    if (powerOptions.length > 0) {
      selectedIndex = 0;
    } else {
      selectedIndex = -1;
    }
  }

  function selectLast() {
    if (powerOptions.length > 0) {
      selectedIndex = powerOptions.length - 1;
    } else {
      selectedIndex = -1;
    }
  }

  function getGridInfo() {
    let columns, rows;
    if (Settings.data.sessionMenu.largeButtonsLayout === "single-row") {
      columns = powerOptions.length;
      rows = 1;
    } else {
      columns = Math.min(3, Math.ceil(Math.sqrt(powerOptions.length)));
      rows = Math.ceil(powerOptions.length / columns);
    }

    return {
      columns,
      rows,
      currentRow: selectedIndex >= 0 ? Math.floor(selectedIndex / columns) : -1,
      currentCol: selectedIndex >= 0 ? selectedIndex % columns : -1,
      itemsInRow: row => Math.min(columns, powerOptions.length - row * columns)
    };
  }

  // Unified navigation function
  function navigateGrid(direction) {
    if (powerOptions.length === 0)
      return;

    const grid = getGridInfo();
    // If no selection, start at first item
    let newRow = grid.currentRow >= 0 ? grid.currentRow : 0;
    let newCol = grid.currentCol >= 0 ? grid.currentCol : 0;

    switch (direction) {
    case "left":
      newCol = newCol - 1 < 0 ? grid.itemsInRow(newRow) - 1 : newCol - 1;
      break;
    case "right":
      newCol = newCol + 1 >= grid.itemsInRow(newRow) ? 0 : newCol + 1;
      break;
    case "up":
      newRow = newRow - 1 < 0 ? grid.rows - 1 : newRow - 1;
      break;
    case "down":
      newRow = newRow + 1 >= grid.rows ? 0 : newRow + 1;
      break;
    }

    // For vertical movement, clamp column if row has fewer items
    if (direction === "up" || direction === "down") {
      const itemsInNewRow = grid.itemsInRow(newRow);
      newCol = Math.min(newCol, itemsInNewRow - 1);
    }

    const newIndex = newRow * grid.columns + newCol;
    if (newIndex < powerOptions.length) {
      selectedIndex = newIndex;
    }
  }

  function activate() {
    if (powerOptions.length > 0 && selectedIndex >= 0 && powerOptions[selectedIndex]) {
      const option = powerOptions[selectedIndex];
      startTimer(option.action);
    }
  }

  function checkKey(event, settingName) {
    return Keybinds.checkKey(event, settingName, Settings);
  }

  function handleUp() {
    if (largeButtonsStyle) {
      navigateGrid("up");
    } else {
      selectPreviousWrapped();
    }
  }

  function handleDown() {
    if (largeButtonsStyle) {
      navigateGrid("down");
    } else {
      selectNextWrapped();
    }
  }

  function handleLeft() {
    if (largeButtonsStyle) {
      navigateGrid("left");
    } else {
      selectPreviousWrapped();
    }
  }

  function handleRight() {
    if (largeButtonsStyle) {
      navigateGrid("right");
    } else {
      selectNextWrapped();
    }
  }

  function handleEnter() {
    activate();
  }

  function handleEscape() {
    if (timerActive) {
      cancelTimer();
    } else {
      root.close();
    }
  }

  // Override keyboard handlers from SmartPanel
  function onEscapePressed() {
    handleEscape();
  }
  function onTabPressed() {
    selectNextWrapped();
  }
  function onBackTabPressed() {
    selectPreviousWrapped();
  }
  function onLeftPressed() {
    handleLeft();
  }
  function onRightPressed() {
    handleRight();
  }
  function onUpPressed() {
    handleUp();
  }
  function onDownPressed() {
    handleDown();
  }
  function onEnterPressed() {
    handleEnter();
  }
  function onHomePressed() {
    selectFirst();
  }
  function onEndPressed() {
    selectLast();
  }

  function checkKeybind(event) {
    if (powerOptions.length === 0)
      return false;

    // Construct key string in the same format as the recorder
    // Ignore modifier keys by themselves
    if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
      return false;
    }

    const pressedKeybind = Keybinds.getKeybindString(event);
    if (!pressedKeybind)
      return false;

    for (var i = 0; i < powerOptions.length; i++) {
      const option = powerOptions[i];
      if (option.keybind === pressedKeybind) {
        selectedIndex = i;
        startTimer(option.action);
        return true;
      }
    }
    return false;
  }

  // Countdown timer
  Timer {
    id: countdownTimer
    interval: 100
    repeat: true
    onTriggered: {
      timeRemaining -= interval;
      if (timeRemaining <= 0) {
        executeAction(pendingAction);
      }
    }
  }

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"
    focus: true

    width: (largeButtonsStyle || showBlurBackground) ? (root.screen?.width || root.width || 2560) : undefined
    height: (largeButtonsStyle || showBlurBackground) ? (root.screen?.height || root.height || 1440) : undefined

    readonly property var contentPreferredWidth: (largeButtonsStyle || showBlurBackground) ? (root.screen?.width || root.width || 0) : undefined
    readonly property var contentPreferredHeight: (largeButtonsStyle || showBlurBackground) ? (root.screen?.height || root.height || 0) : undefined
    readonly property color blurColor: Color[Settings.data.sessionMenu.blurColor] ?? Color.mSurface

    Rectangle {
      id: blurBackground
      anchors.fill: parent
      anchors.margins: -100
      z: -10
      visible: showBlurBackground

      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: Qt.alpha(blurColor, 0.4)
        }
      }
    }

    // Focus management
    Connections {
      target: root
      function onOpened() {
        Qt.callLater(() => {
                       panelContent.forceActiveFocus();
                     });
      }
    }

    Keys.onPressed: event => {
                      // Check custom entry keybinds first
                      if (root.checkKeybind(event)) {
                        event.accepted = true;
                        return;
                      }

                      // Check global navigation keybinds
                      if (checkKey(event, 'up')) {
                        handleUp();
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'down')) {
                        handleDown();
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'left')) {
                        handleLeft();
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'right')) {
                        handleRight();
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'enter')) {
                        handleEnter();
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'escape')) {
                        handleEscape();
                        event.accepted = true;
                        return;
                      }

                      // Block default keys if they weren't matched above
                      // This prevents 'Up' from working if rebinned to something else
                      if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        return;
                      }
                    }

    HoverHandler {
      id: globalHoverHandler

      onPointChanged: {
        if (!root.mouseTrackingReady) {
          return;
        }

        if (!root.globalMouseInitialized) {
          root.globalLastMouseX = point.position.x;
          root.globalLastMouseY = point.position.y;
          root.globalMouseInitialized = true;
          return;
        }

        const deltaX = Math.abs(point.position.x - root.globalLastMouseX);
        const deltaY = Math.abs(point.position.y - root.globalLastMouseY);
        if (deltaX + deltaY >= 5) {
          root.ignoreMouseHover = false;
          root.globalLastMouseX = point.position.x;
          root.globalLastMouseY = point.position.y;
        }
      }
    }

    // Timer text for large buttons style (above buttons) - positioned absolutely with background
    Rectangle {
      id: timerTextContainer
      visible: largeButtonsStyle && timerActive
      anchors.bottom: largeButtonsContainer.top
      anchors.horizontalCenter: largeButtonsContainer.horizontalCenter
      anchors.bottomMargin: Style.marginM
      width: timerText.width + Style.marginXL * 2
      height: timerText.height + Style.marginL * 2
      radius: Style.radiusM
      color: Qt.alpha(Color.mSurface, Settings.data.ui.panelBackgroundOpacity)
      border.color: Color.mOutline
      border.width: Style.borderS
      z: 1000

      NText {
        id: timerText
        anchors.centerIn: parent
        text: I18n.tr("session-menu.action-in-seconds", {
                        "action": I18n.tr("common." + pendingAction),
                        "seconds": Math.ceil(timeRemaining / 1000)
                      })
        font.weight: Style.fontWeightBold
        pointSize: Style.fontSizeL
        color: Color.mOnSurface
      }
    }

    // Large buttons style layout container
    ColumnLayout {
      id: largeButtonsContainer
      visible: largeButtonsStyle
      anchors.centerIn: parent

      // Large buttons style layout (grid)
      GridLayout {
        id: largeButtonsGrid
        Layout.alignment: Qt.AlignHCenter
        columns: Settings.data.sessionMenu.largeButtonsLayout === "single-row" ? powerOptions.length : Math.min(3, Math.ceil(Math.sqrt(powerOptions.length)))
        rowSpacing: Style.marginXL
        columnSpacing: Style.marginXL
        width: columns * 200 * Style.uiScaleRatio + (columns - 1) * Style.marginXL
        height: Math.ceil(powerOptions.length / columns) * 200 * Style.uiScaleRatio + (Math.ceil(powerOptions.length / columns) - 1) * Style.marginXL

        Repeater {
          model: powerOptions
          delegate: LargeButton {
            Layout.preferredWidth: Math.round(200 * Style.uiScaleRatio)
            Layout.preferredHeight: Math.round(200 * Style.uiScaleRatio)
            icon: modelData.icon
            title: modelData.title
            isShutdown: modelData.isShutdown || false
            isSelected: index === selectedIndex
            number: index + 1
            buttonIndex: index
            onClicked: {
              selectedIndex = index;
              startTimer(modelData.action);
            }
            pending: timerActive && pendingAction === modelData.action
            keybind: modelData.keybind || ""
          }
        }
      }
    }

    // Normal style layout
    NBox {
      visible: !largeButtonsStyle
      anchors.fill: showBlurBackground ? undefined : parent
      anchors.margins: showBlurBackground ? -100 : Style.marginL
      anchors.centerIn: showBlurBackground ? parent : undefined

      // Calculate height for normal style only when background overlay is shown
      readonly property int normalStyleHeight: {
        var headerHeight = Settings.data.sessionMenu.showHeader ? Style.baseWidgetSize * 0.6 : 0;
        var dividerHeight = Settings.data.sessionMenu.showHeader ? Style.marginS : 0;
        var buttonHeight = Style.baseWidgetSize * 1.3 * Style.uiScaleRatio;
        var buttonSpacing = Style.marginS;
        var enabledCount = powerOptions.length;
        var headerSpacing = Settings.data.sessionMenu.showHeader ? (Style.marginL * 2) : 0;
        var baseHeight = (Style.marginL * 4) + headerHeight + dividerHeight + headerSpacing;
        var buttonsHeight = enabledCount > 0 ? (buttonHeight * enabledCount) + (buttonSpacing * (enabledCount - 1)) : 0;
        return Math.round(baseHeight + buttonsHeight);
      }

      width: showBlurBackground ? Math.round(440 * Style.uiScaleRatio) : undefined
      height: showBlurBackground ? normalStyleHeight : undefined

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginL

        // Header with title and close button
        RowLayout {
          visible: Settings.data.sessionMenu.showHeader
          Layout.fillWidth: true
          Layout.preferredHeight: Style.baseWidgetSize * 0.6

          NText {
            text: timerActive ? I18n.tr("session-menu.action-in-seconds", {
                                          "action": I18n.tr("common." + pendingAction),
                                          "seconds": Math.ceil(timeRemaining / 1000)
                                        }) : I18n.tr("session-menu.title")
            font.weight: Style.fontWeightBold
            pointSize: Style.fontSizeL
            color: timerActive ? Color.mPrimary : Color.mOnSurface
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
          }

          Item {
            Layout.fillWidth: true
          }

          NIconButton {
            icon: timerActive ? "stop" : "close"
            tooltipText: timerActive ? I18n.tr("session-menu.cancel-timer") : I18n.tr("common.close")
            Layout.alignment: Qt.AlignVCenter
            baseSize: Style.baseWidgetSize * 0.7
            colorBg: timerActive ? Qt.alpha(Color.mError, 0.08) : "transparent"
            colorFg: timerActive ? Color.mError : Color.mOnSurface
            onClicked: {
              if (timerActive) {
                cancelTimer();
              } else {
                cancelTimer();
                root.close();
              }
            }
          }
        }

        NDivider {
          visible: Settings.data.sessionMenu.showHeader
          Layout.fillWidth: true
        }

        // Power options
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Repeater {
            model: powerOptions
            delegate: PowerButton {
              Layout.fillWidth: true
              icon: modelData.icon
              title: modelData.title
              isShutdown: modelData.isShutdown || false
              isSelected: index === selectedIndex
              number: index + 1
              buttonIndex: index
              onClicked: {
                selectedIndex = index;
                startTimer(modelData.action);
              }
              pending: timerActive && pendingAction === modelData.action
              keybind: modelData.keybind || ""
            }
          }
        }
      }
    }

    // Background MouseArea for large buttons style - closes panel when clicking outside buttons
    MouseArea {
      visible: largeButtonsStyle
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: mouse => {
                   // Only close if not clicking on a button
                   // The buttons are above this MouseArea, so clicks on them won't reach here
                   if (timerActive) {
                     // Cancel countdown if active
                     cancelTimer();
                   } else {
                     root.close();
                   }
                 }
    }
  }

  // Custom power button component
  component PowerButton: Rectangle {
    id: buttonRoot

    property string icon: ""
    property string title: ""
    property bool pending: false
    property bool isShutdown: false
    property bool isSelected: false
    property int number: 0
    property string keybind: ""
    property int buttonIndex: -1

    // Effective hover state that respects ignoreMouseHover
    readonly property bool effectiveHover: !root.ignoreMouseHover && mouseArea.containsMouse

    signal clicked

    height: Style.baseWidgetSize * 1.3 * Style.uiScaleRatio
    radius: Style.radiusS
    color: {
      if (pending) {
        return Qt.alpha(Color.mPrimary, 0.08);
      }
      if (isSelected || effectiveHover) {
        return Color.mHover;
      }
      return "transparent";
    }

    border.width: pending ? Math.max(Style.borderM) : 0
    border.color: pending ? Color.mPrimary : Color.mOutline

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    Item {
      id: contentItem
      anchors.fill: parent
      anchors.margins: Style.marginM

      // Icon on the left
      NIcon {
        id: iconElement
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon: buttonRoot.icon
        color: {
          if (buttonRoot.pending)
            return Color.mPrimary;
          if (buttonRoot.isShutdown && !buttonRoot.isSelected && !buttonRoot.effectiveHover)
            return Color.mError;
          if (buttonRoot.isSelected || buttonRoot.effectiveHover)
            return Color.mOnHover;
          return Color.mOnSurface;
        }
        pointSize: Style.fontSizeXXL
        width: Style.baseWidgetSize * 0.5
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCirc
          }
        }
      }

      // Keybind indicator and countdown text at far right
      Item {
        id: indicatorGroup
        width: (countdownText.visible ? countdownText.width + Style.marginXS : 0) + numberIndicatorRect.width
        height: numberIndicatorRect.height
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        z: 20

        // Countdown as plain text (left of keybind)
        NText {
          id: countdownText
          visible: !Settings.data.sessionMenu.showHeader && buttonRoot.pending && timerActive && pendingAction === modelData.action
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Math.ceil(timeRemaining / 1000)
          pointSize: Style.fontSizeS
          color: Color.mPrimary
          font.weight: Style.fontWeightBold
        }

        // Keybind indicator
        Rectangle {
          id: numberIndicatorRect
          anchors.left: countdownText.visible ? countdownText.right : parent.left
          anchors.leftMargin: countdownText.visible ? Style.marginXS : 0
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.marginXL, labelText.implicitWidth + Style.marginM)
          height: Style.marginXL
          radius: Math.min(Style.radiusM, height / 2)
          color: (buttonRoot.isSelected || buttonRoot.effectiveHover) ? Color.mOnPrimary : Qt.alpha(Color.mSurfaceVariant, 0.5)
          border.width: Style.borderS
          border.color: (buttonRoot.isSelected || buttonRoot.effectiveHover) ? Color.mOnPrimary : Color.mOutline
          visible: Settings.data.sessionMenu.showKeybinds && (buttonRoot.keybind !== "") && !buttonRoot.pending

          NText {
            id: labelText
            anchors.centerIn: parent
            text: buttonRoot.keybind
            pointSize: Style.fontSizeS
            font.weight: Style.fontWeightBold
            color: (buttonRoot.isSelected || buttonRoot.effectiveHover) ? Color.mPrimary : Color.mOnSurface

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
                easing.type: Easing.OutCirc
              }
            }
          }
        }
      }

      // Text content in the middle
      ColumnLayout {
        anchors.left: iconElement.right
        anchors.right: indicatorGroup.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.marginL
        anchors.rightMargin: Style.marginM
        spacing: 0

        NText {
          text: buttonRoot.title
          font.weight: Style.fontWeightMedium
          pointSize: Style.fontSizeM
          color: {
            if (buttonRoot.pending)
              return Color.mPrimary;
            if (buttonRoot.isShutdown && !buttonRoot.isSelected && !buttonRoot.effectiveHover)
              return Color.mError;
            if (buttonRoot.isSelected || buttonRoot.effectiveHover)
              return Color.mOnHover;
            return Color.mOnSurface;
          }

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCirc
            }
          }
        }
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onEntered: {
        if (!root.ignoreMouseHover) {
          selectedIndex = buttonRoot.buttonIndex;
        }
      }

      onExited: {
        if (!root.ignoreMouseHover && selectedIndex === buttonRoot.buttonIndex) {
          selectedIndex = -1;
        }
      }

      onClicked: buttonRoot.clicked()
    }
  }

  // Large buttons style button component
  component LargeButton: Rectangle {
    id: largeButtonRoot

    property string icon: ""
    property string title: ""
    property bool pending: false
    property bool isShutdown: false
    property bool isSelected: false
    property int number: 0
    property string keybind: ""
    property int buttonIndex: -1

    // Effective hover state that respects ignoreMouseHover
    readonly property bool effectiveHover: !root.ignoreMouseHover && mouseArea.containsMouse
    readonly property real hoveredScale: 1.05

    signal clicked

    property real hoverScale: (isSelected || effectiveHover) ? hoveredScale : 1.0

    radius: Style.radiusL
    color: {
      if (pending) {
        return Qt.alpha(Color.mPrimary, 1.0);
      }
      if (isSelected || effectiveHover) {
        return Qt.alpha(Color.mPrimary, 1.0);
      }
      return Qt.alpha(Color.mSurfaceVariant, Settings.data.ui.panelBackgroundOpacity);
    }

    border.width: Style.borderS
    border.color: Color.mOutline

    // Always enable layer to fix nvidia bug, render at 2x size to avoid blur when scaling up
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))

    // Scale transform for hover effect
    transform: Scale {
      origin.x: largeButtonRoot.width / 2
      origin.y: largeButtonRoot.height / 2
      xScale: hoverScale
      yScale: hoverScale
    }

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    Behavior on border.width {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    Behavior on hoverScale {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
        easing.overshoot: 0.5
      }
    }

    ColumnLayout {
      anchors.centerIn: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Large icon with scale animation
      NIcon {
        id: iconElement
        Layout.alignment: Qt.AlignHCenter
        icon: largeButtonRoot.icon
        color: {
          if (largeButtonRoot.pending)
            return Color.mOnPrimary;
          if (largeButtonRoot.isShutdown && !largeButtonRoot.isSelected && !largeButtonRoot.effectiveHover)
            return Color.mError;
          if (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover)
            return Color.mOnPrimary;
          return Color.mOnSurface;
        }
        pointSize: Style.fontSizeXXXL * 2.25
        width: 90 * Style.uiScaleRatio
        height: 90 * Style.uiScaleRatio
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        readonly property real hoveredIconScale: 1.15
        property real iconScale: (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover) ? hoveredIconScale : 1.0

        // Always enable layer to fix nvidia bug, render at 2x size to avoid blur when scaling up
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))

        transform: Scale {
          origin.x: iconElement.width / 2
          origin.y: iconElement.height / 2
          xScale: iconElement.iconScale
          yScale: iconElement.iconScale
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCirc
          }
        }

        Behavior on iconScale {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
            easing.overshoot: 0.6
          }
        }
      }

      // Title text
      NText {
        Layout.alignment: Qt.AlignHCenter
        text: largeButtonRoot.title
        font.weight: Style.fontWeightMedium
        pointSize: Style.fontSizeL
        color: {
          if (largeButtonRoot.pending)
            return Color.mOnPrimary;
          if (largeButtonRoot.isShutdown && !largeButtonRoot.isSelected && !largeButtonRoot.effectiveHover)
            return Color.mError;
          if (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover)
            return Color.mOnPrimary;
          return Color.mOnSurface;
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCirc
          }
        }
      }
    }

    // Keybind/Number indicator in top-right corner
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.marginM
      width: Math.max(Style.fontSizeM * 2, largeNumberText.implicitWidth + Style.marginM)
      height: Style.fontSizeM * 2
      radius: Math.min(Style.radiusM, height / 2)
      color: (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover) ? Color.mOnPrimary : Qt.alpha(Color.mSurfaceVariant, 0.7)
      border.width: Style.borderS
      border.color: (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover) ? Color.mOnPrimary : Color.mOutline
      visible: Settings.data.sessionMenu.showKeybinds && (largeButtonRoot.keybind !== "") && !largeButtonRoot.pending
      z: 10

      NText {
        id: largeNumberText
        anchors.centerIn: parent
        text: largeButtonRoot.keybind
        pointSize: Style.fontSizeM
        font.weight: Style.fontWeightBold
        color: {
          if (largeButtonRoot.isSelected || largeButtonRoot.effectiveHover)
            return Color.mPrimary;
          return Color.mOnSurface;
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCirc
          }
        }
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onEntered: {
        if (!root.ignoreMouseHover) {
          selectedIndex = largeButtonRoot.buttonIndex;
        }
      }

      onExited: {
        if (!root.ignoreMouseHover && selectedIndex === largeButtonRoot.buttonIndex) {
          selectedIndex = -1;
        }
      }

      onClicked: largeButtonRoot.clicked()
    }
  }
}

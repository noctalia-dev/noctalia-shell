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

  // Make panel background transparent for large buttons style
  panelBackgroundColor: largeButtonsStyle ? Color.transparent : Color.mSurface

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

  // Action metadata mapping
  readonly property var actionMetadata: {
    "lock": {
      "icon": "lock",
      "title": I18n.tr("session-menu.lock"),
      "isShutdown": false
    },
    "suspend": {
      "icon": "suspend",
      "title": I18n.tr("session-menu.suspend"),
      "isShutdown": false
    },
    "hibernate": {
      "icon": "hibernate",
      "title": I18n.tr("session-menu.hibernate"),
      "isShutdown": false
    },
    "reboot": {
      "icon": "reboot",
      "title": I18n.tr("session-menu.reboot"),
      "isShutdown": false
    },
    "logout": {
      "icon": "logout",
      "title": I18n.tr("session-menu.logout"),
      "isShutdown": false
    },
    "shutdown": {
      "icon": "shutdown",
      "title": I18n.tr("session-menu.shutdown"),
      "isShutdown": true
    }
  }

  // Build powerOptions from settings, filtering enabled ones and adding metadata
  property var powerOptions: {
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
                       "command": settingOption.command || ""
                     });
      }
    }

    return options;
  }

  // Update powerOptions when settings change
  Connections {
    target: Settings.data.sessionMenu
    function onPowerOptionsChanged() {
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
                         "command": settingOption.command || ""
                       });
        }
      }

      root.powerOptions = options;
    }
  }

  // Lifecycle handlers
  onOpened: {
    selectedIndex = -1;
  }

  onClosed: {
    cancelTimer();
    selectedIndex = -1;
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

    // Find the option to check for custom command
    var option = null;
    for (var i = 0; i < powerOptions.length; i++) {
      if (powerOptions[i].action === action) {
        option = powerOptions[i];
        break;
      }
    }

    // If custom command is defined, execute it
    if (option && option.command && option.command.trim() !== "") {
      Logger.i("SessionMenu", "Executing custom command for action:", action, "Command:", option.command);
      Quickshell.execDetached(["sh", "-c", option.command]);
      cancelTimer();
      root.close();
      return;
    }

    // Otherwise, use default behavior
    switch (action) {
    case "lock":
      // Access lockScreen via PanelService
      if (PanelService.lockScreen && !PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true;
      }
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
    const columns = Math.min(3, Math.ceil(Math.sqrt(powerOptions.length)));
    const rows = Math.ceil(powerOptions.length / columns);
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

  // Override keyboard handlers from SmartPanel
  function onEscapePressed() {
    if (timerActive) {
      cancelTimer();
    } else {
      root.close();
    }
  }

  function onTabPressed() {
    selectNextWrapped();
  }

  function onBackTabPressed() {
    selectPreviousWrapped();
  }

  function onLeftPressed() {
    if (largeButtonsStyle) {
      navigateGrid("left");
    } else {
      selectPreviousWrapped();
    }
  }

  function onRightPressed() {
    if (largeButtonsStyle) {
      navigateGrid("right");
    } else {
      selectNextWrapped();
    }
  }

  function onUpPressed() {
    if (largeButtonsStyle) {
      navigateGrid("up");
    } else {
      selectPreviousWrapped();
    }
  }

  function onDownPressed() {
    if (largeButtonsStyle) {
      navigateGrid("down");
    } else {
      selectNextWrapped();
    }
  }

  function onReturnPressed() {
    activate();
  }

  function onHomePressed() {
    selectFirst();
  }

  function onEndPressed() {
    selectLast();
  }

  function onCtrlJPressed() {
    selectNextWrapped();
  }

  function onCtrlKPressed() {
    selectPreviousWrapped();
  }

  function onNumberPressed(number) {
    if (!Settings.data.sessionMenu.showNumberLabels) {
      return;
    }
    // Number is 1-based, convert to 0-based index
    const index = number - 1;
    if (index >= 0 && index < powerOptions.length) {
      const option = powerOptions[index];
      selectedIndex = index;
      startTimer(option.action);
    }
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
    id: ui
    color: Color.transparent
    focus: true

    // For large buttons style, use full screen dimensions
    readonly property var contentPreferredWidth: largeButtonsStyle ? (root.screen?.width || root.width || 0) : undefined
    readonly property var contentPreferredHeight: largeButtonsStyle ? (root.screen?.height || root.height || 0) : undefined

    // Focus management
    Connections {
      target: root
      function onOpened() {
        Qt.callLater(() => {
                       ui.forceActiveFocus();
                     });
      }
    }

    // Navigation functions
    function selectFirst() {
      root.selectFirst();
    }

    function selectLast() {
      root.selectLast();
    }

    function selectNextWrapped() {
      root.selectNextWrapped();
    }

    function selectPreviousWrapped() {
      root.selectPreviousWrapped();
    }

    function activate() {
      root.activate();
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
                        "action": I18n.tr("session-menu." + pendingAction),
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
        columns: Math.min(3, Math.ceil(Math.sqrt(powerOptions.length)))
        rowSpacing: Style.marginXL
        columnSpacing: Style.marginXL
        width: columns * 200 * Style.uiScaleRatio + (columns - 1) * Style.marginXL
        height: Math.ceil(powerOptions.length / columns) * 200 * Style.uiScaleRatio + (Math.ceil(powerOptions.length / columns) - 1) * Style.marginXL

        Repeater {
          model: powerOptions
          delegate: LargeButton {
            Layout.preferredWidth: 200 * Style.uiScaleRatio
            Layout.preferredHeight: 200 * Style.uiScaleRatio
            icon: modelData.icon
            title: modelData.title
            isShutdown: modelData.isShutdown || false
            isSelected: index === selectedIndex
            number: index + 1
            onClicked: {
              selectedIndex = index;
              startTimer(modelData.action);
            }
            pending: timerActive && pendingAction === modelData.action
          }
        }
      }
    }

    // Normal style layout
    NBox {
      visible: !largeButtonsStyle
      anchors.fill: parent
      anchors.margins: Style.marginL

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
                                          "action": I18n.tr("session-menu." + pendingAction),
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
            tooltipText: timerActive ? I18n.tr("tooltips.cancel-timer") : I18n.tr("tooltips.close")
            Layout.alignment: Qt.AlignVCenter
            baseSize: Style.baseWidgetSize * 0.7
            colorBg: timerActive ? Qt.alpha(Color.mError, 0.08) : Color.transparent
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
              onClicked: {
                selectedIndex = index;
                startTimer(modelData.action);
              }
              pending: timerActive && pendingAction === modelData.action
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

    signal clicked

    height: Style.baseWidgetSize * 1.3 * Style.uiScaleRatio
    radius: Style.radiusS
    color: {
      if (pending) {
        return Qt.alpha(Color.mPrimary, 0.08);
      }
      if (isSelected || mouseArea.containsMouse) {
        return Color.mHover;
      }
      return Color.transparent;
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
          if (buttonRoot.isShutdown && !buttonRoot.isSelected && !mouseArea.containsMouse)
            return Color.mError;
          if (buttonRoot.isSelected || mouseArea.containsMouse)
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

      // Text content in the middle
      ColumnLayout {
        anchors.left: iconElement.right
        anchors.right: numberIndicator.visible ? numberIndicator.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.marginL
        anchors.rightMargin: numberIndicator.visible ? Style.marginM : 0
        spacing: 0

        NText {
          text: buttonRoot.title
          font.weight: Style.fontWeightMedium
          pointSize: Style.fontSizeM
          color: {
            if (buttonRoot.pending)
              return Color.mPrimary;
            if (buttonRoot.isShutdown && !buttonRoot.isSelected && !mouseArea.containsMouse)
              return Color.mError;
            if (buttonRoot.isSelected || mouseArea.containsMouse)
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

      // Number indicator on the right (when not pending)
      Rectangle {
        id: numberIndicator
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.marginM * 2
        height: width
        radius: Math.min(Style.radiusM, height / 2)
        color: Qt.alpha(Color.mSurfaceVariant, 0.5)
        border.width: Style.borderS
        border.color: Color.mOutline
        visible: Settings.data.sessionMenu.showNumberLabels && buttonRoot.number > 0 && !buttonRoot.pending

        NText {
          id: numberText
          anchors.centerIn: parent
          text: buttonRoot.number
          pointSize: Style.fontSizeS
          color: {
            if (buttonRoot.isSelected || mouseArea.containsMouse)
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

    signal clicked

    property real hoverScale: (isSelected || mouseArea.containsMouse) ? 1.05 : 1.0

    radius: Style.radiusL
    color: {
      if (pending) {
        return Qt.alpha(Color.mPrimary, 1.0);
      }
      if (isSelected || mouseArea.containsMouse) {
        return Qt.alpha(Color.mPrimary, 1.0);
      }
      return Qt.alpha(Color.mSurfaceVariant, Settings.data.ui.panelBackgroundOpacity);
    }

    border.width: Style.borderS
    border.color: Color.mOutline

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
          if (largeButtonRoot.isShutdown && !largeButtonRoot.isSelected && !mouseArea.containsMouse)
            return Color.mError;
          if (largeButtonRoot.isSelected || mouseArea.containsMouse)
            return Color.mOnPrimary;
          return Color.mOnSurface;
        }
        pointSize: Style.fontSizeXXXL * 2
        width: 80 * Style.uiScaleRatio
        height: 80 * Style.uiScaleRatio
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        property real iconScale: (largeButtonRoot.isSelected || mouseArea.containsMouse) ? 1.1 : 1.0

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
          if (largeButtonRoot.isShutdown && !largeButtonRoot.isSelected && !mouseArea.containsMouse)
            return Color.mError;
          if (largeButtonRoot.isSelected || mouseArea.containsMouse)
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

    // Number indicator in top-right corner
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.marginM
      width: Style.fontSizeM * 2
      height: width
      radius: Math.min(Style.radiusM, height / 2)
      color: Qt.alpha(Color.mSurfaceVariant, 0.7)
      border.width: Style.borderS
      border.color: Color.mOutline
      visible: Settings.data.sessionMenu.showNumberLabels && largeButtonRoot.number > 0 && !largeButtonRoot.pending
      z: 10

      NText {
        id: largeNumberText
        anchors.centerIn: parent
        text: largeButtonRoot.number
        pointSize: Style.fontSizeM
        color: {
          if (largeButtonRoot.isSelected || mouseArea.containsMouse)
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

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onClicked: largeButtonRoot.clicked()
    }
  }
}

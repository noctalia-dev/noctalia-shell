import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.System
import qs.Widgets

// Notification History panel
SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(540 * Style.uiScaleRatio)
  property var contentItem: null

  onOpened: {
    NotificationService.updateLastSeenTs();
    Qt.callLater(() => {
                   if (!root.contentItem)
                     return;
                   root.contentItem.forceActiveFocus();
                   root.contentItem.ensureKeyboardSelection();
                 });
  }

  function onUpPressed() {
    if (root.contentItem)
      root.contentItem.selectRelative(-1);
  }

  function onDownPressed() {
    if (root.contentItem)
      root.contentItem.selectRelative(1);
  }

  function onEnterPressed() {
    if (root.contentItem)
      root.contentItem.toggleSelectedExpand();
  }

  function onLeftPressed() {
    if (root.contentItem)
      root.contentItem.selectPreviousRange();
  }

  function onRightPressed() {
    if (root.contentItem)
      root.contentItem.selectNextRange();
  }

  function onHomePressed() {
    if (root.contentItem)
      root.contentItem.selectBoundary(false);
  }

  function onEndPressed() {
    if (root.contentItem)
      root.contentItem.selectBoundary(true);
  }

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"
    focus: true

    // Calculate content height based on header + tabs (if visible) + content
    property real calculatedHeight: {
      if (NotificationService.historyList.count === 0) {
        return headerBox.implicitHeight + scrollView.implicitHeight + (Style.marginL * 2) + Style.marginM;
      }
      return headerBox.implicitHeight + scrollView.implicitHeight + (Style.marginL * 2) + Style.marginM;
    }
    property real contentPreferredHeight: Math.min(root.preferredHeight, Math.ceil(calculatedHeight))

    // State (lazy-loaded with panelContent)
    property var rangeCounts: [0, 0, 0, 0]
    property var lastKnownDate: null  // Track the current date to detect day changes

    // UI state (lazy-loaded with panelContent)
    // 0 = All, 1 = Today, 2 = Yesterday, 3 = Earlier
    property int currentRange: 1  // start on Today by default
    property bool groupByDate: true
    property string keyboardSelectedId: ""

    function isDelegateNavigable(delegateItem) {
      return delegateItem && delegateItem.visible && !delegateItem.isRemoving && delegateItem.height > 0;
    }

    function visibleDelegates() {
      var delegates = [];
      if (!notificationRepeater)
        return delegates;
      for (var i = 0; i < notificationRepeater.count; ++i) {
        var item = notificationRepeater.itemAt(i);
        if (isDelegateNavigable(item))
          delegates.push(item);
      }
      return delegates;
    }

    function ensureDelegateVisible(delegateItem) {
      if (!delegateItem || !scrollView || !scrollView.contentItem)
        return;

      var flickable = scrollView.contentItem;
      var topY = delegateItem.y;
      var bottomY = topY + delegateItem.height;
      var viewportTop = flickable.contentY;
      var viewportBottom = viewportTop + flickable.height;
      var targetY = flickable.contentY;

      if (topY < viewportTop) {
        targetY = topY;
      } else if (bottomY > viewportBottom) {
        targetY = bottomY - flickable.height;
      }

      var maxY = Math.max(0, flickable.contentHeight - flickable.height);
      flickable.contentY = Math.max(0, Math.min(targetY, maxY));
    }

    function ensureKeyboardSelection() {
      var delegates = visibleDelegates();
      if (delegates.length === 0) {
        keyboardSelectedId = "";
        return false;
      }

      if (keyboardSelectedId !== "") {
        for (var i = 0; i < delegates.length; ++i) {
          if (delegates[i].notificationId === keyboardSelectedId) {
            ensureDelegateVisible(delegates[i]);
            return true;
          }
        }
      }

      keyboardSelectedId = delegates[0].notificationId;
      ensureDelegateVisible(delegates[0]);
      return true;
    }

    function selectRelative(delta) {
      var delegates = visibleDelegates();
      if (delegates.length === 0) {
        keyboardSelectedId = "";
        return false;
      }

      var currentIndex = -1;
      for (var i = 0; i < delegates.length; ++i) {
        if (delegates[i].notificationId === keyboardSelectedId) {
          currentIndex = i;
          break;
        }
      }

      if (currentIndex < 0)
        currentIndex = delta > 0 ? -1 : delegates.length;

      var nextIndex = Math.max(0, Math.min(delegates.length - 1, currentIndex + delta));
      keyboardSelectedId = delegates[nextIndex].notificationId;
      ensureDelegateVisible(delegates[nextIndex]);
      return true;
    }

    function selectBoundary(toEnd) {
      var delegates = visibleDelegates();
      if (delegates.length === 0) {
        keyboardSelectedId = "";
        return false;
      }

      var index = toEnd ? delegates.length - 1 : 0;
      keyboardSelectedId = delegates[index].notificationId;
      ensureDelegateVisible(delegates[index]);
      return true;
    }

    function selectedDelegate() {
      if (!notificationRepeater || keyboardSelectedId === "")
        return null;
      for (var i = 0; i < notificationRepeater.count; ++i) {
        var item = notificationRepeater.itemAt(i);
        if (item && item.notificationId === keyboardSelectedId)
          return item;
      }
      return null;
    }

    function toggleSelectedExpand() {
      if (!ensureKeyboardSelection())
        return false;

      var delegateItem = selectedDelegate();
      if (!delegateItem || !delegateItem.canExpand)
        return false;

      if (scrollView.expandedId === delegateItem.notificationId) {
        scrollView.expandedId = "";
      } else {
        scrollView.expandedId = delegateItem.notificationId;
      }

      ensureDelegateVisible(delegateItem);
      return true;
    }

    function dismissSelectedNotification() {
      if (!ensureKeyboardSelection())
        return false;

      var delegateItem = selectedDelegate();
      if (!delegateItem || delegateItem.isRemoving)
        return false;

      delegateItem.swipeOffset = 1;
      delegateItem.dismissBySwipe();
      return true;
    }

    function selectNextRange() {
      if (!groupByDate || !tabsBox.visible)
        return false;
      currentRange = Math.min(3, currentRange + 1);
      Qt.callLater(() => ensureKeyboardSelection());
      return true;
    }

    function selectPreviousRange() {
      if (!groupByDate || !tabsBox.visible)
        return false;
      currentRange = Math.max(0, currentRange - 1);
      Qt.callLater(() => ensureKeyboardSelection());
      return true;
    }

    // Helper functions (lazy-loaded with panelContent)
    function dateOnly(d) {
      return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function getDateKey(d) {
      // Returns a string key for the date (YYYY-MM-DD) for comparison
      var date = dateOnly(d);
      return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
    }

    function rangeForTimestamp(ts) {
      var dt = new Date(ts);
      var today = dateOnly(new Date());
      var thatDay = dateOnly(dt);

      var diffMs = today - thatDay;
      var diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

      if (diffDays === 0)
        return 0;
      if (diffDays === 1)
        return 1;
      return 2;
    }

    function recalcRangeCounts() {
      var m = NotificationService.historyList;
      if (!m || typeof m.count === "undefined" || m.count <= 0) {
        panelContent.rangeCounts = [0, 0, 0, 0];
        return;
      }

      var counts = [0, 0, 0, 0];

      counts[0] = m.count;

      for (var i = 0; i < m.count; ++i) {
        var item = m.get(i);
        if (!item || typeof item.timestamp === "undefined")
          continue;
        var r = rangeForTimestamp(item.timestamp);
        counts[r + 1] = counts[r + 1] + 1;
      }

      panelContent.rangeCounts = counts;
    }

    function isInCurrentRange(ts) {
      if (currentRange === 0)
        return true;
      return rangeForTimestamp(ts) === (currentRange - 1);
    }

    function countForRange(range) {
      return rangeCounts[range] || 0;
    }

    function hasNotificationsInCurrentRange() {
      var m = NotificationService.historyList;
      if (!m || m.count === 0) {
        return false;
      }
      for (var i = 0; i < m.count; ++i) {
        var item = m.get(i);
        if (item && isInCurrentRange(item.timestamp))
          return true;
      }
      return false;
    }

    Component.onCompleted: {
      root.contentItem = panelContent;
      recalcRangeCounts();
      // Initialize lastKnownDate
      lastKnownDate = getDateKey(new Date());
      Qt.callLater(() => ensureKeyboardSelection());
    }

    onCurrentRangeChanged: Qt.callLater(() => ensureKeyboardSelection())

    Connections {
      target: NotificationService.historyList
      function onCountChanged() {
        panelContent.recalcRangeCounts();
        Qt.callLater(() => panelContent.ensureKeyboardSelection());
      }
    }

    Keys.onPressed: event => {
                      const vimNavigationEnabled = Settings.data.notifications?.vimKeyboardNavigation === true;
                      const hasBlockingModifier = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0;
                      if (vimNavigationEnabled && !hasBlockingModifier && event.text && event.text.length === 1) {
                        const vimKey = event.text;
                        const vimKeyLower = vimKey.toLowerCase();
                        if (vimKeyLower === "j") {
                          panelContent.selectRelative(1);
                          event.accepted = true;
                          return;
                        }
                        if (vimKeyLower === "k") {
                          panelContent.selectRelative(-1);
                          event.accepted = true;
                          return;
                        }
                        if (vimKeyLower === "h") {
                          panelContent.selectPreviousRange();
                          event.accepted = true;
                          return;
                        }
                        if (vimKeyLower === "l") {
                          panelContent.selectNextRange();
                          event.accepted = true;
                          return;
                        }
                        if (vimKey === "g") {
                          panelContent.selectBoundary(false);
                          event.accepted = true;
                          return;
                        }
                        if (vimKey === "G") {
                          panelContent.selectBoundary(true);
                          event.accepted = true;
                          return;
                        }
                      }

                      if (event.key === Qt.Key_Up) {
                        panelContent.selectRelative(-1);
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Down) {
                        panelContent.selectRelative(1);
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Left) {
                        panelContent.selectPreviousRange();
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Right) {
                        panelContent.selectNextRange();
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Home) {
                        panelContent.selectBoundary(false);
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_End) {
                        panelContent.selectBoundary(true);
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        panelContent.toggleSelectedExpand();
                        event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        if (panelContent.dismissSelectedNotification())
                          event.accepted = true;
                        return;
                      }
                      if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                      }
                    }

    // Timer to check for day changes at midnight
    Timer {
      id: dayChangeTimer
      interval: 60000  // Check every minute
      repeat: true
      running: true  // Always runs when panelContent exists (panel is open)
      onTriggered: {
        var currentDateKey = panelContent.getDateKey(new Date());
        if (panelContent.lastKnownDate !== null && panelContent.lastKnownDate !== currentDateKey) {
          // Day has changed, recalculate counts
          panelContent.recalcRangeCounts();
        }
        panelContent.lastKnownDate = currentDateKey;
      }
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header section
      NBox {
        id: headerBox
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + Style.marginXL

        ColumnLayout {
          id: header
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          RowLayout {
            id: headerRow
            NIcon {
              icon: "bell"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("common.notifications")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
              tooltipText: NotificationService.doNotDisturb ? I18n.tr("tooltips.do-not-disturb-enabled") : I18n.tr("tooltips.do-not-disturb-enabled")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
            }

            NIconButton {
              icon: "trash"
              tooltipText: I18n.tr("actions.clear-history")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                NotificationService.clearHistory();
                // Close panel as there is nothing more to see.
                root.close();
              }
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }

          // Time range tabs ([All] / [Today] / [Yesterday] / [Earlier])
          NTabBar {
            id: tabsBox
            Layout.fillWidth: true
            visible: NotificationService.historyList.count > 0 && panelContent.groupByDate
            currentIndex: panelContent.currentRange
            tabHeight: Style.toOdd(Style.baseWidgetSize * 0.8)
            spacing: Style.marginXS
            distributeEvenly: true

            NTabButton {
              tabIndex: 0
              text: I18n.tr("launcher.categories.all") + " (" + panelContent.countForRange(0) + ")"
              checked: tabsBox.currentIndex === 0
              onClicked: panelContent.currentRange = 0
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 1
              text: I18n.tr("notifications.range.today") + " (" + panelContent.countForRange(1) + ")"
              checked: tabsBox.currentIndex === 1
              onClicked: panelContent.currentRange = 1
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 2
              text: I18n.tr("notifications.range.yesterday") + " (" + panelContent.countForRange(2) + ")"
              checked: tabsBox.currentIndex === 2
              onClicked: panelContent.currentRange = 2
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 3
              text: I18n.tr("notifications.range.earlier") + " (" + panelContent.countForRange(3) + ")"
              checked: tabsBox.currentIndex === 3
              onClicked: panelContent.currentRange = 3
              pointSize: Style.fontSizeXS
            }
          }
        }
      }

      // Notification list container with gradient overlay
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NScrollView {
          id: scrollView
          anchors.fill: parent
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          reserveScrollbarSpace: false
          gradientColor: Color.mSurface

          // Track which notification is expanded
          property string expandedId: ""

          ColumnLayout {
            width: scrollView.availableWidth
            spacing: Style.marginM

            // Empty state when no notifications
            NBox {
              visible: !panelContent.hasNotificationsInCurrentRange()
              Layout.fillWidth: true
              Layout.preferredHeight: emptyState.implicitHeight + Style.marginXL

              ColumnLayout {
                id: emptyState
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginL

                Item {
                  Layout.fillHeight: true
                }

                NIcon {
                  icon: "bell-off"
                  pointSize: (NotificationService.historyList.count === 0) ? 48 : Style.baseWidgetSize
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: I18n.tr("notifications.panel.no-notifications")
                  pointSize: (NotificationService.historyList.count === 0) ? Style.fontSizeL : Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  visible: NotificationService.historyList.count === 0
                  text: I18n.tr("notifications.panel.description")
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  horizontalAlignment: Text.AlignHCenter
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }

                Item {
                  Layout.fillHeight: true
                }
              }
            }

            // Notification list container
            Item {
              visible: panelContent.hasNotificationsInCurrentRange()
              Layout.fillWidth: true
              Layout.preferredHeight: notificationColumn.implicitHeight

              Column {
                id: notificationColumn
                width: scrollView.width
                spacing: Style.marginM

                Repeater {
                  id: notificationRepeater
                  model: NotificationService.historyList

                  delegate: Item {
                    id: notificationDelegate
                    width: parent.width
                    visible: panelContent.isInCurrentRange(model.timestamp)
                    height: visible && !isRemoving ? contentColumn.height + Style.marginXL : 0

                    property string notificationId: model.id
                    property bool isExpanded: scrollView.expandedId === notificationId
                    property bool canExpand: summaryText.truncated || bodyText.truncated
                    property bool isKeyboardSelected: panelContent.keyboardSelectedId === notificationId
                    property real swipeOffset: 0
                    property real pressGlobalX: 0
                    property real pressGlobalY: 0
                    property bool isSwiping: false
                    property bool suppressClick: false
                    property bool isRemoving: false
                    readonly property real swipeStartThreshold: Math.round(16 * Style.uiScaleRatio)
                    readonly property real swipeDismissThreshold: Math.max(110, width * 0.3)
                    readonly property int removeAnimationDuration: Style.animationNormal

                    transform: Translate {
                      x: notificationDelegate.swipeOffset
                    }

                    function dismissBySwipe() {
                      if (isRemoving)
                        return;
                      isRemoving = true;
                      isSwiping = false;
                      suppressClick = true;

                      if (Settings.data.general.animationDisabled) {
                        NotificationService.removeFromHistory(notificationId);
                        return;
                      }

                      swipeOffset = swipeOffset >= 0 ? width + Style.marginL : -width - Style.marginL;
                      opacity = 0;
                      removeTimer.restart();
                    }

                    Timer {
                      id: removeTimer
                      interval: notificationDelegate.removeAnimationDuration
                      repeat: false
                      onTriggered: NotificationService.removeFromHistory(notificationId)
                    }

                    Behavior on swipeOffset {
                      enabled: !Settings.data.general.animationDisabled && !notificationDelegate.isSwiping
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on opacity {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on height {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on y {
                      enabled: !Settings.data.general.animationDisabled
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    // Parse actions safely
                    property var actionsList: {
                      try {
                        return JSON.parse(model.actionsJson || "[]");
                      } catch (e) {
                        return [];
                      }
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.radiusM
                      color: notificationDelegate.isKeyboardSelected ? Qt.alpha(Color.mPrimary, Style.opacityLight) : Color.mSurfaceVariant
                      border.color: notificationDelegate.isKeyboardSelected ? Qt.alpha(Color.mPrimary, Style.opacityHeavy) : (Settings.data.ui.boxBorderEnabled ? Qt.alpha(Color.mOutline, Style.opacityHeavy) : "transparent")
                      border.width: Style.borderS

                      Behavior on color {
                        enabled: !Settings.data.general.animationDisabled
                        ColorAnimation {
                          duration: Style.animationFast
                        }
                      }
                    }

                    // Click to expand/collapse
                    MouseArea {
                      id: historyInteractionArea
                      anchors.fill: parent
                      anchors.rightMargin: Style.baseWidgetSize
                      enabled: !notificationDelegate.isRemoving
                      cursorShape: notificationDelegate.canExpand ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onPressed: mouse => {
                                   if (mouse.button !== Qt.LeftButton)
                                     return;
                                   panelContent.keyboardSelectedId = notificationId;
                                   panelContent.ensureDelegateVisible(notificationDelegate);
                                   const globalPoint = historyInteractionArea.mapToGlobal(mouse.x, mouse.y);
                                   notificationDelegate.pressGlobalX = globalPoint.x;
                                   notificationDelegate.pressGlobalY = globalPoint.y;
                                   notificationDelegate.isSwiping = false;
                                   notificationDelegate.suppressClick = false;
                                 }
                      onPositionChanged: mouse => {
                                           if (!(mouse.buttons & Qt.LeftButton) || notificationDelegate.isRemoving)
                                             return;

                                           const globalPoint = historyInteractionArea.mapToGlobal(mouse.x, mouse.y);
                                           const deltaX = globalPoint.x - notificationDelegate.pressGlobalX;
                                           const deltaY = globalPoint.y - notificationDelegate.pressGlobalY;

                                           if (!notificationDelegate.isSwiping) {
                                             if (Math.abs(deltaX) < notificationDelegate.swipeStartThreshold)
                                               return;

                                             // Only start a swipe-dismiss when horizontal movement is dominant.
                                             if (Math.abs(deltaX) <= Math.abs(deltaY) * 1.15) {
                                               notificationDelegate.suppressClick = true;
                                               return;
                                             }
                                             notificationDelegate.isSwiping = true;
                                           }

                                           notificationDelegate.swipeOffset = deltaX;
                                         }
                      onReleased: mouse => {
                                    if (mouse.button !== Qt.LeftButton)
                                      return;

                                    if (notificationDelegate.isSwiping) {
                                      if (Math.abs(notificationDelegate.swipeOffset) >= notificationDelegate.swipeDismissThreshold) {
                                        notificationDelegate.dismissBySwipe();
                                      } else {
                                        notificationDelegate.swipeOffset = 0;
                                      }
                                      notificationDelegate.suppressClick = true;
                                      notificationDelegate.isSwiping = false;
                                      return;
                                    }

                                    if (!notificationDelegate.canExpand || notificationDelegate.suppressClick)
                                      return;

                                    if (scrollView.expandedId === notificationId) {
                                      scrollView.expandedId = "";
                                    } else {
                                      scrollView.expandedId = notificationId;
                                    }
                                  }
                      onCanceled: {
                        notificationDelegate.isSwiping = false;
                        notificationDelegate.swipeOffset = 0;
                        notificationDelegate.suppressClick = true;
                      }
                    }

                    onVisibleChanged: {
                      if (!visible) {
                        notificationDelegate.isSwiping = false;
                        notificationDelegate.suppressClick = false;
                        notificationDelegate.swipeOffset = 0;
                        notificationDelegate.opacity = 1;
                        notificationDelegate.isRemoving = false;
                        removeTimer.stop();
                      }
                    }

                    Component.onDestruction: removeTimer.stop()

                    Column {
                      id: contentColumn
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.marginM
                      spacing: Style.marginM

                      Row {
                        width: parent.width
                        spacing: Style.marginM

                        // Icon
                        NImageRounded {
                          anchors.verticalCenter: parent.verticalCenter
                          width: Math.round(40 * Style.uiScaleRatio)
                          height: Math.round(40 * Style.uiScaleRatio)
                          radius: Math.min(Style.radiusL, width / 2)
                          imagePath: model.cachedImage || model.originalImage || ""
                          borderColor: "transparent"
                          borderWidth: 0
                          fallbackIcon: "bell"
                          fallbackIconSize: 24
                        }

                        // Content
                        Column {
                          width: parent.width - Math.round(40 * Style.uiScaleRatio) - Style.marginM - Style.baseWidgetSize
                          spacing: Style.marginXS

                          // Header row with app name and timestamp
                          Row {
                            width: parent.width
                            spacing: Style.marginS

                            // Urgency indicator
                            Rectangle {
                              width: 6
                              height: 6
                              anchors.verticalCenter: parent.verticalCenter
                              radius: 3
                              visible: model.urgency !== 1
                              color: {
                                if (model.urgency === 2)
                                  return Color.mError;
                                else if (model.urgency === 0)
                                  return Color.mOnSurfaceVariant;
                                else
                                  return "transparent";
                              }
                            }

                            NText {
                              text: model.appName || "Unknown App"
                              pointSize: Style.fontSizeXS
                              font.weight: Style.fontWeightBold
                              color: Color.mSecondary
                            }

                            NText {
                              textFormat: Text.PlainText
                              text: " " + Time.formatRelativeTime(model.timestamp)
                              pointSize: Style.fontSizeXXS
                              color: Color.mOnSurfaceVariant
                              anchors.bottom: parent.bottom
                            }
                          }

                          // Summary
                          NText {
                            id: summaryText
                            width: parent.width
                            text: model.summary || I18n.tr("common.no-summary")
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: notificationDelegate.isExpanded ? 999 : 2
                            elide: Text.ElideRight
                          }

                          // Body
                          NText {
                            id: bodyText
                            width: parent.width
                            text: model.body || ""
                            pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: notificationDelegate.isExpanded ? 999 : 3
                            elide: Text.ElideRight
                            visible: text.length > 0
                          }

                          // Expand indicator
                          Row {
                            width: parent.width
                            visible: !notificationDelegate.isExpanded && notificationDelegate.canExpand
                            spacing: Style.marginXS

                            Item {
                              width: parent.width - expandText.width - expandIcon.width - Style.marginXS
                              height: 1
                            }

                            NText {
                              id: expandText
                              text: I18n.tr("notifications.panel.click-to-expand") || "Click to expand"
                              pointSize: Style.fontSizeXS
                              color: Color.mPrimary
                            }

                            NIcon {
                              id: expandIcon
                              icon: "chevron-down"
                              pointSize: Style.fontSizeS
                              color: Color.mPrimary
                            }
                          }

                          // Actions Flow
                          Flow {
                            width: parent.width
                            spacing: Style.marginS
                            visible: notificationDelegate.actionsList.length > 0

                            Repeater {
                              model: notificationDelegate.actionsList
                              delegate: NButton {
                                text: modelData.text
                                fontSize: Style.fontSizeS
                                backgroundColor: Color.mPrimary
                                textColor: Color.mOnPrimary
                                outlined: false
                                implicitHeight: 24

                                // Capture modelData in a property to avoid reference errors
                                property var actionData: modelData
                                onClicked: {
                                  NotificationService.invokeAction(notificationDelegate.notificationId, actionData.identifier);
                                }
                              }
                            }
                          }
                        }

                        // Delete button
                        NIconButton {
                          icon: "trash"
                          tooltipText: I18n.tr("tooltips.delete-notification")
                          baseSize: Style.baseWidgetSize * 0.7
                          anchors.verticalCenter: parent.verticalCenter

                          onClicked: {
                            NotificationService.removeFromHistory(notificationId);
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

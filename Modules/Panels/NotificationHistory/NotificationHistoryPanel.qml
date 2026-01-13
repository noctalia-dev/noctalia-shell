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

  onOpened: {
    NotificationService.updateLastSeenTs();
  }

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"

    // Calculate content height based on header + tabs (if visible) + content
    property real calculatedHeight: {
      if (NotificationService.historyList.count === 0) {
        return headerBox.implicitHeight + scrollView.implicitHeight + (Style.marginL * 2) + Style.marginM;
      }
      return headerBox.implicitHeight + tabsBox.implicitHeight + scrollView.implicitHeight + (Style.marginL * 2) + (Style.marginM * 2);
    }
    property real contentPreferredHeight: Math.min(root.preferredHeight, Math.ceil(calculatedHeight))

    // State (lazy-loaded with panelContent)
    property var rangeCounts: [0, 0, 0, 0]
    property var lastKnownDate: null  // Track the current date to detect day changes

    // UI state (lazy-loaded with panelContent)
    // 0 = All, 1 = Today, 2 = Yesterday, 3 = Earlier
    property int currentRange: 1  // start on Today by default
    property bool groupByDate: true

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
      recalcRangeCounts();
      // Initialize lastKnownDate
      lastKnownDate = getDateKey(new Date());
    }

    Connections {
      target: NotificationService.historyList
      function onCountChanged() {
        panelContent.recalcRangeCounts();
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
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

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
      }

      // Time range tabs ([All] / [Today] / [Yesterday] / [Earlier])
      NTabBar {
        id: tabsBox
        Layout.fillWidth: true
        margins: Style.marginS
        visible: NotificationService.historyList.count > 0 && panelContent.groupByDate
        currentIndex: panelContent.currentRange
        tabHeight: Style.baseWidgetSize * 0.7
        spacing: Style.marginXS
        distributeEvenly: true
        border.color: Style.boxBorderColor
        border.width: Style.borderS

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

      // Notification list container with gradient overlay
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NScrollView {
          id: scrollView
          anchors.fill: parent
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          ScrollBar.vertical.policy: ScrollBar.AsNeeded
          clip: true

          ColumnLayout {
            width: parent.width
            spacing: Style.marginM

            NBox {
              visible: !panelContent.hasNotificationsInCurrentRange()
              Layout.fillWidth: true
              Layout.preferredHeight: emptyState.implicitHeight + Style.marginM * 2

              // Empty state when no notifications
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

            // Track which notification is expanded
            property string expandedId: ""

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
                  model: NotificationService.historyList

                  delegate: Item {
                    id: notificationDelegate
                    width: parent.width
                    visible: panelContent.isInCurrentRange(model.timestamp)
                    height: visible ? contentColumn.height + (Style.marginM * 2) : 0

                    property string notificationId: model.id
                    property bool isExpanded: scrollView.expandedId === notificationId
                    property bool canExpand: summaryText.truncated || bodyText.truncated || (actionsList.length > 0) // Explicitly allow expand if actions exist

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
                      color: Color.mSurfaceVariant

                      Behavior on color {
                        enabled: !Settings.data.general.animationDisabled
                        ColorAnimation {
                          duration: Style.animationFast
                        }
                      }
                    }

                    // Click to expand/collapse
                    MouseArea {
                      anchors.fill: parent
                      anchors.rightMargin: Style.baseWidgetSize
                      enabled: notificationDelegate.canExpand
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: {
                        if (scrollView.expandedId === notificationId) {
                          scrollView.expandedId = "";
                        } else {
                          scrollView.expandedId = notificationId;
                        }
                      }
                    }

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

                          // Actions Flow
                          Flow {
                            width: parent.width
                            spacing: Style.marginS
                            visible: notificationDelegate.actionsList.length > 0

                            Repeater {
                              model: notificationDelegate.actionsList
                              delegate: NButton {
                                text: modelData.text
                                // Explicitly set primary colors
                                backgroundColor: Color.mPrimary
                                textColor: Color.mOnPrimary
                                outlined: false
                                implicitHeight: 24

                                // Capture modelData in a property to avoid reference errors
                                property var actionData: modelData

                                fontWeight: Style.fontWeightRegular // Use regular font weight

                                onClicked: {
                                  NotificationService.invokeAction(notificationDelegate.notificationId, actionData.identifier);
                                }
                              }
                            }
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

        // Overlay gradient to smooth the hard cut due to scrolling at the bottom (only visible when scrollable)
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          visible: scrollView.ScrollBar.vertical && scrollView.ScrollBar.vertical.size < 1.0
          opacity: {
            const scrollBar = scrollView.ScrollBar.vertical;
            return (scrollBar.position + scrollBar.size >= 0.99) ? 0 : 1;
          }

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutQuad
            }
          }

          gradient: Gradient {
            GradientStop {
              position: 0.0
              color: "transparent"
            }
            GradientStop {
              position: 0.85
              color: "transparent"
            }
            GradientStop {
              position: 1.0
              color: Qt.alpha(Color.mSurface, 0.95)
            }
          }
        }
      }
    }
  }
}

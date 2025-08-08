import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Settings

PanelWithOverlay {
    id: notificationHistoryWin

    property string historyFilePath: Settings.settingsDir + "notification_history.json"
    property bool hasUnread: notificationHistoryWinRect.hasUnread && !notificationHistoryWinRect.visible

    function addToHistory(notification) {
        notificationHistoryWinRect.addToHistory(notification);
    }

    Rectangle {
        id: notificationHistoryWinRect

        property int maxPopupHeight: 800
        property int minPopupHeight: 210
        property int contentHeight: headerRow.height + historyList.contentHeight + 56
        property int maxHistory: 100
        property bool hasUnread: false

        signal unreadChanged(bool hasUnread)

        function updateHasUnread() {
            var unread = false;
            for (let i = 0; i < historyModel.count; ++i) {
                if (historyModel.get(i).read === false) {
                    unread = true;
                    break;
                }
            }
            if (hasUnread !== unread) {
                hasUnread = unread;
                unreadChanged(hasUnread);
            }
        }

        function loadHistory() {
            if (historyAdapter.notifications) {
                historyModel.clear();
                const notifications = historyAdapter.notifications;
                const count = Math.min(notifications.length, maxHistory);
                for (let i = 0; i < count; i++) {
                    let n = notifications[i];
                    if (typeof n === 'object' && n !== null) {
                        if (n.read === undefined)
                            n.read = false;

                        // Mark as read if window is open
                        if (notificationHistoryWinRect.visible)
                            n.read = true;

                        historyModel.append(n);
                    }
                }
                updateHasUnread();
            }
        }

        function saveHistory() {
            const historyArray = [];
            const count = Math.min(historyModel.count, maxHistory);
            for (let i = 0; i < count; ++i) {
                let obj = historyModel.get(i);
                if (typeof obj === 'object' && obj !== null)
                    historyArray.push({
                        "id": obj.id,
                        "appName": obj.appName,
                        "summary": obj.summary,
                        "body": obj.body,
                        "timestamp": obj.timestamp,
                        "read": obj.read === undefined ? false : obj.read
                    });

            }
            historyAdapter.notifications = historyArray;
            Qt.callLater(function() {
                historyFileView.writeAdapter();
            });
            updateHasUnread();
        }

        function addToHistory(notification) {
            if (!notification.id)
                notification.id = Date.now();

            if (!notification.timestamp)
                notification.timestamp = new Date().toISOString();

            // Mark as read if window is open
            notification.read = visible;
            // Remove duplicate by id
            for (let i = 0; i < historyModel.count; ++i) {
                if (historyModel.get(i).id === notification.id) {
                    historyModel.remove(i);
                    break;
                }
            }
            historyModel.insert(0, notification);
            if (historyModel.count > maxHistory)
                historyModel.remove(maxHistory);

            saveHistory();
        }

        function clearHistory() {
            historyModel.clear();
            historyAdapter.notifications = [];
            historyFileView.writeAdapter();
        }

        function formatTimestamp(ts) {
            if (!ts)
                return "";

            var date = typeof ts === "number" ? new Date(ts) : new Date(Date.parse(ts));
            var y = date.getFullYear();
            var m = (date.getMonth() + 1).toString().padStart(2, '0');
            var d = date.getDate().toString().padStart(2, '0');
            var h = date.getHours().toString().padStart(2, '0');
            var min = date.getMinutes().toString().padStart(2, '0');
            return `${y}-${m}-${d} ${h}:${min}`;
        }

        implicitWidth: 400
        implicitHeight: Math.max(Math.min(contentHeight, maxPopupHeight), minPopupHeight)
        visible: parent.visible
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 4
        color: Theme.backgroundPrimary
        radius: 20
        onVisibleChanged: {
            if (visible) {
                // Mark all as read when popup is opened
                let changed = false;
                for (let i = 0; i < historyModel.count; ++i) {
                    if (historyModel.get(i).read === false) {
                        historyModel.setProperty(i, 'read', true);
                        changed = true;
                    }
                }
                if (changed)
                    saveHistory();

            }
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
        }

        ListModel {
            id: historyModel
        }

        FileView {
            id: historyFileView

            path: notificationHistoryWin.historyFilePath
            blockLoading: true
            printErrors: true
            watchChanges: true
            onFileChanged: historyFileView.reload()
            onLoaded: notificationHistoryWinRect.loadHistory()
            onLoadFailed: function(error) {
                historyAdapter.notifications = [];
                historyFileView.writeAdapter();
            }
            Component.onCompleted: {
                if (path) {
                    reload();
                }
            }

            JsonAdapter {
                id: historyAdapter

                property var notifications: []
            }

        }

        Rectangle {
            width: notificationHistoryWinRect.width
            height: notificationHistoryWinRect.height
            anchors.fill: parent
            color: Theme.backgroundPrimary
            radius: 20

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    id: headerRow

                    spacing: 4
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 52
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16

                    Text {
                        text: "Notification History"
                        font.pixelSize: 18
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        id: clearAllButton

                        width: 90
                        height: 32
                        radius: 16
                        color: clearAllMouseArea.containsMouse ? Theme.accentPrimary : Theme.surfaceVariant
                        border.color: Theme.accentPrimary
                        border.width: 1
                        Layout.alignment: Qt.AlignVCenter

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "delete_sweep"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 14
                                color: clearAllMouseArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                text: "Clear"
                                font.pixelSize: Theme.fontSizeSmall
                                color: clearAllMouseArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                        }

                        MouseArea {
                            id: clearAllMouseArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notificationHistoryWinRect.clearHistory()
                        }

                    }

                }

                Rectangle {
                    width: parent.width
                    height: 0
                    color: "transparent"
                    visible: true
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 56
                    height: notificationHistoryWinRect.height - 56 - 12
                    color: Theme.surfaceVariant
                    radius: 20

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.surface
                        radius: 20
                        z: 0
                    }

                    Rectangle {
                        id: listContainer

                        anchors.fill: parent
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        color: "transparent"
                        clip: true

                        Column {
                            anchors.fill: parent
                            spacing: 0

                            ListView {
                                id: historyList

                                width: parent.width
                                height: Math.min(contentHeight, parent.height)
                                spacing: 12
                                model: historyModel.count > 0 ? historyModel : placeholderModel
                                clip: true

                                delegate: Item {
                                    width: parent.width
                                    height: notificationCard.implicitHeight + 12

                                    Rectangle {
                                        id: notificationCard

                                        width: parent.width - 24
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        color: Theme.backgroundPrimary
                                        radius: 16
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 0
                                        implicitHeight: contentColumn.implicitHeight + 20

                                        Column {
                                            id: contentColumn

                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 6

                                            RowLayout {
                                                id: headerRow2

                                                spacing: 8

                                                Rectangle {
                                                    id: iconBackground

                                                    width: 28
                                                    height: 28
                                                    radius: 20
                                                    color: Theme.accentPrimary
                                                    border.color: Qt.darker(Theme.accentPrimary, 1.2)
                                                    border.width: 1.2
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: model.appName ? model.appName.charAt(0).toUpperCase() : "?"
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 15
                                                        font.bold: true
                                                        color: Theme.backgroundPrimary
                                                    }

                                                }

                                                Column {
                                                    id: appInfoColumn

                                                    spacing: 0
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Text {
                                                        text: model.appName || "No Notifications"
                                                        font.bold: true
                                                        color: Theme.textPrimary
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    Text {
                                                        visible: !model.isPlaceholder
                                                        text: model.timestamp ? notificationHistoryWinRect.formatTimestamp(model.timestamp) : ""
                                                        color: Theme.textDisabled
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSizeCaption
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                }

                                            }

                                            Text {
                                                text: model.summary || (model.isPlaceholder ? "You're all caught up!" : "")
                                                color: Theme.textSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeBody
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                            }

                                            Text {
                                                text: model.body || (model.isPlaceholder ? "No notifications to show." : "")
                                                color: Theme.textDisabled
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeBody
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                }

                Rectangle {
                    width: 1
                    height: 24
                    color: "transparent"
                }

                ListModel {
                    id: placeholderModel

                    ListElement {
                        appName: ""
                        summary: ""
                        body: ""
                        isPlaceholder: true
                    }

                }

            }

        }

    }

}

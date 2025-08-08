import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Settings

PanelWindow {
    id: window
    width: 350
    implicitHeight: notificationColumn.implicitHeight + 20
    color: "transparent"
    visible: false
    screen: Quickshell.primaryScreen
    focusable: false
    
    anchors.top: true
    anchors.right: true
            margins.top: -20
    margins.right: 6

    property var notifications: []
    property int maxVisible: 5
    property int spacing: 10

    function addNotification(notification) {
        var notifObj = {
            id: notification.id,
            appName: notification.appName || "Notification",
            summary: notification.summary || "",
            body: notification.body || "",
            rawNotification: notification
        };
        notifications.unshift(notifObj);

        if (notifications.length > maxVisible) {
            notifications = notifications.slice(0, maxVisible);
        }

        visible = true;
        notificationsChanged();
    }

    function dismissNotification(id) {
        notifications = notifications.filter(n => n.id !== id);
        if (notifications.length === 0) {
            visible = false;
        }
        notificationsChanged();
    }

    Column {
        id: notificationColumn
        anchors.right: parent.right
        spacing: window.spacing
        width: parent.width
        clip: false // Prevent clipping during animation

        Repeater {
            model: notifications

            delegate: Rectangle {
                id: notificationDelegate
                width: parent.width
                height: contentColumn.height + 20
                color: Theme.backgroundPrimary
                radius: 20
                opacity: 1

                Column {
                    id: contentColumn
                    width: parent.width - 20
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: modelData.appName
                        width: parent.width
                        color: "white"
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.summary
                        width: parent.width
                        color: "#eeeeee"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                        visible: text !== ""
                    }

                    Text {
                        text: modelData.body
                        width: parent.width
                        color: "#cccccc"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        wrapMode: Text.Wrap
                        visible: text !== ""
                    }
                }

                Timer {
                    interval: 4000
                    running: true
                    onTriggered: {
                        dismissAnimation.start();
                        if (modelData.rawNotification) {
                            modelData.rawNotification.expire();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        dismissAnimation.start();
                        if (modelData.rawNotification) {
                            modelData.rawNotification.dismiss();
                        }
                    }
                }

                ParallelAnimation {
                    id: dismissAnimation
                    NumberAnimation {
                        target: notificationDelegate
                        property: "opacity"
                        to: 0
                        duration: 300
                    }
                    NumberAnimation {
                        target: notificationDelegate
                        property: "height"
                        to: 0
                        duration: 300
                    }
                    onFinished: window.dismissNotification(modelData.id)
                }

                Component.onCompleted: {
                    opacity = 0;
                    height = 0;
                    appearAnimation.start();
                }

                ParallelAnimation {
                    id: appearAnimation
                    NumberAnimation {
                        target: notificationDelegate
                        property: "opacity"
                        to: 1
                        duration: 300
                    }
                    NumberAnimation {
                        target: notificationDelegate
                        property: "height"
                        to: contentColumn.height + 20
                        duration: 300
                    }
                }
            }
        }
    }

    onNotificationsChanged: {
        height = notificationColumn.implicitHeight + 20
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (window.screen) {
                x = window.screen.width - width - 20
                // y stays as it is (margins.top = -20)
            }
        }
    }
}

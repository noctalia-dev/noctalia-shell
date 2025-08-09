import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs.Settings

// Main container that manages multiple notification popups for different monitors
Item {
    id: notificationManager
    anchors.fill: parent

    // Get list of available monitors/screens
    property var monitors: Quickshell.screens || []
    
    // Component.onCompleted: {
    //     console.log("[NotificationPopup] Initialized with", monitors.length, "monitors");
    //     for (let i = 0; i < monitors.length; i++) {
    //         console.log("[NotificationPopup] Monitor", i, ":", monitors[i].name);
    //     }
    // }
    
    // Global visibility state for all notification popups
    property bool notificationsVisible: true
    
    function togglePopup(): void {
        console.log("[NotificationManager] Current state: " + notificationsVisible);
        notificationsVisible = !notificationsVisible;
        console.log("[NotificationManager] New state: " + notificationsVisible);
    }
    
    function addNotification(notification): void {
        console.log("[NotificationPopup] Adding notification to popup manager");
        // Add notification to all monitor popups
        for (let i = 0; i < children.length; i++) {
            let child = children[i];
            if (child.addNotification) {
                child.addNotification(notification);
            }
        }
    }

    // Create a notification popup for each monitor
    Repeater {
        model: notificationManager.monitors
        delegate: Item {
            id: delegateItem
            
            // Make addNotification accessible from the Item level
            function addNotification(notification) {
                if (panelWindow) {
                    panelWindow.addNotification(notification);
                }
            }
            
            PanelWindow {
                id: panelWindow
                implicitWidth: 350
                implicitHeight: Math.max(notificationColumn.height, 0)
                color: "transparent"
                visible: notificationManager.notificationsVisible && notificationModel.count > 0 && shouldShowOnThisMonitor
                screen: modelData
                focusable: false

                property bool barVisible: true
                property bool notificationsVisible: notificationManager.notificationsVisible
                
                // Check if this monitor should show notifications - make it reactive to settings changes
                property bool shouldShowOnThisMonitor: {
                    let notificationMonitors = Settings.settings.notificationMonitors || [];
                    let currentScreenName = modelData ? modelData.name : "";
                    // Show notifications on monitors listed or if list contains "*"
                    let shouldShow = notificationMonitors.includes("*") || 
                           notificationMonitors.includes(currentScreenName);
                    // console.log("[NotificationPopup] Monitor", currentScreenName, "should show:", shouldShow, "monitors:", JSON.stringify(notificationMonitors));
                    return shouldShow;
                }

                // Watch for changes in notification monitors setting
                Connections {
                    target: Settings.settings
                    function onNotificationMonitorsChanged() {
                        // Settings changed, visibility will update automatically
                    }
                }

                anchors.top: true
                anchors.right: true
                margins.top: 6
                margins.right: 6

                ListModel {
                    id: notificationModel
                }

                property int maxVisible: 5
                property int spacing: 5

                function addNotification(notification) {
                    console.log("[NotificationPopup] Adding notification to monitor popup:", notification.appName);
                    notificationModel.insert(0, {
                        id: notification.id,
                        appName: notification.appName || "Notification",
                        summary: notification.summary || "",
                        body: notification.body || "",
                        urgency: notification.urgency || 0,
                        rawNotification: notification,
                        appeared: false,
                        dismissed: false
                    });

                    while (notificationModel.count > maxVisible) {
                        notificationModel.remove(notificationModel.count - 1);
                    }
                }

                function dismissNotificationById(id) {
                    for (var i = 0; i < notificationModel.count; i++) {
                        if (notificationModel.get(i).id === id) {
                            dismissNotificationByIndex(i);
                            break;
                        }
                    }
                }

                function dismissNotificationByIndex(index) {
                    if (index >= 0 && index < notificationModel.count) {
                        var notif = notificationModel.get(index);
                        if (!notif.dismissed) {
                            notificationModel.set(index, {
                                id: notif.id,
                                appName: notif.appName,
                                summary: notif.summary,
                                body: notif.body,
                                rawNotification: notif.rawNotification,
                                appeared: notif.appeared,
                                dismissed: true
                            });
                        }
                    }
                }

                Column {
                    id: notificationColumn
                    anchors.right: parent.right
                    spacing: panelWindow.spacing
                    width: parent.width
                    clip: false

                    Repeater {
                        id: notificationRepeater
                        model: notificationModel

                        delegate: Rectangle {
                            id: notificationDelegate
                            width: parent.width
                            color: Theme.backgroundPrimary
                            radius: 20
                            border.color: model.urgency == 2 ? Theme.warning : Theme.outline
                            border.width: 1

                            property bool appeared: model.appeared
                            property bool dismissed: model.dismissed
                            property var rawNotification: model.rawNotification

                            x: appeared ? 0 : width
                            opacity: dismissed ? 0 : 1
                            height: dismissed ? 0 : Math.max(contentRow.height, 60) + 20

                            Row {
                                id: contentRow
                                anchors.centerIn: parent
                                spacing: 10
                                width: parent.width - 20

                                // Circular Icon container with border
                                Rectangle {
                                    id: iconBackground
                                    width: 36
                                    height: 36
                                    radius: width / 2
                                    color: Theme.accentPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                    border.color: Qt.darker(Theme.accentPrimary, 1.2)
                                    border.width: 1.5

                                    // Priority order for notification icons: image > appIcon > icon
                                    property var iconSources: [rawNotification?.image || "", rawNotification?.appIcon || "", rawNotification?.icon || ""]

                                    // Load notification icon with fallback handling
                                    IconImage {
                                        id: iconImage
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        asynchronous: true
                                        backer.fillMode: Image.PreserveAspectFit
                                        source: {
                                            // Try each icon source in priority order
                                            for (var i = 0; i < iconBackground.iconSources.length; i++) {
                                                var icon = iconBackground.iconSources[i];
                                                if (!icon)
                                                    continue;

                                                // Handle special path format from some notifications
                                                if (icon.includes("?path=")) {
                                                    const [name, path] = icon.split("?path=");
                                                    const fileName = name.substring(name.lastIndexOf("/") + 1);
                                                    return `file://${path}/${fileName}`;
                                                }

                                                // Handle absolute file paths
                                                if (icon.startsWith('/')) {
                                                    return "file://" + icon;
                                                }

                                                return icon;
                                            }
                                            return "";
                                        }
                                        visible: status === Image.Ready && source.toString() !== ""
                                    }

                                    // Fallback: show first letter of app name when no icon available
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !iconImage.visible
                                        text: model.appName ? model.appName.charAt(0).toUpperCase() : "?"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                        color: Theme.backgroundPrimary
                                    }
                                }

                                Column {
                                    width: contentRow.width - iconBackground.width - 10
                                    spacing: 5

                                    Text {
                                        text: model.appName
                                        width: parent.width
                                        color: Theme.textPrimary
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: model.summary
                                        width: parent.width
                                        color: "#eeeeee"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.Wrap
                                        visible: text !== ""
                                    }
                                    Text {
                                        text: model.body
                                        width: parent.width
                                        color: "#cccccc"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeCaption
                                        wrapMode: Text.Wrap
                                        visible: text !== ""
                                    }
                                }
                            }

                            Timer {
                                interval: 4000
                                running: !dismissed
                                repeat: false
                                onTriggered: {
                                    dismissAnimation.start();
                                    if (rawNotification)
                                        rawNotification.expire();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    dismissAnimation.start();
                                    if (rawNotification)
                                        rawNotification.dismiss();
                                }
                            }

                            ParallelAnimation {
                                id: dismissAnimation
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "opacity"
                                    to: 0
                                    duration: 150
                                }
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "height"
                                    to: 0
                                    duration: 150
                                }
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "x"
                                    to: width
                                    duration: 150
                                    easing.type: Easing.InQuad
                                }
                                onFinished: {
                                    for (let i = 0; i < notificationModel.count; i++) {
                                        if (notificationModel.get(i).id === notificationDelegate.id) {
                                            notificationModel.remove(i);
                                            break;
                                        }
                                    }
                                }
                            }

                            ParallelAnimation {
                                id: appearAnimation
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "opacity"
                                    to: 1
                                    duration: 150
                                }
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "height"
                                    to: Math.max(contentRow.height, 60) + 20
                                    duration: 150
                                }
                                NumberAnimation {
                                    target: notificationDelegate
                                    property: "x"
                                    to: 0
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }

                            Timer {
                                id: appearTimer
                                interval: 10
                                repeat: false
                                onTriggered: {
                                    appearAnimation.start();
                                }
                            }

                            Component.onCompleted: {
                                if (!appeared) {
                                    opacity = 0;
                                    height = 0;
                                    x = width;
                                    // Small delay to ensure contentRow has proper height
                                    appearTimer.start();
                                    for (let i = 0; i < notificationModel.count; i++) {
                                        if (notificationModel.get(i).id === notificationDelegate.id) {
                                            var oldItem = notificationModel.get(i);
                                            notificationModel.set(i, {
                                                id: oldItem.id,
                                                appName: oldItem.appName,
                                                summary: oldItem.summary,
                                                body: oldItem.body,
                                                rawNotification: oldItem.rawNotification,
                                                appeared: true,
                                                read: oldItem.read,
                                                dismissed: oldItem.dismissed
                                            });
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Connections {
                    target: Quickshell
                    function onScreensChanged() {
                        if (panelWindow.screen) {
                            x = panelWindow.screen.width - panelWindow.width - 20;
                        }
                    }
                }
            }
        }
    }
}

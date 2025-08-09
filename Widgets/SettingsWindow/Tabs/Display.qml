import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Settings
import qs.Components

ColumnLayout {
    id: root

    // Get list of available monitors/screens
    property var monitors: Quickshell.screens || []

    // Sorted monitors by name
    property var sortedMonitors: {
        let sorted = [...monitors];
        sorted.sort((a, b) => {
            let nameA = a.name || "Unknown";
            let nameB = b.name || "Unknown";
            return nameA.localeCompare(nameB);
        });
        return sorted;
    }

    spacing: 0
    anchors.fill: parent
    anchors.margins: 0

    function orientationToString(o) {
        // Map common Qt orientations; fallback to string
        if (o === Qt.LandscapeOrientation) return "Landscape";
        if (o === Qt.PortraitOrientation) return "Portrait";
        if (o === Qt.InvertedLandscapeOrientation) return "Inverted Landscape";
        if (o === Qt.InvertedPortraitOrientation) return "Inverted Portrait";
        try {
            return String(o);
        } catch (e) {
            return "Unknown";
        }
    }

    ScrollView {
        id: scrollView

        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 16
        rightPadding: 12
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 0

            Text {
                text: "Monitor Selection"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            Text {
                text: "Configure the Bar, Dock and Notifications for each monitor. Details below help differentiate similar displays."
                font.pixelSize: 12 * Theme.scale(screen)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.bottomMargin: 12 * Theme.scale(screen)
            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                visible: false

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Bar Monitors"
                            font.pixelSize: 13 * Theme.scale(screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display the top panel/bar on"
                            font.pixelSize: 12 * Theme.scale(screen)
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

        
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.sortedMonitors
                        delegate: Rectangle {
                            id: barCheckbox
                            property bool isChecked: false
                            
                            Component.onCompleted: {
                                // Initialize checkbox state from settings
                                let monitors = Settings.settings.barMonitors || [];
                                isChecked = monitors.includes(modelData.name);
                            }
                            
                            width: checkboxContent.implicitWidth + 16
                            height: 32
                            radius: 16
                            color: isChecked ? Theme.accentPrimary : Theme.surfaceVariant
                            border.color: isChecked ? Theme.accentPrimary : Theme.outline
                            border.width: 1

                            RowLayout {
                                id: checkboxContent
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: barCheckbox.isChecked ? "check" : ""
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 14 * Theme.scale(screen)
                                    color: barCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: barCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(screen)
                                    color: barCheckbox.isChecked ? Theme.onAccent : Theme.textPrimary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    isChecked = !isChecked;
                                    
                                    // Update settings array when checkbox is toggled
                                    let monitors = Settings.settings.barMonitors || [];
                                    monitors = [...monitors]; // Create copy to trigger reactivity
                                    
                                    if (isChecked) {
                                        if (!monitors.includes(modelData.name)) {
                                            monitors.push(modelData.name);
                                        }
                                    } else {
                                        monitors = monitors.filter(name => name !== modelData.name);
                                    }
                                    
                                    Settings.settings.barMonitors = monitors;
                                    console.log("Bar monitors updated:", JSON.stringify(monitors));
                                }
                            }
                        }
                    }
                }
            }


            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                visible: false

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Dock Monitors"
                            font.pixelSize: 13 * Theme.scale(screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display the application dock on"
                            font.pixelSize: 12 * Theme.scale(screen)
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }


                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.sortedMonitors
                        delegate: Rectangle {
                            id: dockCheckbox
                            property bool isChecked: false
                            
                            Component.onCompleted: {
                                // Initialize with current settings
                                let monitors = Settings.settings.dockMonitors || [];
                                isChecked = monitors.includes(modelData.name);
                            }
                            
                            width: checkboxContent.implicitWidth + 16
                            height: 32
                            radius: 16
                            color: isChecked ? Theme.accentPrimary : Theme.surfaceVariant
                            border.color: isChecked ? Theme.accentPrimary : Theme.outline
                            border.width: 1

                            RowLayout {
                                id: checkboxContent
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: dockCheckbox.isChecked ? "check" : ""
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 14 * Theme.scale(screen)
                                    color: dockCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: dockCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(screen)
                                    color: dockCheckbox.isChecked ? Theme.onAccent : Theme.textPrimary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Toggle state immediately for UI responsiveness
                                    isChecked = !isChecked;
                                    
                                    // Update settings
                                    let monitors = Settings.settings.dockMonitors || [];
                                    monitors = [...monitors]; // Copy array
                                    
                                    if (isChecked) {
                                        // Add to array if not already there
                                        if (!monitors.includes(modelData.name)) {
                                            monitors.push(modelData.name);
                                        }
                                    } else {
                                        // Remove from array
                                        monitors = monitors.filter(name => name !== modelData.name);
                                    }
                                    
                                    Settings.settings.dockMonitors = monitors;
                                    console.log("Dock monitors updated:", JSON.stringify(monitors));
                                }
                            }
                        }
                    }
                }
            }


            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                visible: true
            // New per-monitor layout
            ColumnLayout {
                id: perMonitorLayout
                spacing: 12 * Theme.scale(screen)
                Layout.fillWidth: true

                Repeater {
                    model: root.sortedMonitors
                    delegate: Rectangle {
                        id: monitorCard
                        property string monitorName: modelData.name || ""
                        // Treat empty lists as "all monitors" so toggles reflect reality
                        property bool barChecked: {
                            const list = Settings.settings.barMonitors || []
                            return list.includes("*") || list.includes(monitorName)
                        }
                        property bool dockChecked: {
                            const list = Settings.settings.dockMonitors || []
                            return list.includes("*") || list.includes(monitorName)
                        }
                        property bool notifChecked: {
                            const list = Settings.settings.notificationMonitors || []
                            return list.includes("*") || list.includes(monitorName)
                        }
                        Layout.fillWidth: true
                        radius: 12 * Theme.scale(screen)
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        implicitHeight: contentCol.implicitHeight + 24 * Theme.scale(screen)

                        ColumnLayout {
                            id: contentCol
                            anchors.fill: parent
                            anchors.margins: 12 * Theme.scale(screen)
                            spacing: 8 * Theme.scale(screen)

                            // Monitor title
                            Text {
                                text: modelData.name || "Unknown"
                                font.pixelSize: 16 * Theme.scale(screen)
                                font.bold: true
                                color: Theme.accentPrimary
                            }

                            // Details laid out as four columns: Model, Position, Resolution, Orientation
                            GridLayout {
                                columns: 4
                                columnSpacing: 16 * Theme.scale(screen)
                                rowSpacing: 2 * Theme.scale(screen)

                                // Model
                                ColumnLayout {
                                    spacing: 2 * Theme.scale(screen)
                                    Text { text: "Model"; color: Theme.textSecondary; font.pixelSize: 10 * Theme.scale(screen) }
                                    Text { text: modelData.model || "-"; color: Theme.textPrimary; font.pixelSize: 12 * Theme.scale(screen) }
                                }

                                // Position
                                ColumnLayout {
                                    spacing: 2 * Theme.scale(screen)
                                    Text { text: "Position"; color: Theme.textSecondary; font.pixelSize: 10 * Theme.scale(screen) }
                                    Text { text: `(${(modelData.x || 0)}, ${(modelData.y || 0)})`; color: Theme.textPrimary; font.pixelSize: 12 * Theme.scale(screen) }
                                }

                                // Resolution
                                ColumnLayout {
                                    spacing: 2 * Theme.scale(screen)
                                    Text { text: "Resolution"; color: Theme.textSecondary; font.pixelSize: 10 * Theme.scale(screen) }
                                    Text { text: `${(modelData.width || 0)}x${(modelData.height || 0)}`; color: Theme.textPrimary; font.pixelSize: 12 * Theme.scale(screen) }
                                }

                                // Orientation
                                ColumnLayout {
                                    spacing: 2 * Theme.scale(screen)
                                    Text { text: "Orientation"; color: Theme.textSecondary; font.pixelSize: 10 * Theme.scale(screen) }
                                    Text { text: orientationToString(modelData.orientation); color: Theme.textPrimary; font.pixelSize: 12 * Theme.scale(screen) }
                                }
                            }

                            // Bar toggle
                            ToggleOption {
                                label: "Bar"
                                description: "Display the top bar on this monitor"
                                value: monitorCard.barChecked
                                onToggled: function() {
                                    let monitors = Settings.settings.barMonitors || []
                                    monitors = [...monitors]
                                    const name = monitorCard.monitorName
                                    const allNames = (root.sortedMonitors || []).map(m => m.name).filter(n => !!n)
                                    const isSingle = allNames.length <= 1
                                    const isAll = monitors.includes("*")
                                    const isOn = isAll || monitors.includes(name)

                                    if (isSingle) {
                                        Settings.settings.barMonitors = isOn ? [] : ["*"]
                                        return
                                    }

                                    if (isOn) {
                                        if (isAll) {
                                            // From all -> all except this one
                                            monitors = allNames.filter(n => n !== name)
                                        } else {
                                            monitors = monitors.filter(n => n !== name)
                                        }
                                    } else {
                                        if (!monitors.includes(name)) monitors.push(name)
                                    }

                                    Settings.settings.barMonitors = monitors
                                }
                            }

                            // Dock toggle
                            ToggleOption {
                                label: "Dock"
                                description: "Display the dock on this monitor"
                                value: monitorCard.dockChecked
                                onToggled: function() {
                                    let monitors = Settings.settings.dockMonitors || []
                                    monitors = [...monitors]
                                    const name = monitorCard.monitorName
                                    const allNames = (root.sortedMonitors || []).map(m => m.name).filter(n => !!n)
                                    const isSingle = allNames.length <= 1
                                    const isAll = monitors.includes("*")
                                    const isOn = isAll || monitors.includes(name)

                                    if (isSingle) {
                                        Settings.settings.dockMonitors = isOn ? [] : ["*"]
                                        return
                                    }

                                    if (isOn) {
                                        if (isAll) {
                                            monitors = allNames.filter(n => n !== name)
                                        } else {
                                            monitors = monitors.filter(n => n !== name)
                                        }
                                    } else {
                                        if (!monitors.includes(name)) monitors.push(name)
                                    }

                                    Settings.settings.dockMonitors = monitors
                                }
                            }

                            // Notification toggle
                            ToggleOption {
                                label: "Notifications"
                                description: "Display notifications on this monitor"
                                value: monitorCard.notifChecked
                                onToggled: function() {
                                    let monitors = Settings.settings.notificationMonitors || []
                                    monitors = [...monitors]
                                    const name = monitorCard.monitorName
                                    const allNames = (root.sortedMonitors || []).map(m => m.name).filter(n => !!n)
                                    const isSingle = allNames.length <= 1
                                    const isAll = monitors.includes("*")
                                    const isOn = isAll || monitors.includes(name)

                                    if (isSingle) {
                                        Settings.settings.notificationMonitors = isOn ? [] : ["*"]
                                        return
                                    }

                                    if (isOn) {
                                        if (isAll) {
                                            monitors = allNames.filter(n => n !== name)
                                        } else {
                                            monitors = monitors.filter(n => n !== name)
                                        }
                                    } else {
                                        if (!monitors.includes(name)) monitors.push(name)
                                    }

                                    Settings.settings.notificationMonitors = monitors
                                }
                            }

                            // Scale slider
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4 * Theme.scale(screen)
                                Text { text: "Scale"; color: Theme.textSecondary; font.pixelSize: 10 * Theme.scale(screen) }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8 * Theme.scale(screen)
                                    // Value read from settings override, default to Theme.scale(modelData)
                                    property real currentValue: (Settings.settings.monitorScaleOverrides && Settings.settings.monitorScaleOverrides[monitorCard.monitorName] !== undefined) ? Settings.settings.monitorScaleOverrides[monitorCard.monitorName] : Theme.scale(modelData)
                                    function commitScale(newValue) {
                                        if (!isFinite(newValue)) return
                                        let overrides = Settings.settings.monitorScaleOverrides || {}
                                        overrides = Object.assign({}, overrides)
                                        overrides[monitorCard.monitorName] = newValue
                                        Settings.settings.monitorScaleOverrides = overrides
                                        parent.currentValue = newValue
                                    }
                                    // Reusable slider component
                                    ThemedSlider {
                                        id: scaleSlider
                                        Layout.fillWidth: true
                                        screen: modelData
                                        cutoutColor: Theme.surface
                                        from: 0.8
                                        to: 2.0
                                        stepSize: 0.02
                                        snapAlways: false
                                        value: parent.currentValue
                                        onMoved: parent.currentValue = value
                                        onPressedChanged: if (!pressed) parent.commitScale(value)
                                    }
                                    Text { text: parent.currentValue.toFixed(2); font.pixelSize: 12 * Theme.scale(screen); color: Theme.textPrimary; width: 40 }
                                }
                            }
                        }
                    }
                }
            }
                RowLayout {
                    visible: false
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Notification Monitors"
                            font.pixelSize: 13 * Theme.scale(screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display system notifications on"
                            font.pixelSize: 12 * Theme.scale(screen)
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }


                Flow {
                    visible: false
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.sortedMonitors
                        delegate: Rectangle {
                            id: notificationCheckbox
                            property bool isChecked: false
                            
                            Component.onCompleted: {
                                // Initialize with current settings
                                let monitors = Settings.settings.notificationMonitors || [];
                                isChecked = monitors.includes(modelData.name);
                            }
                            
                            width: checkboxContent.implicitWidth + 16
                            height: 32
                            radius: 16
                            color: isChecked ? Theme.accentPrimary : Theme.surfaceVariant
                            border.color: isChecked ? Theme.accentPrimary : Theme.outline
                            border.width: 1

                            RowLayout {
                                id: checkboxContent
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: notificationCheckbox.isChecked ? "check" : ""
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 14 * Theme.scale(screen)
                                    color: notificationCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: notificationCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(screen)
                                    color: notificationCheckbox.isChecked ? Theme.onAccent : Theme.textPrimary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Toggle state immediately for UI responsiveness
                                    isChecked = !isChecked;
                                    
                                    // Update settings
                                    let monitors = Settings.settings.notificationMonitors || [];
                                    monitors = [...monitors]; // Copy array
                                    
                                    if (isChecked) {
                                        // Add to array if not already there
                                        if (!monitors.includes(modelData.name)) {
                                            monitors.push(modelData.name);
                                        }
                                    } else {
                                        // Remove from array
                                        monitors = monitors.filter(name => name !== modelData.name);
                                    }
                                    
                                    Settings.settings.notificationMonitors = monitors;
                                    console.log("Notification monitors updated:", JSON.stringify(monitors));
                                }
                            }
                        }
                    }
                }
            }

        }

    }

}
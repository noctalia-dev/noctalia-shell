import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Settings

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
                font.pixelSize: 18 * Theme.scale(Screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(Screen)
            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Bar Monitors"
                            font.pixelSize: 13 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display the top panel/bar on"
                            font.pixelSize: 12 * Theme.scale(Screen)
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
                                    font.pixelSize: 14 * Theme.scale(Screen)
                                    color: barCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: barCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(Screen)
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

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Dock Monitors"
                            font.pixelSize: 13 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display the application dock on"
                            font.pixelSize: 12 * Theme.scale(Screen)
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
                                    font.pixelSize: 14 * Theme.scale(Screen)
                                    color: dockCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: dockCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(Screen)
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

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Notification Monitors"
                            font.pixelSize: 13 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Select which monitors to display system notifications on"
                            font.pixelSize: 12 * Theme.scale(Screen)
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
                                    font.pixelSize: 14 * Theme.scale(Screen)
                                    color: notificationCheckbox.isChecked ? Theme.onAccent : Theme.textSecondary
                                    visible: notificationCheckbox.isChecked
                                }

                                Text {
                                    text: modelData.name || "Unknown"
                                    font.pixelSize: 12 * Theme.scale(Screen)
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
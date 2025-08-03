import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Quickshell.Widgets
import qs.Components
import qs.Settings

Rectangle {
    id: profileSettingsCard
    Layout.fillWidth: true
    Layout.preferredHeight: 690
    color: Theme.surface
    radius: 18

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                text: "settings"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                color: Theme.accentPrimary
            }
            Text {
                text: "Profile Settings"
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }
        }

        // Profile Image Input Section
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Profile Image"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                // Profile image
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24

                    // Border
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: 24
                        border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 2
                        z: 2
                    }

                    Avatar {}
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 16
                    color: Theme.surfaceVariant
                    border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1

                    TextInput {
                        id: profileImageInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        text: Settings.settings.profileImage
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        onTextChanged: {
                            Settings.settings.profileImage = text;
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: profileImageInput.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Show Active Window Icon Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show Active Window Icon"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: activeWindowIconSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showActiveWindowIcon ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showActiveWindowIcon ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: activeWindowIconThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showActiveWindowIcon ? activeWindowIconSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showActiveWindowIcon = !Settings.settings.showActiveWindowIcon;
                    }
                }
            }
        }

        // Show System Info In Bar Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show System Info In Bar"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: systemInfoSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showSystemInfoInBar ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showSystemInfoInBar ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: systemInfoThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showSystemInfoInBar ? systemInfoSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showSystemInfoInBar = !Settings.settings.showSystemInfoInBar;
                    }
                }
            }
        }

        // Show Corners Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show Corners"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: cornersSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: cornersThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showCorners ? cornersSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showCorners = !Settings.settings.showCorners;
                    }
                }
            }
        }

        // Show Taskbar Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show Taskbar"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: taskbarSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showTaskbar ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showTaskbar ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: taskbarThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showTaskbar ? taskbarSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showTaskbar = !Settings.settings.showTaskbar;
                    }
                }
            }
        }

        // Show Dock Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show Dock"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: dockSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showDock ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showDock ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: dockThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showDock ? taskbarSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showDock = !Settings.settings.showDock;
                    }
                }
            }
        }

        // Show Media In Bar Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Show Media In Bar"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: mediaSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.showMediaInBar ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.showMediaInBar ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: mediaThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.showMediaInBar ? mediaSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.showMediaInBar = !Settings.settings.showMediaInBar;
                    }
                }
            }
        }

        // Dim Windows Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Dim Desktop"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                id: dimSwitch
                width: 52
                height: 32
                radius: 16
                color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: dimThumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.dimPanels ? dimSwitch.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Settings.settings.dimPanels = !Settings.settings.dimPanels;
                    }
                }
            }
        }

        // Visualizer Type Selection
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 16

            Text {
                text: "Visualizer Type"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            ComboBox {
                id: visualizerTypeComboBox
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                model: ["radial", "fire", "diamond"]
                currentIndex: model.indexOf(Settings.settings.visualizerType)

                background: Rectangle {
                    implicitWidth: 120
                    implicitHeight: 40
                    color: Theme.surfaceVariant
                    border.color: visualizerTypeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1
                    radius: 16
                }

                contentItem: Text {
                    leftPadding: 12
                    rightPadding: visualizerTypeComboBox.indicator.width + visualizerTypeComboBox.spacing
                    text: visualizerTypeComboBox.displayText.charAt(0).toUpperCase() + visualizerTypeComboBox.displayText.slice(1)
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: visualizerTypeComboBox.width - width - 12
                    y: visualizerTypeComboBox.topPadding + (visualizerTypeComboBox.availableHeight - height) / 2
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24
                    color: Theme.textPrimary
                }

                popup: Popup {
                    y: visualizerTypeComboBox.height
                    width: visualizerTypeComboBox.width
                    implicitHeight: contentItem.implicitHeight
                    padding: 1

                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: visualizerTypeComboBox.popup.visible ? visualizerTypeComboBox.delegateModel : null
                        currentIndex: visualizerTypeComboBox.highlightedIndex

                        ScrollIndicator.vertical: ScrollIndicator {}
                    }

                    background: Rectangle {
                        color: Theme.surfaceVariant
                        border.color: Theme.outline
                        border.width: 1
                        radius: 16
                    }
                }

                delegate: ItemDelegate {
                    width: visualizerTypeComboBox.width
                    contentItem: Text {
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    highlighted: visualizerTypeComboBox.highlightedIndex === index

                    background: Rectangle {
                        color: highlighted ? Theme.accentPrimary.toString().replace(/#/, "#1A") : "transparent"
                    }
                }

                onActivated: {
                    Settings.settings.visualizerType = model[index];
                }
            }
        }

        // Video Path Input Section
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 16

            Text {
                text: "Video Path"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 16
                color: Theme.surfaceVariant
                border.color: videoPathInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                TextInput {
                    id: videoPathInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    text: Settings.settings.videoPath !== undefined ? Settings.settings.videoPath : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true
                    activeFocusOnTab: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly
                    onTextChanged: {
                        Settings.settings.videoPath = text;
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: videoPathInput.forceActiveFocus()
                    }
                }
            }
        }
    }
}

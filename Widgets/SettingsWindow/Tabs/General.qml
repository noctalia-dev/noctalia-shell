import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings

ColumnLayout {
    id: root

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
                text: "Profile"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            Text {
                text: "Profile Image"
                font.pixelSize: 13 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 4 * Theme.scale(screen)
            }

            Text {
                text: "Your profile picture displayed in various places throughout the shell"
                font.pixelSize: 12 * Theme.scale(screen)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.bottomMargin: 4
            }

            RowLayout {
                spacing: 8 * Theme.scale(screen)
                Layout.fillWidth: true

                Rectangle {
                    width: 48 * Theme.scale(screen)
                    height: 48 * Theme.scale(screen)
                    radius: 24

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: 24
                        border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 2 * Theme.scale(screen)
                        z: 2
                    }

                    Avatar {
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40 * Theme.scale(screen)
                    radius: 16
                    color: Theme.surfaceVariant
                    border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1 * Theme.scale(screen)

                    TextInput {
                        id: profileImageInput

                        anchors.fill: parent
                        anchors.leftMargin: 12 * Theme.scale(screen)
                        anchors.rightMargin: 12 * Theme.scale(screen)
                        anchors.topMargin: 6 * Theme.scale(screen)
                        anchors.bottomMargin: 6 * Theme.scale(screen)
                        text: Settings.settings.profileImage
                        font.pixelSize: 13 * Theme.scale(screen)
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

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 26 * Theme.scale(screen)
                Layout.bottomMargin: 18 * Theme.scale(screen)
                height: 1 // Don't scale divider
                color: Theme.outline
                opacity: 0.3
            }

            Text {
                text: "User Interface"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            ToggleOption {
                label: "Show Corners"
                description: "Display rounded corners on the edge of the screen"
                value: Settings.settings.showCorners
                onToggled: function() {
                    Settings.settings.showCorners = !Settings.settings.showCorners;
                }
            }

            ToggleOption {
                label: "Show Dock"
                description: "Display a dock at the bottom of the screen for quick access to applications"
                value: Settings.settings.showDock
                onToggled: function() {
                    Settings.settings.showDock = !Settings.settings.showDock;
                }
            }

            ToggleOption {
                label: "Dim Desktop"
                description: "Dim the desktop when panels or menus are open"
                value: Settings.settings.dimPanels
                onToggled: function() {
                    Settings.settings.dimPanels = !Settings.settings.dimPanels;
                }
            }

        }

    }

}

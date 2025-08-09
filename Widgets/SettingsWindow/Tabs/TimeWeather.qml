import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow.Tabs.Components

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
                text: "Time"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            ToggleOption {
                label: "Use 12 Hour Clock"
                description: "Display time in 12-hour format (e.g., 2:30 PM) instead of 24-hour format"
                value: Settings.settings.use12HourClock
                onToggled: function() {
                    Settings.settings.use12HourClock = !Settings.settings.use12HourClock;
                }
            }

            ToggleOption {
                label: "US Style Date"
                description: "Display dates in MM/DD/YYYY format instead of DD/MM/YYYY"
                value: Settings.settings.reverseDayMonth
                onToggled: function() {
                    Settings.settings.reverseDayMonth = !Settings.settings.reverseDayMonth;
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 26
                Layout.bottomMargin: 18
                height: 1
                color: Theme.outline
                opacity: 0.3
            }

            Text {
                text: "Weather"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.bottomMargin: 8 * Theme.scale(screen)

                Text {
                    text: "City"
                    font.pixelSize: 13 * Theme.scale(screen)
                    font.bold: true
                    color: Theme.textPrimary
                }

                Text {
                    text: "Your city name for weather information"
                    font.pixelSize: 12 * Theme.scale(screen)
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 16
                    color: Theme.surfaceVariant
                    border.color: cityInput.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1

                    TextInput {
                        id: cityInput

                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        text: Settings.settings.weatherCity
                        font.pixelSize: 13 * Theme.scale(screen)
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        inputMethodHints: Qt.ImhNone
                        onTextChanged: {
                            Settings.settings.weatherCity = text;
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                cityInput.forceActiveFocus();
                            }
                        }

                    }

                }

            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 8

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        Text {
                            text: "Temperature Unit"
                            font.pixelSize: 13 * Theme.scale(screen)
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Choose between Celsius and Fahrenheit"
                            font.pixelSize: 12 * Theme.scale(screen)
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                    }

                    UnitSelector {
                    }

                }

            }

        }

    }

}

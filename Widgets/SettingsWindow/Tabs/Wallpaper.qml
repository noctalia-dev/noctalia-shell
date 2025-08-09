import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Services
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

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 0
            }

            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "Wallpaper Settings"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.bottomMargin: 8
                }

                // Wallpaper Settings Category
                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    // Wallpaper Folder
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true

                        Text {
                            text: "Wallpaper Folder"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Path to your wallpaper folder"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 16
                                color: Theme.surfaceVariant
                                border.color: folderInput.activeFocus ? Theme.accentPrimary : Theme.outline
                                border.width: 1

                                TextInput {
                                    id: folderInput

                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 6
                                    anchors.bottomMargin: 6
                                    text: Settings.settings.wallpaperFolder !== undefined ? Settings.settings.wallpaperFolder : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: Theme.textPrimary
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    activeFocusOnTab: true
                                    inputMethodHints: Qt.ImhUrlCharactersOnly
                                    onTextChanged: {
                                        Settings.settings.wallpaperFolder = text;
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: folderInput.forceActiveFocus()
                                }

                            }

                        }

                    }

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

            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "Automation"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.bottomMargin: 8
                }

                // Random Wallpaper
                ToggleOption {
                    label: "Random Wallpaper"
                    description: "Automatically select random wallpapers from the folder"
                    value: Settings.settings.randomWallpaper
                    onToggled: function() {
                        Settings.settings.randomWallpaper = !Settings.settings.randomWallpaper;
                    }
                }

                // Use Wallpaper Theme
                ToggleOption {
                    label: "Use Wallpaper Theme"
                    description: "Automatically adjust theme colors based on wallpaper"
                    value: Settings.settings.useWallpaperTheme
                    onToggled: function() {
                        Settings.settings.useWallpaperTheme = !Settings.settings.useWallpaperTheme;
                    }
                }

                // Wallpaper Interval
                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Wallpaper Interval"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "How often to change wallpapers automatically (in seconds)"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: Settings.settings.wallpaperInterval + " seconds"
                            font.pixelSize: 13
                            color: Theme.textPrimary
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                    }

                    ThemedSlider {
                        id: intervalSlider
                        Layout.fillWidth: true
                        cutoutColor: Theme.backgroundPrimary
                        from: 10
                        to: 900
                        stepSize: 10
                        value: Settings.settings.wallpaperInterval
                        snapAlways: true
                        onMoved: {
                            Settings.settings.wallpaperInterval = Math.round(value);
                        }
                    }

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

            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "SWWW"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.bottomMargin: 8
                }

                // Use SWWW
                ToggleOption {
                    label: "Use SWWW"
                    description: "Use SWWW daemon for advanced wallpaper management"
                    value: Settings.settings.useSWWW
                    onToggled: function() {
                        Settings.settings.useSWWW = !Settings.settings.useSWWW;
                    }
                }

                // SWWW Settings (only visible when useSWWW is enabled)
                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: Settings.settings.useSWWW

                    // Resize Mode
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true

                        Text {
                            text: "Resize Mode"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "How SWWW should resize wallpapers to fit the screen"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 16
                            color: Theme.surfaceVariant
                            border.color: resizeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1

                            ComboBox {
                                id: resizeComboBox

                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                model: ["no", "crop", "fit", "stretch"]
                                currentIndex: model.indexOf(Settings.settings.wallpaperResize)
                                onActivated: {
                                    Settings.settings.wallpaperResize = model[index];
                                }

                                background: Rectangle {
                                    color: "transparent"
                                }

                                contentItem: Text {
                                    text: resizeComboBox.displayText
                                    font: resizeComboBox.font
                                    color: Theme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignLeft
                                }

                                popup: Popup {
                                    y: resizeComboBox.height
                                    width: resizeComboBox.width
                                    implicitHeight: contentItem.implicitHeight
                                    padding: 1

                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: resizeComboBox.popup.visible ? resizeComboBox.delegateModel : null
                                        currentIndex: resizeComboBox.highlightedIndex

                                        ScrollIndicator.vertical: ScrollIndicator {
                                        }

                                    }

                                    background: Rectangle {
                                        color: Theme.surface
                                        border.color: Theme.outline
                                        border.width: 1
                                        radius: 8
                                    }

                                }

                                delegate: ItemDelegate {
                                    width: resizeComboBox.width
                                    highlighted: resizeComboBox.highlightedIndex === index

                                    contentItem: Text {
                                        text: modelData
                                        color: Theme.textPrimary
                                        font: resizeComboBox.font
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    background: Rectangle {
                                        color: parent.highlighted ? Theme.accentPrimary : "transparent"
                                    }

                                }

                            }

                        }

                    }

                    // Transition Type
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Layout.topMargin: 8

                        Text {
                            text: "Transition Type"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Animation type when switching between wallpapers"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 16
                            color: Theme.surfaceVariant
                            border.color: transitionTypeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1

                            ComboBox {
                                id: transitionTypeComboBox

                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                model: ["none", "simple", "fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer", "random"]
                                currentIndex: model.indexOf(Settings.settings.transitionType)
                                onActivated: {
                                    Settings.settings.transitionType = model[index];
                                }

                                background: Rectangle {
                                    color: "transparent"
                                }

                                contentItem: Text {
                                    text: transitionTypeComboBox.displayText
                                    font: transitionTypeComboBox.font
                                    color: Theme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignLeft
                                }

                                popup: Popup {
                                    y: transitionTypeComboBox.height
                                    width: transitionTypeComboBox.width
                                    implicitHeight: contentItem.implicitHeight
                                    padding: 1

                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: transitionTypeComboBox.popup.visible ? transitionTypeComboBox.delegateModel : null
                                        currentIndex: transitionTypeComboBox.highlightedIndex

                                        ScrollIndicator.vertical: ScrollIndicator {
                                        }

                                    }

                                    background: Rectangle {
                                        color: Theme.surface
                                        border.color: Theme.outline
                                        border.width: 1
                                        radius: 8
                                    }

                                }

                                delegate: ItemDelegate {
                                    width: transitionTypeComboBox.width
                                    highlighted: transitionTypeComboBox.highlightedIndex === index

                                    contentItem: Text {
                                        text: modelData
                                        color: Theme.textPrimary
                                        font: transitionTypeComboBox.font
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    background: Rectangle {
                                        color: parent.highlighted ? Theme.accentPrimary : "transparent"
                                    }

                                }

                            }

                        }

                    }

                    // Transition FPS
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Layout.topMargin: 8

                        Text {
                            text: "Transition FPS"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Frames per second for transition animations"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: Settings.settings.transitionFps + " FPS"
                                font.pixelSize: 13
                                color: Theme.textPrimary
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                        }

                        ThemedSlider {
                            id: fpsSlider
                            Layout.fillWidth: true
                            cutoutColor: Theme.backgroundPrimary
                            from: 30
                            to: 500
                            stepSize: 5
                            value: Settings.settings.transitionFps
                            snapAlways: true
                            onMoved: {
                                Settings.settings.transitionFps = Math.round(value);
                            }
                        }

                    }

                    // Transition Duration
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Layout.topMargin: 8

                        Text {
                            text: "Transition Duration"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Duration of transition animations in seconds"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: Settings.settings.transitionDuration.toFixed(3) + " seconds"
                                font.pixelSize: 13
                                color: Theme.textPrimary
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                        }

                        ThemedSlider {
                            id: durationSlider
                            Layout.fillWidth: true
                            cutoutColor: Theme.backgroundPrimary
                            from: 0.25
                            to: 10
                            stepSize: 0.05
                            value: Settings.settings.transitionDuration
                            snapAlways: true
                            onMoved: {
                                Settings.settings.transitionDuration = value;
                            }
                        }

                    }

                }

            }

        }

    }

}

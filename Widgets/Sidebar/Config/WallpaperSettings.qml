import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Settings

Rectangle {
    id: wallpaperSettingsCard

    Layout.fillWidth: true
    Layout.preferredHeight: Settings.settings.useSWWW ? 720 : 360
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
                text: "image"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                color: Theme.accentPrimary
            }

            Text {
                text: "Wallpaper Settings"
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }
        }

        // Wallpaper Path
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Wallpaper Path"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            // Folder Path Input
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 16
                color: Theme.surfaceVariant
                border.color: folderInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                TextInput {
                    id: folderInput

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    text: Settings.settings.wallpaperFolder
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

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: folderInput.forceActiveFocus()
                    }

                }

            }

        }



        // Random Wallpaper Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Random Wallpaper"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: randomWallpaperSwitch

                width: 52
                height: 32
                radius: 16
                color: Settings.settings.randomWallpaper ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.randomWallpaper ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: randomWallpaperThumb

                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.randomWallpaper ? randomWallpaperSwitch.width - width - 2 : 2

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
                        Settings.settings.randomWallpaper = !Settings.settings.randomWallpaper;
                    }
                }

            }

        }

        // Use Wallpaper Theme Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Use Wallpaper Theme"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: wallpaperThemeSwitch

                width: 52
                height: 32
                radius: 16
                color: Settings.settings.useWallpaperTheme ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.useWallpaperTheme ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: wallpaperThemeThumb

                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.useWallpaperTheme ? wallpaperThemeSwitch.width - width - 2 : 2

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
                        Settings.settings.useWallpaperTheme = !Settings.settings.useWallpaperTheme;
                    }
                }

            }

        }

        // Wallpaper Interval Setting
        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Wallpaper Interval (seconds)"
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: Settings.settings.wallpaperInterval
                    font.pixelSize: 13
                    color: Theme.textPrimary
                }

            }

            Slider {
                id: intervalSlider

                Layout.fillWidth: true
                from: 10
                to: 900
                stepSize: 10
                value: Settings.settings.wallpaperInterval
                snapMode: Slider.SnapAlways
                onMoved: {
                    Settings.settings.wallpaperInterval = Math.round(value);
                }

                background: Rectangle {
                    x: intervalSlider.leftPadding
                    y: intervalSlider.topPadding + intervalSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: intervalSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: intervalSlider.visualPosition * parent.width
                        height: parent.height
                        color: Theme.accentPrimary
                        radius: 2
                    }

                }

                handle: Rectangle {
                    x: intervalSlider.leftPadding + intervalSlider.visualPosition * (intervalSlider.availableWidth - width)
                    y: intervalSlider.topPadding + intervalSlider.availableHeight / 2 - height / 2
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: intervalSlider.pressed ? Theme.surfaceVariant : Theme.surface
                    border.color: Theme.accentPrimary
                    border.width: 2
                }

            }

        }

        // Use SWWW Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            Text {
                text: "Use SWWW"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: swwwSwitch

                width: 52
                height: 32
                radius: 16
                color: Settings.settings.useSWWW ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: Settings.settings.useSWWW ? Theme.accentPrimary : Theme.outline
                border.width: 2

                Rectangle {
                    id: swwwThumb

                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: Settings.settings.useSWWW ? swwwSwitch.width - width - 2 : 2

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
                        Settings.settings.useSWWW = !Settings.settings.useSWWW;
                    }
                }

            }

        }

        // Resize Mode Setting
        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: Settings.settings.useSWWW

            Text {
                text: "Resize Mode"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            ComboBox {
                id: resizeComboBox

                Layout.fillWidth: true
                Layout.preferredHeight: 40
                model: ["no", "crop", "fit", "stretch"]
                currentIndex: model.indexOf(Settings.settings.wallpaperResize)
                onActivated: {
                    Settings.settings.wallpaperResize = model[index];
                }

                background: Rectangle {
                    implicitWidth: 120
                    implicitHeight: 40
                    color: Theme.surfaceVariant
                    border.color: resizeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1
                    radius: 16
                }

                contentItem: Text {
                    leftPadding: 12
                    rightPadding: resizeComboBox.indicator.width + resizeComboBox.spacing
                    text: resizeComboBox.displayText
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: resizeComboBox.width - width - 12
                    y: resizeComboBox.topPadding + (resizeComboBox.availableHeight - height) / 2
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24
                    color: Theme.textPrimary
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
                        color: Theme.surfaceVariant
                        border.color: Theme.outline
                        border.width: 1
                        radius: 16
                    }

                }

                delegate: ItemDelegate {
                    width: resizeComboBox.width
                    highlighted: resizeComboBox.highlightedIndex === index

                    contentItem: Text {
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        color: highlighted ? Theme.accentPrimary.toString().replace(/#/, "#1A") : "transparent"
                    }

                }

            }

        }

        // Transition Type Setting
        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: Settings.settings.useSWWW

            Text {
                text: "Transition Type"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            ComboBox {
                id: transitionTypeComboBox

                Layout.fillWidth: true
                Layout.preferredHeight: 40
                model: ["none", "simple", "fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer", "random"]
                currentIndex: model.indexOf(Settings.settings.transitionType)
                onActivated: {
                    Settings.settings.transitionType = model[index];
                }

                background: Rectangle {
                    implicitWidth: 120
                    implicitHeight: 40
                    color: Theme.surfaceVariant
                    border.color: transitionTypeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1
                    radius: 16
                }

                contentItem: Text {
                    leftPadding: 12
                    rightPadding: transitionTypeComboBox.indicator.width + transitionTypeComboBox.spacing
                    text: transitionTypeComboBox.displayText
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: transitionTypeComboBox.width - width - 12
                    y: transitionTypeComboBox.topPadding + (transitionTypeComboBox.availableHeight - height) / 2
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24
                    color: Theme.textPrimary
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
                        color: Theme.surfaceVariant
                        border.color: Theme.outline
                        border.width: 1
                        radius: 16
                    }

                }

                delegate: ItemDelegate {
                    width: transitionTypeComboBox.width
                    highlighted: transitionTypeComboBox.highlightedIndex === index

                    contentItem: Text {
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        color: highlighted ? Theme.accentPrimary.toString().replace(/#/, "#1A") : "transparent"
                    }

                }

            }

        }

        // Transition FPS Setting
        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: Settings.settings.useSWWW

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Transition FPS"
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: Settings.settings.transitionFps
                    font.pixelSize: 13
                    color: Theme.textPrimary
                }

            }

            Slider {
                id: fpsSlider

                Layout.fillWidth: true
                from: 30
                to: 500
                stepSize: 5
                value: Settings.settings.transitionFps
                snapMode: Slider.SnapAlways
                onMoved: {
                    Settings.settings.transitionFps = Math.round(value);
                }

                background: Rectangle {
                    x: fpsSlider.leftPadding
                    y: fpsSlider.topPadding + fpsSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: fpsSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: fpsSlider.visualPosition * parent.width
                        height: parent.height
                        color: Theme.accentPrimary
                        radius: 2
                    }

                }

                handle: Rectangle {
                    x: fpsSlider.leftPadding + fpsSlider.visualPosition * (fpsSlider.availableWidth - width)
                    y: fpsSlider.topPadding + fpsSlider.availableHeight / 2 - height / 2
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: fpsSlider.pressed ? Theme.surfaceVariant : Theme.surface
                    border.color: Theme.accentPrimary
                    border.width: 2
                }

            }

        }

        // Transition Duration Setting
        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: Settings.settings.useSWWW
            
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Transition Duration (seconds)"
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: Settings.settings.transitionDuration.toFixed(3)
                    font.pixelSize: 13
                    color: Theme.textPrimary
                }

            }

            Slider {
                id: durationSlider

                Layout.fillWidth: true
                from: 0.25
                to: 10
                stepSize: 0.05
                value: Settings.settings.transitionDuration
                snapMode: Slider.SnapAlways
                onMoved: {
                    Settings.settings.transitionDuration = value;
                }

                background: Rectangle {
                    x: durationSlider.leftPadding
                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: durationSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: durationSlider.visualPosition * parent.width
                        height: parent.height
                        color: Theme.accentPrimary
                        radius: 2
                    }

                }

                handle: Rectangle {
                    x: durationSlider.leftPadding + durationSlider.visualPosition * (durationSlider.availableWidth - width)
                    y: durationSlider.topPadding + durationSlider.availableHeight / 2 - height / 2
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: durationSlider.pressed ? Theme.surfaceVariant : Theme.surface
                    border.color: Theme.accentPrimary
                    border.width: 2
                }

            }

        }

    }

}

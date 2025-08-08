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

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 0
            }

            ColumnLayout {
                // Text {
                //     text: "Screen Recording"
                //     font.pixelSize: 18 * Theme.scale(Screen)
                //     font.bold: true
                //     color: Theme.textPrimary
                //     Layout.bottomMargin: 8
                // }

                spacing: 4
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    Text {
                        text: "Output Directory"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Directory where screen recordings will be saved"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
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
                            font.pixelSize: 13 * Theme.scale(Screen)
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

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Frame Rate"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Target frame rate for screen recordings (default: 60)"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    SpinBox {
                        id: frameRateSpinBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        from: 24
                        to: 144
                        value: Settings.settings.recordingFrameRate || 60
                        stepSize: 1
                        onValueChanged: {
                            Settings.settings.recordingFrameRate = value;
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: frameRateSpinBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: TextInput {
                            text: frameRateSpinBox.textFromValue(frameRateSpinBox.value, frameRateSpinBox.locale)
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            selectionColor: Theme.accentPrimary
                            selectedTextColor: Theme.onAccent
                            horizontalAlignment: Qt.AlignHCenter
                            verticalAlignment: Qt.AlignVCenter
                            readOnly: false
                            selectByMouse: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            onTextChanged: {
                                var newValue = parseInt(text);
                                if (!isNaN(newValue) && newValue >= frameRateSpinBox.from && newValue <= frameRateSpinBox.to)
                                    frameRateSpinBox.value = newValue;

                            }
                            onEditingFinished: {
                                var newValue = parseInt(text);
                                if (isNaN(newValue) || newValue < frameRateSpinBox.from || newValue > frameRateSpinBox.to)
                                    text = frameRateSpinBox.textFromValue(frameRateSpinBox.value, frameRateSpinBox.locale);

                            }

                            validator: IntValidator {
                                bottom: frameRateSpinBox.from
                                top: frameRateSpinBox.to
                            }

                        }

                        up.indicator: Rectangle {
                            x: parent.width - width
                            height: parent.height
                            width: height
                            color: "transparent"
                            radius: 16

                            Text {
                                text: "add"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 20 * Theme.scale(Screen)
                                color: Theme.textPrimary
                                anchors.centerIn: parent
                            }

                        }

                        down.indicator: Rectangle {
                            x: 0
                            height: parent.height
                            width: height
                            color: "transparent"
                            radius: 16

                            Text {
                                text: "remove"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 20 * Theme.scale(Screen)
                                color: Theme.textPrimary
                                anchors.centerIn: parent
                            }

                        }

                    }

                }

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Audio Source"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Audio source to capture during recording"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    ComboBox {
                        id: audioSourceComboBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        model: ["default_output", "default_input", "both"]
                        currentIndex: model.indexOf(Settings.settings.recordingAudioSource || "default_output")
                        onActivated: {
                            Settings.settings.recordingAudioSource = model[index];
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: audioSourceComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: Text {
                            leftPadding: 12
                            rightPadding: audioSourceComboBox.indicator.width + audioSourceComboBox.spacing
                            text: {
                                switch (audioSourceComboBox.currentText) {
                                case "default_output":
                                    return "System Audio";
                                case "default_input":
                                    return "Microphone";
                                case "both":
                                    return "System Audio + Microphone";
                                default:
                                    return audioSourceComboBox.currentText;
                                }
                            }
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Text {
                            x: audioSourceComboBox.width - width - 12
                            y: audioSourceComboBox.topPadding + (audioSourceComboBox.availableHeight - height) / 2
                            text: "arrow_drop_down"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.textPrimary
                        }

                        popup: Popup {
                            y: audioSourceComboBox.height
                            width: audioSourceComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: audioSourceComboBox.popup.visible ? audioSourceComboBox.delegateModel : null
                                currentIndex: audioSourceComboBox.highlightedIndex

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
                            width: audioSourceComboBox.width
                            highlighted: audioSourceComboBox.highlightedIndex === index

                            contentItem: Text {
                                text: {
                                    switch (modelData) {
                                    case "default_output":
                                        return "System Audio";
                                    case "default_input":
                                        return "Microphone";
                                    case "both":
                                        return "System Audio + Microphone";
                                    default:
                                        return modelData;
                                    }
                                }
                                font.pixelSize: 13 * Theme.scale(Screen)
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

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Video Quality"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Higher quality results in larger file sizes"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    ComboBox {
                        id: qualityComboBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        model: ["medium", "high", "very_high", "ultra"]
                        currentIndex: model.indexOf(Settings.settings.recordingQuality || "very_high")
                        onActivated: {
                            Settings.settings.recordingQuality = model[index];
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: qualityComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: Text {
                            leftPadding: 12
                            rightPadding: qualityComboBox.indicator.width + qualityComboBox.spacing
                            text: {
                                switch (qualityComboBox.currentText) {
                                case "medium":
                                    return "Medium";
                                case "high":
                                    return "High";
                                case "very_high":
                                    return "Very High";
                                case "ultra":
                                    return "Ultra";
                                default:
                                    return qualityComboBox.currentText;
                                }
                            }
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Text {
                            x: qualityComboBox.width - width - 12
                            y: qualityComboBox.topPadding + (qualityComboBox.availableHeight - height) / 2
                            text: "arrow_drop_down"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.textPrimary
                        }

                        popup: Popup {
                            y: qualityComboBox.height
                            width: qualityComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: qualityComboBox.popup.visible ? qualityComboBox.delegateModel : null
                                currentIndex: qualityComboBox.highlightedIndex

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
                            width: qualityComboBox.width
                            highlighted: qualityComboBox.highlightedIndex === index

                            contentItem: Text {
                                text: {
                                    switch (modelData) {
                                    case "medium":
                                        return "Medium";
                                    case "high":
                                        return "High";
                                    case "very_high":
                                        return "Very High";
                                    case "ultra":
                                        return "Ultra";
                                    default:
                                        return modelData;
                                    }
                                }
                                font.pixelSize: 13 * Theme.scale(Screen)
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

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Video Codec"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Different codecs offer different compression and compatibility"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    ComboBox {
                        id: codecComboBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        model: ["h264", "hevc", "av1", "vp8", "vp9"]
                        currentIndex: model.indexOf(Settings.settings.recordingCodec || "h264")
                        onActivated: {
                            Settings.settings.recordingCodec = model[index];
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: codecComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: Text {
                            leftPadding: 12
                            rightPadding: codecComboBox.indicator.width + codecComboBox.spacing
                            text: codecComboBox.currentText.toUpperCase()
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Text {
                            x: codecComboBox.width - width - 12
                            y: codecComboBox.topPadding + (codecComboBox.availableHeight - height) / 2
                            text: "arrow_drop_down"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.textPrimary
                        }

                        popup: Popup {
                            y: codecComboBox.height
                            width: codecComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: codecComboBox.popup.visible ? codecComboBox.delegateModel : null
                                currentIndex: codecComboBox.highlightedIndex

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
                            width: codecComboBox.width
                            highlighted: codecComboBox.highlightedIndex === index

                            contentItem: Text {
                                text: modelData.toUpperCase()
                                font.pixelSize: 13 * Theme.scale(Screen)
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

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Text {
                        text: "Audio Codec"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Opus is recommended for best performance and smallest audio size"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    ComboBox {
                        id: audioCodecComboBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        model: ["opus", "aac"]
                        currentIndex: model.indexOf(Settings.settings.audioCodec || "opus")
                        onActivated: {
                            Settings.settings.audioCodec = model[index];
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: audioCodecComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: Text {
                            leftPadding: 12
                            rightPadding: audioCodecComboBox.indicator.width + audioCodecComboBox.spacing
                            text: audioCodecComboBox.currentText.toUpperCase()
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Text {
                            x: audioCodecComboBox.width - width - 12
                            y: audioCodecComboBox.topPadding + (audioCodecComboBox.availableHeight - height) / 2
                            text: "arrow_drop_down"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.textPrimary
                        }

                        popup: Popup {
                            y: audioCodecComboBox.height
                            width: audioCodecComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: audioCodecComboBox.popup.visible ? audioCodecComboBox.delegateModel : null
                                currentIndex: audioCodecComboBox.highlightedIndex

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
                            width: audioCodecComboBox.width
                            highlighted: audioCodecComboBox.highlightedIndex === index

                            contentItem: Text {
                                text: modelData.toUpperCase()
                                font.pixelSize: 13 * Theme.scale(Screen)
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

                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 16

                    Text {
                        text: "Color Range"
                        font.pixelSize: 13 * Theme.scale(Screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Limited is recommended for better compatibility"
                        font.pixelSize: 12 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        Layout.bottomMargin: 4
                    }

                    ComboBox {
                        id: colorRangeComboBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        model: ["limited", "full"]
                        currentIndex: model.indexOf(Settings.settings.colorRange || "limited")
                        onActivated: {
                            Settings.settings.colorRange = model[index];
                        }

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            color: Theme.surfaceVariant
                            border.color: colorRangeComboBox.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 1
                            radius: 16
                        }

                        contentItem: Text {
                            leftPadding: 12
                            rightPadding: colorRangeComboBox.indicator.width + colorRangeComboBox.spacing
                            text: colorRangeComboBox.currentText.charAt(0).toUpperCase() + colorRangeComboBox.currentText.slice(1)
                            font.pixelSize: 13 * Theme.scale(Screen)
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Text {
                            x: colorRangeComboBox.width - width - 12
                            y: colorRangeComboBox.topPadding + (colorRangeComboBox.availableHeight - height) / 2
                            text: "arrow_drop_down"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.textPrimary
                        }

                        popup: Popup {
                            y: colorRangeComboBox.height
                            width: colorRangeComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: colorRangeComboBox.popup.visible ? colorRangeComboBox.delegateModel : null
                                currentIndex: colorRangeComboBox.highlightedIndex

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
                            width: colorRangeComboBox.width
                            highlighted: colorRangeComboBox.highlightedIndex === index

                            contentItem: Text {
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.pixelSize: 13 * Theme.scale(Screen)
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

                ToggleOption {
                    label: "Show Cursor"
                    description: "Record mouse cursor in the video"
                    value: Settings.settings.showCursor
                    onToggled: function() {
                        Settings.settings.showCursor = !Settings.settings.showCursor;
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
            }

        }

    }

}

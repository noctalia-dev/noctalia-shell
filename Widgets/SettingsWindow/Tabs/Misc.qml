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
                text: "Media"
                font.pixelSize: 18 * Theme.scale(Screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(Screen)
            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true

                Text {
                    text: "Visualizer Type"
                    font.pixelSize: 13 * Theme.scale(Screen)
                    font.bold: true
                    color: Theme.textPrimary
                }

                Text {
                    text: "Choose the style of the audio visualizer"
                    font.pixelSize: 12 * Theme.scale(Screen)
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                }

                ComboBox {
                    id: visualizerTypeComboBox

                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    model: ["radial", "fire", "diamond"]
                    currentIndex: model.indexOf(Settings.settings.visualizerType)
                    onActivated: {
                        Settings.settings.visualizerType = model[index];
                    }

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
                        padding: 8

                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: visualizerTypeComboBox.popup.visible ? visualizerTypeComboBox.delegateModel : null
                            currentIndex: visualizerTypeComboBox.highlightedIndex

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
                        width: visualizerTypeComboBox.width
                        highlighted: visualizerTypeComboBox.highlightedIndex === index

                        contentItem: Text {
                            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
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

        }

    }

}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Settings

PanelWithOverlay {
    id: ioSelector

    property int tabIndex: 0
    property Item anchorItem: null

    signal panelClosed()

    function sinkNodes() {
        let nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values.filter(function(n) {
            return n.isSink && n.audio && n.isStream === false;
        }) : [];
        if (Pipewire.defaultAudioSink)
            nodes = nodes.slice().sort(function(a, b) {
                if (a.id === Pipewire.defaultAudioSink.id)
                    return -1;

                if (b.id === Pipewire.defaultAudioSink.id)
                    return 1;

                return 0;
            });

        return nodes;
    }

    function sourceNodes() {
        let nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values.filter(function(n) {
            return !n.isSink && n.audio && n.isStream === false;
        }) : [];
        if (Pipewire.defaultAudioSource)
            nodes = nodes.slice().sort(function(a, b) {
                if (a.id === Pipewire.defaultAudioSource.id)
                    return -1;

                if (b.id === Pipewire.defaultAudioSource.id)
                    return 1;

                return 0;
            });

        return nodes;
    }

    Component.onCompleted: {
        if (Pipewire.nodes && Pipewire.nodes.values) {
            for (var i = 0; i < Pipewire.nodes.values.length; ++i) {
                var n = Pipewire.nodes.values[i];
            }
        }
    }
    Component.onDestruction: {
    }
    onVisibleChanged: {
        if (!visible)
            panelClosed();

    }

    // Bind all Pipewire nodes so their properties are valid
    PwObjectTracker {
        id: nodeTracker

        objects: Pipewire.nodes
    }

    Rectangle {
        color: Theme.backgroundPrimary
        radius: 20
        width: 340
        height: 340
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 4

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // Tabs centered inside the window
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 0

                Tabs {
                    id: ioTabs

                    tabsModel: [{
                        "label": "Output",
                        "icon": "volume_up"
                    }, {
                        "label": "Input",
                        "icon": "mic"
                    }]
                    currentIndex: tabIndex
                    onTabChanged: {
                        tabIndex = currentIndex;
                    }
                }

            }

            // Add vertical space between tabs and entries
            Item {
                height: 36
                Layout.fillWidth: true
            }

            // Output Devices
            Flickable {
                id: sinkList

                visible: tabIndex === 0
                contentHeight: sinkColumn.height
                clip: true
                interactive: contentHeight > height
                width: parent.width
                height: 220

                ColumnLayout {
                    id: sinkColumn

                    width: sinkList.width
                    spacing: 6

                    Repeater {
                        model: ioSelector.sinkNodes()

                        Rectangle {
                            width: parent.width
                            height: 36
                            color: "transparent"
                            radius: 6

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                Text {
                                    text: "volume_up"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16 * Theme.scale(Screen)
                                    color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === modelData.id) ? Theme.accentPrimary : Theme.textPrimary
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Layout.maximumWidth: sinkList.width - 120 // Reserve space for the Set button

                                    Text {
                                        text: modelData.nickname || modelData.description || modelData.name
                                        font.bold: true
                                        font.pixelSize: 12 * Theme.scale(Screen)
                                        color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === modelData.id) ? Theme.accentPrimary : Theme.textPrimary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.description !== modelData.nickname ? modelData.description : ""
                                        font.pixelSize: 10 * Theme.scale(Screen)
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }

                                }

                                Rectangle {
                                    visible: Pipewire.preferredDefaultAudioSink !== modelData
                                    width: 60
                                    height: 20
                                    radius: 4
                                    color: Theme.accentPrimary
                                    border.color: Theme.accentPrimary
                                    border.width: 1
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Set"
                                        color: Theme.onAccent
                                        font.pixelSize: 10 * Theme.scale(Screen)
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                                    }

                                }

                                Text {
                                    text: "(Current)"
                                    visible: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === modelData.id
                                    color: Theme.accentPrimary
                                    font.pixelSize: 10 * Theme.scale(Screen)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                            }

                        }

                    }

                }

                ScrollBar.vertical: ScrollBar {
                }

            }

            // Input Devices
            Flickable {
                id: sourceList

                visible: tabIndex === 1
                contentHeight: sourceColumn.height
                clip: true
                interactive: contentHeight > height
                width: parent.width
                height: 220

                ColumnLayout {
                    id: sourceColumn

                    width: sourceList.width
                    spacing: 6

                    Repeater {
                        model: ioSelector.sourceNodes()

                        Rectangle {
                            width: parent.width
                            height: 36
                            color: "transparent"
                            radius: 6

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                Text {
                                    text: "mic"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16 * Theme.scale(Screen)
                                    color: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === modelData.id) ? Theme.accentPrimary : Theme.textPrimary
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Layout.maximumWidth: sourceList.width - 120 // Reserve space for the Set button

                                    Text {
                                        text: modelData.nickname || modelData.description || modelData.name
                                        font.bold: true
                                        font.pixelSize: 12 * Theme.scale(Screen)
                                        color: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === modelData.id) ? Theme.accentPrimary : Theme.textPrimary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.description !== modelData.nickname ? modelData.description : ""
                                        font.pixelSize: 10 * Theme.scale(Screen)
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        Layout.fillWidth: true
                                    }

                                }

                                Rectangle {
                                    visible: Pipewire.preferredDefaultAudioSource !== modelData
                                    width: 60
                                    height: 20
                                    radius: 4
                                    color: Theme.accentPrimary
                                    border.color: Theme.accentPrimary
                                    border.width: 1
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Set"
                                        color: Theme.onAccent
                                        font.pixelSize: 10 * Theme.scale(Screen)
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Pipewire.preferredDefaultAudioSource = modelData
                                    }

                                }

                                Text {
                                    text: "(Current)"
                                    visible: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === modelData.id
                                    color: Theme.accentPrimary
                                    font.pixelSize: 10 * Theme.scale(Screen)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                            }

                        }

                    }

                }

                ScrollBar.vertical: ScrollBar {
                }

            }

        }

    }

    Connections {
        function onReadyChanged() {
            if (Pipewire.ready && Pipewire.nodes && Pipewire.nodes.values) {
                for (var i = 0; i < Pipewire.nodes.values.length; ++i) {
                    var n = Pipewire.nodes.values[i];
                }
            }
        }

        function onDefaultAudioSinkChanged() {
        }

        function onDefaultAudioSourceChanged() {
        }

        target: Pipewire
    }

}

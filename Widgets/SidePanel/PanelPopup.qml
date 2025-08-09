import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow

PanelWithOverlay {
    id: sidebarPopup

    property var shell: null
    // Screen context for scaling passed down from Bar/Bar.qml
    property var screen

    function showAt() {
        sidebarPopupRect.showAt();
    }

    function hidePopup() {
        sidebarPopupRect.hidePopup();
    }

    function show() {
        sidebarPopupRect.showAt();
    }

    function dismiss() {
        sidebarPopupRect.hidePopup();
    }

    // Trigger initial weather loading when component is completed
    Component.onCompleted: {
        // Load initial weather data after a short delay to ensure all components are ready
        Qt.callLater(function() {
            if (weather && weather.fetchCityWeather)
                weather.fetchCityWeather();

        });
    }

    Rectangle {
        // Access the shell's SettingsWindow instead of creating a new one
        id: sidebarPopupRect

        property real slideOffset: width
        property bool isAnimating: false
        // Unified scale context and padding for the panel
        readonly property real scale: Theme.scale(sidebarPopup.screen)
        readonly property int padding: Math.round(16 * scale)
        readonly property int topPadding: padding
        readonly property int bottomPadding: Math.round(padding * 0.6)
        // Recording properties
        property bool isRecording: false

        function checkRecordingStatus() {
            if (isRecording)
                checkRecordingProcess.running = true;

        }

        function showAt() {
            if (!sidebarPopup.visible) {
                sidebarPopup.visible = true;
                forceActiveFocus();
                slideAnim.from = width;
                slideAnim.to = 0;
                slideAnim.running = true;
                if (weather)
                    weather.startWeatherFetch();

                if (systemWidget)
                    systemWidget.panelVisible = true;

            }
        }

        function hidePopup() {
            if (shell && shell.settingsWindow && shell.settingsWindow.visible)
                shell.settingsWindow.visible = false;

            if (sidebarPopup.visible) {
                slideAnim.from = 0;
                slideAnim.to = width;
                slideAnim.running = true;
            }
        }

        // Start screen recording using Quickshell.execDetached
        function startRecording() {
            var currentDate = new Date();
            var hours = String(currentDate.getHours()).padStart(2, '0');
            var minutes = String(currentDate.getMinutes()).padStart(2, '0');
            var day = String(currentDate.getDate()).padStart(2, '0');
            var month = String(currentDate.getMonth() + 1).padStart(2, '0');
            var year = currentDate.getFullYear();
            var filename = hours + "-" + minutes + "-" + day + "-" + month + "-" + year + ".mp4";
            var videoPath = Settings.settings.videoPath;
            if (videoPath && !videoPath.endsWith("/"))
                videoPath += "/";

            var outputPath = videoPath + filename;
            var command = "gpu-screen-recorder -w portal" + " -f " + Settings.settings.recordingFrameRate + " -a default_output" + " -k " + Settings.settings.recordingCodec + " -ac " + Settings.settings.audioCodec + " -q " + Settings.settings.recordingQuality + " -cursor " + (Settings.settings.showCursor ? "yes" : "no") + " -cr " + Settings.settings.colorRange + " -o " + outputPath;
            Quickshell.execDetached(["sh", "-c", command]);
            isRecording = true;
        }

        // Stop recording using Quickshell.execDetached
        function stopRecording() {
            Quickshell.execDetached(["sh", "-c", "pkill -SIGINT -f 'gpu-screen-recorder.*portal'"]);
            // Optionally, force kill after a delay
            var cleanupTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 3000; running: true; repeat: false }', sidebarPopupRect);
            cleanupTimer.triggered.connect(function() {
                Quickshell.execDetached(["sh", "-c", "pkill -9 -f 'gpu-screen-recorder.*portal' 2>/dev/null || true"]);
                cleanupTimer.destroy();
            });
            isRecording = false;
        }

        width: {
            const maxW = (screen ? screen.width : 1920) * 0.5
            const base = 420 * scale
            return Math.round(Math.min(Math.max(360 * scale, base), maxW))
        }
        height: contentCol.implicitHeight + topPadding + bottomPadding
        visible: parent.visible
        color: "transparent"
        anchors.top: parent.top
        anchors.right: parent.right
        // Clean up processes on destruction
        Component.onDestruction: {
            if (isRecording)
                stopRecording();

        }

        Process {
            id: checkRecordingProcess

            command: ["pgrep", "-f", "gpu-screen-recorder.*portal"]
            onExited: function(exitCode, exitStatus) {
                var isActuallyRecording = exitCode === 0;
                if (isRecording && !isActuallyRecording)
                    isRecording = isActuallyRecording;

            }
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
        }

        NumberAnimation {
            id: slideAnim

            target: sidebarPopupRect
            property: "slideOffset"
            duration: 300
            easing.type: Easing.OutCubic
            onStopped: {
                if (sidebarPopupRect.slideOffset === sidebarPopupRect.width) {
                    sidebarPopup.visible = false;
                    if (weather)
                        weather.stopWeatherFetch();

                    if (systemWidget)
                        systemWidget.panelVisible = false;

                }
                sidebarPopupRect.isAnimating = false;
            }
            onStarted: {
                sidebarPopupRect.isAnimating = true;
            }
        }

        Rectangle {
            id: mainRectangle

            width: sidebarPopupRect.width
            height: contentCol.implicitHeight + sidebarPopupRect.topPadding + sidebarPopupRect.bottomPadding
            x: sidebarPopupRect.slideOffset
            y: 0
            color: Theme.backgroundPrimary
            bottomLeftRadius: Math.round(20 * sidebarPopupRect.scale)

            Behavior on x {
                enabled: !sidebarPopupRect.isAnimating

                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

            }

        }

        // SettingsIcon component
        SettingsIcon {
            id: settingsModal

            onWeatherRefreshRequested: {
                if (weather && weather.fetchCityWeather)
                    weather.fetchCityWeather();

            }
        }

        Item {
            anchors.fill: mainRectangle
            Keys.onEscapePressed: sidebarPopupRect.hidePopup()

            ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.leftMargin: sidebarPopupRect.topPadding
                anchors.topMargin: sidebarPopupRect.topPadding
                anchors.rightMargin: sidebarPopupRect.topPadding
                anchors.bottomMargin: sidebarPopupRect.bottomPadding
                spacing: Math.round(8 * sidebarPopupRect.scale)

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(80 * sidebarPopupRect.scale)
                    System {
                        id: systemWidget
                        anchors.fill: parent
                        // Pass screen to enable per-monitor scaling inside
                        screen: sidebarPopup.screen
                        settingsModal: settingsModal
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(180 * sidebarPopupRect.scale)
                    Weather {
                        id: weather
                        anchors.fill: parent
                        // Weather uses Theme.scale(Screen); keep default
                    }
                }

                // Music and System Monitor row
                RowLayout {
                    spacing: Math.round(8 * sidebarPopupRect.scale)
                    Layout.fillWidth: true

                    Music {
                        screen: sidebarPopup.screen
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(250 * sidebarPopupRect.scale)
                    }

                    SystemMonitor {
                        screen: sidebarPopup.screen
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        // Size to content so it stays within its card across scales
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                    }

                }


                RowLayout {
                    spacing: Math.round(8 * sidebarPopupRect.scale)
                    Layout.fillWidth: true

                    PowerProfile {
                        screen: sidebarPopup.screen
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(70 * sidebarPopupRect.scale)
                    }

                    Shortcuts {
                        screen: sidebarPopup.screen
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(70 * sidebarPopupRect.scale)
                    }
                }

                Rectangle { height: Math.round(4 * sidebarPopupRect.scale); color: "transparent" }

            }

            Behavior on x {
                enabled: !sidebarPopupRect.isAnimating

                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

}

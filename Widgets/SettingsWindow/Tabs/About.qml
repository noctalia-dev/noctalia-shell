import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Settings

ColumnLayout {
    id: root

    property string latestVersion: "Unknown"
    property string currentVersion: "Unknown"
    property var contributors: []
    property string githubDataPath: Settings.settingsDir + "github_data.json"

    function loadFromFile() {
        const now = Date.now();
        const data = githubData;
        if (!data.timestamp || (now - data.timestamp > 3.6e+06)) {
            console.log("[About] Cache expired or missing, fetching new data from GitHub...");
            fetchFromGitHub();
            return ;
        }
        console.log("[About] Loading cached GitHub data (age: " + Math.round((now - data.timestamp) / 60000) + " minutes)");
        if (data.version)
            root.latestVersion = data.version;

        if (data.contributors)
            root.contributors = data.contributors;

    }

    function fetchFromGitHub() {
        versionProcess.running = true;
        contributorsProcess.running = true;
    }

    function saveData() {
        githubData.timestamp = Date.now();
        Qt.callLater(() => {
            githubDataFile.writeAdapter();
        });
    }

    spacing: 0
    anchors.fill: parent
    anchors.margins: 0

    Process {
        id: currentVersionProcess

        command: ["sh", "-c", "cd " + Quickshell.shellDir + " && git describe --tags --abbrev=0 2>/dev/null || echo 'Unknown'"]
        Component.onCompleted: {
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const version = text.trim();
                if (version && version !== "Unknown") {
                    root.currentVersion = version;
                } else {
                    currentVersionProcess.command = ["sh", "-c", "cd " + Quickshell.shellDir + " && cat package.json 2>/dev/null | grep '\"version\"' | cut -d'\"' -f4 || echo 'Unknown'"];
                    currentVersionProcess.running = true;
                }
            }
        }

    }

    FileView {
        id: githubDataFile

        path: root.githubDataPath
        blockLoading: true
        printErrors: true
        watchChanges: true
        onFileChanged: githubDataFile.reload()
        onLoaded: loadFromFile()
        onLoadFailed: function(error) {
            console.log("GitHub data file doesn't exist yet, creating it...");
            githubData.version = "Unknown";
            githubData.contributors = [];
            githubData.timestamp = 0;
            githubDataFile.writeAdapter();
            fetchFromGitHub();
        }
        Component.onCompleted: {
            if (path)
                reload();

        }

        JsonAdapter {
            id: githubData

            property string version: "Unknown"
            property var contributors: []
            property double timestamp: 0
        }

    }

    Process {
        id: versionProcess

        command: ["curl", "-s", "https://api.github.com/repos/Ly-sec/Noctalia/releases/latest"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.tag_name) {
                        const version = data.tag_name;
                        githubData.version = version;
                        root.latestVersion = version;
                        console.log("[About] Latest version fetched from GitHub:", version);
                    } else {
                        console.log("No tag_name in GitHub response");
                    }
                    saveData();
                } catch (e) {
                    console.error("Failed to parse version:", e);
                }
            }
        }

    }

    Process {
        id: contributorsProcess

        command: ["curl", "-s", "https://api.github.com/repos/Ly-sec/Noctalia/contributors?per_page=100"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    githubData.contributors = data || [];
                    root.contributors = githubData.contributors;
                    console.log("[About] Contributors data fetched from GitHub:", githubData.contributors.length, "contributors");
                    saveData();
                } catch (e) {
                    console.error("Failed to parse contributors:", e);
                    root.contributors = [];
                }
            }
        }

    }

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
                text: "Noctalia: quiet by design"
                font.pixelSize: 24 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignCenter
                Layout.bottomMargin: 8 * Theme.scale(screen)
            }

            Text {
                text: "It may just be another quickshell setup but it won't get in your way."
                font.pixelSize: 14 * Theme.scale(screen)
                color: Theme.textSecondary
                Layout.alignment: Qt.AlignCenter
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            GridLayout {
                Layout.alignment: Qt.AlignCenter
                columns: 2
                rowSpacing: 4
                columnSpacing: 8

                Text {
                    text: "Latest Version:"
                    font.pixelSize: 16 * Theme.scale(screen)
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignRight
                }

                Text {
                    text: root.latestVersion
                    font.pixelSize: 16 * Theme.scale(screen)
                    color: Theme.textPrimary
                    font.bold: true
                }

                Text {
                    text: "Installed Version:"
                    font.pixelSize: 16 * Theme.scale(screen)
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignRight
                }

                Text {
                    text: root.currentVersion
                    font.pixelSize: 16 * Theme.scale(screen)
                    color: Theme.textPrimary
                    font.bold: true
                }

            }

            Rectangle {
                Layout.alignment: Qt.AlignCenter
                Layout.topMargin: 8
                Layout.preferredWidth: updateText.implicitWidth + 46
                Layout.preferredHeight: 32
                radius: 20
                color: updateArea.containsMouse ? Theme.accentPrimary : "transparent"
                border.color: Theme.accentPrimary
                border.width: 1
                visible: {
                    if (root.currentVersion === "Unknown" || root.latestVersion === "Unknown")
                        return false;

                    const latest = root.latestVersion.replace("v", "").split(".");
                    const current = root.currentVersion.replace("v", "").split(".");
                    for (let i = 0; i < Math.max(latest.length, current.length); i++) {
                        const l = parseInt(latest[i] || "0");
                        const c = parseInt(current[i] || "0");
                        if (l > c)
                            return true;

                        if (l < c)
                            return false;

                    }
                    return false;
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "system_update"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 18 * Theme.scale(screen)
                        color: updateArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                    }

                    Text {
                        id: updateText

                        text: "Download latest release"
                        font.pixelSize: 14 * Theme.scale(screen)
                        color: updateArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                    }

                }

                MouseArea {
                    id: updateArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", "https://github.com/Ly-sec/Noctalia/releases/latest"]);
                    }
                }

            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 26
                Layout.bottomMargin: 18
                height: 1
                color: Theme.outline
                opacity: 0.3
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.alignment: Qt.AlignCenter
                spacing: 16

                RowLayout {
                    Layout.alignment: Qt.AlignCenter
                    spacing: 8

                    Text {
                        text: "Contributors"
                        font.pixelSize: 18 * Theme.scale(screen)
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "(" + root.contributors.length + ")"
                        font.pixelSize: 14 * Theme.scale(screen)
                        color: Theme.textSecondary
                    }

                }

                GridView {
                    id: contributorsGrid

                    Layout.leftMargin: 32
                    Layout.rightMargin: 32
                    Layout.alignment: Qt.AlignCenter
                    width: 200 * 3
                    height: 300
                    cellWidth: 200
                    cellHeight: 100
                    model: root.contributors

                    delegate: Rectangle {
                        width: contributorsGrid.cellWidth - 8
                        height: contributorsGrid.cellHeight - 4
                        radius: 20
                        color: contributorArea.containsMouse ? Theme.highlight : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12

                            Item {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40

                                Image {
                                    id: avatarImage

                                    anchors.fill: parent
                                    source: modelData.avatar_url || ""
                                    sourceSize: Qt.size(80, 80)
                                    visible: false
                                    mipmap: true
                                    smooth: true
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    cache: true
                                }

                                MultiEffect {
                                    anchors.fill: parent
                                    source: avatarImage
                                    maskEnabled: true
                                    maskSource: mask
                                }

                                Item {
                                    id: mask

                                    anchors.fill: parent
                                    layer.enabled: true
                                    visible: false

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: avatarImage.width / 2
                                    }

                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "person"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 24 * Theme.scale(screen)
                                    color: contributorArea.containsMouse ? Theme.backgroundPrimary : Theme.textPrimary
                                    visible: !avatarImage.source || avatarImage.status !== Image.Ready
                                }

                            }

                            ColumnLayout {
                                spacing: 4
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true

                                Text {
                                    text: modelData.login || "Unknown"
                                    font.pixelSize: 13 * Theme.scale(screen)
                                    color: contributorArea.containsMouse ? Theme.backgroundPrimary : Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: (modelData.contributions || 0) + " commits"
                                    font.pixelSize: 11 * Theme.scale(screen)
                                    color: contributorArea.containsMouse ? Theme.backgroundPrimary : Theme.textSecondary
                                }

                            }

                        }

                        MouseArea {
                            id: contributorArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.html_url)
                                    Quickshell.execDetached(["xdg-open", modelData.html_url]);

                            }
                        }

                    }

                }

            }

        }

    }

}

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Wayland
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Settings
import qs.Components
import qs.Helpers

Item {
    property alias panel: wifiPanelModal

    function showAt() {
        wifiPanelModal.visible = true;
        wifiLogic.refreshNetworks();
    }

    Component.onCompleted: {
        existingNetwork.running = true;
    }

    function signalIcon(signal) {
        if (signal >= 80)
            return "network_wifi";
        if (signal >= 60)
            return "network_wifi_3_bar";
        if (signal >= 40)
            return "network_wifi_2_bar";
        if (signal >= 20)
            return "network_wifi_1_bar";
        return "wifi_0_bar";
    }

    Process {
        id: existingNetwork
        running: false
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const networksMap = {};

                refreshIndicator.running = true;
                refreshIndicator.visible = true;

                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (!line)
                        continue;

                    const parts = line.split(":");
                    if (parts.length < 2) {
                        console.warn("Malformed nmcli output line:", line);
                        continue;
                    }

                    const ssid = wifiLogic.replaceQuickshell(parts[0]);
                    const type = parts[1];

                    if (ssid) {
                        networksMap[ssid] = {
                            ssid: ssid,
                            type: type
                        };
                    }
                }
                scanProcess.existingNetwork = networksMap;
                scanProcess.running = true;
            }
        }
    }

    Process {
        id: scanProcess
        running: false
        command: ["nmcli", "-t", "-f", "SSID,SECURITY,SIGNAL,IN-USE", "device", "wifi", "list"]

        property var existingNetwork

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const networksMap = {};

                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (!line)
                        continue;

                    const parts = line.split(":");
                    if (parts.length < 4) {
                        console.warn("Malformed nmcli output line:", line);
                        continue;
                    }
                    const ssid = parts[0];
                    const security = parts[1];
                    const signal = parseInt(parts[2]);
                    const inUse = parts[3] === "*";

                    if (ssid) {
                        if (!networksMap[ssid]) {
                            networksMap[ssid] = {
                                ssid: ssid,
                                security: security,
                                signal: signal,
                                connected: inUse,
                                existing: ssid in scanProcess.existingNetwork
                            };
                        } else {
                            const existingNet = networksMap[ssid];
                            if (inUse) {
                                existingNet.connected = true;
                            }
                            if (signal > existingNet.signal) {
                                existingNet.signal = signal;
                                existingNet.security = security;
                            }
                        }
                    }
                }

                
                wifiLogic.networks = networksMap;
                scanProcess.existingNetwork = {};
                refreshIndicator.running = false;
                refreshIndicator.visible = false;
            }
        }
    }

    QtObject {
        id: wifiLogic
        property var networks: {}
        property var anchorItem: null
        property real anchorX
        property real anchorY
        property string passwordPromptSsid: ""
        property string passwordInput: ""
        property bool showPasswordPrompt: false
        property string connectingSsid: ""
        property string connectStatus: ""
        property string connectStatusSsid: ""
        property string connectError: ""
        property string connectSecurity: ""
        property var pendingConnect: null
        property string detectedInterface: ""
        property string actionPanelSsid: ""

        function replaceQuickshell(ssid: string): string {
            const newName = ssid.replace("quickshell-", "");
            
            if (!ssid.startsWith("quickshell-")) {
                return newName;
            }

            if (wifiLogic.networks && newName in wifiLogic.networks) {
                console.log(`Quickshell ${newName} already exists, deleting old profile`)
                deleteProfileProcess.connName = ssid;
                deleteProfileProcess.running = true;
            }

            console.log(`Changing from ${ssid} to ${newName}`)
            renameConnectionProcess.oldName = ssid;
            renameConnectionProcess.newName = newName;
            renameConnectionProcess.running = true;

            return newName;
        }

        function disconnectNetwork(ssid) {
            const profileName = ssid;
            disconnectProfileProcess.connectionName = profileName;
            disconnectProfileProcess.running = true;
        }
        function refreshNetworks() {
            existingNetwork.running = true;
        }
        function showAt() {
            wifiPanelModal.visible = true;
            wifiLogic.refreshNetworks();
        }
        function connectNetwork(ssid, security) {
            wifiLogic.pendingConnect = {
                ssid: ssid,
                security: security,
                password: ""
            };
            wifiLogic.doConnect();
        }
        function submitPassword() {
            wifiLogic.pendingConnect = {
                ssid: wifiLogic.passwordPromptSsid,
                security: wifiLogic.connectSecurity,
                password: wifiLogic.passwordInput
            };
            wifiLogic.doConnect();
        }
        function doConnect() {
            const params = wifiLogic.pendingConnect;
            if (!params)
                return;

            wifiLogic.connectingSsid = params.ssid;


            const targetNetwork = wifiLogic.networks[params.ssid];


            if (targetNetwork && targetNetwork.existing) {

                upConnectionProcess.profileName = params.ssid;
                upConnectionProcess.running = true;
                wifiLogic.pendingConnect = null;
                return;
            }


            if (params.security && params.security !== "--") {
                getInterfaceProcess.running = true;
                return;
            }
            connectProcess.security = params.security;
            connectProcess.ssid = params.ssid;
            connectProcess.password = params.password;
            connectProcess.running = true;
            wifiLogic.pendingConnect = null;
        }
        function isSecured(security) {
            return security && security.trim() !== "" && security.trim() !== "--";
        }
    }

    
    Process {
        id: disconnectProfileProcess
        property string connectionName: ""
        running: false
        command: ["nmcli", "connection", "down", connectionName]
        onRunningChanged: {
            if (!running) {
                wifiLogic.refreshNetworks();
            }
        }
    }

    // Process to rename a connection
    Process {
        id: renameConnectionProcess
        running: false
        property string oldName: ""
        property string newName: ""
        command: ["nmcli", "connection", "modify", oldName, "connection.id", newName]

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Successfully renamed connection '" + 
                        renameConnectionProcess.oldName + "' to '" + 
                        renameConnectionProcess.newName + "'");
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && !text.toLowerCase().includes("warning")) {
                    console.error("Error renaming connection:", text);
                }
            }
        }
    }



    // Process to rename a connection
    Process {
        id: deleteProfileProcess
        running: false
        property string connName: ""
        command: ["nmcli", "connection", "delete", `'${connName}'`]

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Deleted connection '" + deleteProfileProcess.connName + "'");
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                console.error("Error deleting connection '" + deleteProfileProcess.connName + "':", text);
            }
        }
    }


    
    Process {
        id: connectProcess
        property string ssid: ""
        property string password: ""
        property string security: ""
        running: false
        onStarted: {
            refreshIndicator.running = true;
        }
        onExited: (exitCode, exitStatus) => {
            refreshIndicator.running = false;
        }
        command: {
            if (password) {
                return ["nmcli", "device", "wifi", "connect", `'${ssid}'`, "password", password];
            } else {
                return ["nmcli", "device", "wifi", "connect", `'${ssid}'`];
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                wifiLogic.connectingSsid = "";
                wifiLogic.showPasswordPrompt = false;
                wifiLogic.passwordPromptSsid = "";
                wifiLogic.passwordInput = "";
                wifiLogic.connectStatus = "success";
                wifiLogic.connectStatusSsid = connectProcess.ssid;
                wifiLogic.connectError = "";
                wifiLogic.refreshNetworks();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                wifiLogic.connectingSsid = "";
                wifiLogic.showPasswordPrompt = false;
                wifiLogic.passwordPromptSsid = "";
                wifiLogic.passwordInput = "";
                wifiLogic.connectStatus = "error";
                wifiLogic.connectStatusSsid = connectProcess.ssid;
                wifiLogic.connectError = text;
            }
        }
    }

    
    Process {
        id: getInterfaceProcess
        running: false
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; ++i) {
                    var parts = lines[i].split(":");
                    if (parts[1] === "wifi" && parts[2] !== "unavailable") {
                        wifiLogic.detectedInterface = parts[0];
                        break;
                    }
                }
                if (wifiLogic.detectedInterface) {
                    var params = wifiLogic.pendingConnect;
                    addConnectionProcess.ifname = wifiLogic.detectedInterface;
                    addConnectionProcess.ssid = params.ssid;
                    addConnectionProcess.password = params.password;
                    addConnectionProcess.profileName = params.ssid;
                    addConnectionProcess.security = params.security;
                    addConnectionProcess.running = true;
                } else {
                    wifiLogic.connectStatus = "error";
                    wifiLogic.connectStatusSsid = wifiLogic.pendingConnect.ssid;
                    wifiLogic.connectError = "No Wi-Fi interface found.";
                    wifiLogic.connectingSsid = "";
                    wifiLogic.pendingConnect = null;
                }
            }
        }
    }

    
    Process {
        id: addConnectionProcess
        property string ifname: ""
        property string ssid: ""
        property string password: ""
        property string profileName: ""
        property string security: ""
        running: false
        command: {
            var cmd = ["nmcli", "connection", "add", "type", "wifi", "ifname", ifname, "con-name", profileName, "ssid", ssid];
            if (security && security !== "--") {
                cmd.push("wifi-sec.key-mgmt");
                cmd.push("wpa-psk");
                cmd.push("wifi-sec.psk");
                cmd.push(password);
            }
            return cmd;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                upConnectionProcess.profileName = addConnectionProcess.profileName;
                upConnectionProcess.running = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                upConnectionProcess.profileName = addConnectionProcess.profileName;
                upConnectionProcess.running = true;
            }
        }
    }

    
    Process {
        id: upConnectionProcess
        property string profileName: ""
        running: false
        command: ["nmcli", "connection", "up", "id", profileName]
        stdout: StdioCollector {
            onStreamFinished: {
                wifiLogic.connectingSsid = "";
                wifiLogic.showPasswordPrompt = false;
                wifiLogic.passwordPromptSsid = "";
                wifiLogic.passwordInput = "";
                wifiLogic.connectStatus = "success";
                wifiLogic.connectStatusSsid = wifiLogic.pendingConnect ? wifiLogic.pendingConnect.ssid : "";
                wifiLogic.connectError = "";
                wifiLogic.refreshNetworks();
                wifiLogic.pendingConnect = null;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                wifiLogic.connectingSsid = "";
                wifiLogic.showPasswordPrompt = false;
                wifiLogic.passwordPromptSsid = "";
                wifiLogic.passwordInput = "";
                wifiLogic.connectStatus = "error";
                wifiLogic.connectStatusSsid = wifiLogic.pendingConnect ? wifiLogic.pendingConnect.ssid : "";
                wifiLogic.connectError = text;
                wifiLogic.pendingConnect = null;
            }
        }
    }

    
    Rectangle {
        id: wifiButton
        width: 36
        height: 36
        radius: 18
        border.color: Theme.accentPrimary
        border.width: 1
        color: wifiButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

        Text {
            anchors.centerIn: parent
            text: "wifi"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            color: wifiButtonArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            id: wifiButtonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: wifiLogic.showAt()
        }
    }

    PanelWindow {
        id: wifiPanelModal
        implicitWidth: 480
        implicitHeight: 780
        visible: false
        color: "transparent"
        anchors.top: true
        anchors.right: true
        margins.right: 0
        margins.top: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Component.onCompleted: {
            wifiLogic.refreshNetworks();
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.backgroundPrimary
            radius: 20
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Layout.preferredHeight: 48
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Text {
                        text: "wifi"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 32
                        color: Theme.accentPrimary
                    }
                    Text {
                        text: "Wi-Fi"
                        font.pixelSize: 26
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Spinner {
                        id: refreshIndicator
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        visible: false
                        running: false
                                    color: Theme.accentPrimary
            size: 22
                    }
                    IconButton {
                        id: refreshButton
                        icon: "refresh"
                        onClicked: wifiLogic.refreshNetworks()
                    }

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                        border.color: Theme.accentPrimary
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                            font.pixelSize: 20
                            color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                        }
                        MouseArea {
                            id: closeButtonArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: wifiPanelModal.visible = false
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.outline
                    opacity: 0.12
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 640
                    Layout.alignment: Qt.AlignHCenter
                    Layout.margins: 0
                    color: Theme.surfaceVariant
                    radius: 18
                    border.color: Theme.outline
                    border.width: 1
                    Rectangle {
                        id: bg
                        anchors.fill: parent
                        color: Theme.backgroundPrimary
                        radius: 12
                        border.width: 1
                        border.color: Theme.surfaceVariant
                        z: 0
                    }
                    Rectangle {
                        id: header
                    }

                    Rectangle {
                        id: listContainer
                        anchors.top: header.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 24
                        color: "transparent"
                        clip: true
                        ListView {
                            id: networkListView
                            anchors.fill: parent
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            model: wifiLogic.networks ? Object.values(wifiLogic.networks) : null
                            delegate: Item {
                                id: networkEntry

                                required property var modelData
                                property var signalIcon: wifiPanel.signalIcon

                                width: parent.width
                                height: (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt ? 102 : 42) + (modelData.ssid === wifiLogic.actionPanelSsid ? 60 : 0)
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42
                                        radius: 8
                                        color: modelData.connected ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.44) : (networkMouseArea.containsMouse || (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt) ? Theme.highlight : "transparent")
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 12
                                            Text {
                                                text: signalIcon(modelData.signal)
                                                font.family: "Material Symbols Outlined"
                                                font.pixelSize: 20
                                                color: networkMouseArea.containsMouse || (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt) ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                                verticalAlignment: Text.AlignVCenter
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Text {
                                                        text: modelData.ssid || "Unknown Network"
                                                        color: networkMouseArea.containsMouse || (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt) ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textPrimary)
                                                        font.pixelSize: 14
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item {
                                                        width: 22
                                                        height: 22
                                                        visible: wifiLogic.connectStatusSsid === modelData.ssid && wifiLogic.connectStatus !== ""
                                                        RowLayout {
                                                            anchors.fill: parent
                                                            spacing: 2
                                                            Text {
                                                                visible: wifiLogic.connectStatus === "success"
                                                                text: "check_circle"
                                                                font.family: "Material Symbols Outlined"
                                                                font.pixelSize: 18
                                                                color: "#43a047"
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                            Text {
                                                                visible: wifiLogic.connectStatus === "error"
                                                                text: "error"
                                                                font.family: "Material Symbols Outlined"
                                                                font.pixelSize: 18
                                                                color: Theme.error
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: modelData.security && modelData.security !== "--" ? modelData.security : "Open"
                                                    color: networkMouseArea.containsMouse || (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt) ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: wifiLogic.connectStatusSsid === modelData.ssid && wifiLogic.connectStatus === "error" && wifiLogic.connectError.length > 0
                                                    text: wifiLogic.connectError
                                                    color: Theme.error
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }
                                            Text {
                                                visible: modelData.connected
                                                text: "connected"
                                                color: networkMouseArea.containsMouse || (modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt) ? Theme.backgroundPrimary : Theme.accentPrimary
                                                font.pixelSize: 11
                                                verticalAlignment: Text.AlignVCenter
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Item {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredHeight: 22
                                                Layout.preferredWidth: 22
                                                Spinner {
                                                    visible: wifiLogic.connectingSsid === modelData.ssid
                                                    running: wifiLogic.connectingSsid === modelData.ssid
                                                    color: Theme.accentPrimary
                                                    anchors.centerIn: parent
                                                    size: 22
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: networkMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                        
                                                if (wifiLogic.actionPanelSsid === modelData.ssid) {
                                                    wifiLogic.actionPanelSsid = ""; // Close if already open
                                                } else {
                                                    wifiLogic.actionPanelSsid = modelData.ssid; // Open for this network
                                                }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: modelData.ssid === wifiLogic.passwordPromptSsid && wifiLogic.showPasswordPrompt
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 60
                                        radius: 8
                                        color: "transparent"
                                        Layout.alignment: Qt.AlignLeft
                                        Layout.leftMargin: 32
                                        Layout.rightMargin: 32
                                        z: 2
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 8
                                                    color: "transparent"
                                                    border.color: passwordField.activeFocus ? Theme.accentPrimary : Theme.outline
                                                    border.width: 1
                                                    TextInput {
                                                        id: passwordField
                                                        anchors.fill: parent
                                                        anchors.margins: 12
                                                        text: wifiLogic.passwordInput
                                                        font.pixelSize: 13
                                                        color: Theme.textPrimary
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        clip: true
                                                        focus: true
                                                        selectByMouse: true
                                                        activeFocusOnTab: true
                                                        inputMethodHints: Qt.ImhNone
                                                        echoMode: TextInput.Password
                                                        onTextChanged: wifiLogic.passwordInput = text
                                                        onAccepted: wifiLogic.submitPassword()
                                                        MouseArea {
                                                            id: passwordMouseArea
                                                            anchors.fill: parent
                                                            onClicked: passwordField.forceActiveFocus()
                                                        }
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 80
                                                Layout.preferredHeight: 36
                                                radius: 18
                                                color: Theme.accentPrimary
                                                border.color: Theme.accentPrimary
                                                border.width: 0
                                                opacity: 1.0
                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 100
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: wifiLogic.submitPassword()
                                                    cursorShape: Qt.PointingHandCursor
                                                    hoverEnabled: true
                                                    onEntered: parent.color = Qt.darker(Theme.accentPrimary, 1.1)
                                                    onExited: parent.color = Theme.accentPrimary
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Connect"
                                                    color: Theme.backgroundPrimary
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }
                            
                                    Rectangle {
                                        visible: modelData.ssid === wifiLogic.actionPanelSsid
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 60
                                        radius: 8
                                        color: "transparent"
                                        Layout.alignment: Qt.AlignLeft
                                        Layout.leftMargin: 32
                                        Layout.rightMargin: 32
                                        z: 2
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10
                                
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                visible: wifiLogic.isSecured(modelData.security) && !modelData.connected && !modelData.existing
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 8
                                                    color: "transparent"
                                                    border.color: actionPanelPasswordField.activeFocus ? Theme.accentPrimary : Theme.outline
                                                    border.width: 1
                                                    TextInput {
                                                        id: actionPanelPasswordField
                                                        anchors.fill: parent
                                                        anchors.margins: 12
                                                        font.pixelSize: 13
                                                        color: Theme.textPrimary
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        clip: true
                                                        selectByMouse: true
                                                        activeFocusOnTab: true
                                                        inputMethodHints: Qt.ImhNone
                                                        echoMode: TextInput.Password
                                                        onAccepted: {
                                                
                                                            wifiLogic.pendingConnect = {
                                                                ssid: modelData.ssid,
                                                                security: modelData.security,
                                                                password: text
                                                            };
                                                            wifiLogic.doConnect();

                                                            wifiLogic.actionPanelSsid = ""; // Close the panel
                                                        }
                                                    }
                                                }
                                            }
                                
                                            Rectangle {
                                                Layout.preferredWidth: 80
                                                Layout.preferredHeight: 36
                                                radius: 18
                                                color: modelData.connected ? Theme.error : Theme.accentPrimary
                                                border.color: modelData.connected ? Theme.error : Theme.accentPrimary
                                                border.width: 0
                                                opacity: 1.0
                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 100
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        if (modelData.connected) {
                                            
                                                            wifiLogic.disconnectNetwork(modelData.ssid);
                                                        } else {
                                            
                                                            if (wifiLogic.isSecured(modelData.security) && !modelData.existing) {
                                                
                                                                if (actionPanelPasswordField.text.length > 0) {
                                                                    wifiLogic.pendingConnect = {
                                                                        ssid: modelData.ssid,
                                                                        security: modelData.security,
                                                                        password: actionPanelPasswordField.text
                                                                    };
                                                                    wifiLogic.doConnect();
                                                                }
                                                                
                                                            } else {
                                                
                                                                wifiLogic.connectNetwork(modelData.ssid, modelData.security);
                                                            }
                                                        }
                                                        wifiLogic.actionPanelSsid = ""; // Close the panel
                                                    }
                                                    cursorShape: Qt.PointingHandCursor
                                                    hoverEnabled: true
                                                    onEntered: parent.color = modelData.connected ? Qt.darker(Theme.error, 1.1) : Qt.darker(Theme.accentPrimary, 1.1)
                                                    onExited: parent.color = modelData.connected ? Theme.error : Theme.accentPrimary
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? "wifi_off" : "check"
                                                    font.family: "Material Symbols Outlined"
                                                    font.pixelSize: 20
                                                    color: Theme.backgroundPrimary
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

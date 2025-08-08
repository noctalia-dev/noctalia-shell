import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var networks: ({})
    property string connectingSsid: ""
    property string connectStatus: ""
    property string connectStatusSsid: ""
    property string connectError: ""
    property string detectedInterface: ""

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

    function isSecured(security) {
        return security && security.trim() !== "" && security.trim() !== "--";
    }

    function refreshNetworks() {
        existingNetwork.running = true;
    }

    function connectNetwork(ssid, security) {
        pendingConnect = {
            ssid: ssid,
            security: security,
            password: ""
        };
        doConnect();
    }

    function submitPassword(ssid, password) {
        pendingConnect = {
            ssid: ssid,
            security: networks[ssid].security,
            password: password
        };
        doConnect();
    }

    function disconnectNetwork(ssid) {
        disconnectProfileProcess.connectionName = ssid;
        disconnectProfileProcess.running = true;
    }

    property var pendingConnect: null

    function doConnect() {
        const params = pendingConnect;
        if (!params)
            return;

        connectingSsid = params.ssid;
        connectStatus = "";
        connectStatusSsid = params.ssid;


        const targetNetwork = networks[params.ssid];

        if (targetNetwork && targetNetwork.existing) {
            upConnectionProcess.profileName = params.ssid;
            upConnectionProcess.running = true;
            pendingConnect = null;
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
        pendingConnect = null;
    }

    property int refreshInterval: 25000

    // Only refresh when we have an active connection
    property bool hasActiveConnection: {
        for (const net in networks) {
            if (networks[net].connected) {
                return true;
            }
        }
        return false;
    }

    property Timer refreshTimer: Timer {
        interval: root.refreshInterval
        // Only run timer when we're connected to a network
        running: root.hasActiveConnection
        repeat: true
        onTriggered: root.refreshNetworks()
    }

    // Force a refresh when menu is opened
    function onMenuOpened() {
        refreshNetworks();
    }

    function onMenuClosed() {
        // No need to do anything special on close
    }

    property Process disconnectProfileProcess: Process {
        id: disconnectProfileProcess
        property string connectionName: ""
        running: false
        command: ["nmcli", "connection", "down", connectionName]
        onRunningChanged: {
            if (!running) {
                root.refreshNetworks();
            }
        }
    }

    property Process existingNetwork: Process {
        id: existingNetwork
        running: false
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const networksMap = {};

                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (!line)
                        continue;

                    const parts = line.split(":");
                    if (parts.length < 2) {
                        console.warn("Malformed nmcli output line:", line);
                        continue;
                    }

                    const ssid = parts[0];
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

    property Process scanProcess: Process {
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

                root.networks = networksMap;
                scanProcess.existingNetwork = {};
            }
        }
    }

    property Process connectProcess: Process {
        id: connectProcess
        property string ssid: ""
        property string password: ""
        property string security: ""
        running: false
        command: {
            if (password) {
                return ["nmcli", "device", "wifi", "connect", `'${ssid}'`, "password", password];
            } else {
                return ["nmcli", "device", "wifi", "connect", `'${ssid}'`];
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.connectingSsid = "";
                root.connectStatus = "success";
                root.connectStatusSsid = connectProcess.ssid;
                root.connectError = "";
                root.refreshNetworks();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.connectingSsid = "";
                root.connectStatus = "error";
                root.connectStatusSsid = connectProcess.ssid;
                root.connectError = text;
            }
        }
    }

    property Process getInterfaceProcess: Process {
        id: getInterfaceProcess
        running: false
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; ++i) {
                    var parts = lines[i].split(":");
                    if (parts[1] === "wifi" && parts[2] !== "unavailable") {
                        root.detectedInterface = parts[0];
                        break;
                    }
                }
                if (root.detectedInterface) {
                    var params = root.pendingConnect;
                    addConnectionProcess.ifname = root.detectedInterface;
                    addConnectionProcess.ssid = params.ssid;
                    addConnectionProcess.password = params.password;
                    addConnectionProcess.profileName = params.ssid;
                    addConnectionProcess.security = params.security;
                    addConnectionProcess.running = true;
                } else {
                    root.connectStatus = "error";
                    root.connectStatusSsid = root.pendingConnect.ssid;
                    root.connectError = "No Wi-Fi interface found.";
                    root.connectingSsid = "";
                    root.pendingConnect = null;
                }
            }
        }
    }

    property Process addConnectionProcess: Process {
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

    property Process upConnectionProcess: Process {
        id: upConnectionProcess
        property string profileName: ""
        running: false
        command: ["nmcli", "connection", "up", "id", profileName]
        stdout: StdioCollector {
            onStreamFinished: {
                root.connectingSsid = "";
                root.connectStatus = "success";
                root.connectStatusSsid = root.pendingConnect ? root.pendingConnect.ssid : "";
                root.connectError = "";
                root.pendingConnect = null;
                root.refreshNetworks();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root.connectingSsid = "";
                root.connectStatus = "error";
                root.connectStatusSsid = root.pendingConnect ? root.pendingConnect.ssid : "";
                root.connectError = text;
                root.pendingConnect = null;
            }
        }
    }

    Component.onCompleted: {
        refreshNetworks();
    }
}
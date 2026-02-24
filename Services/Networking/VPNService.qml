pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property var connections: ({})
  property bool refreshing: false
  property bool connecting: false
  property bool disconnecting: false
  property string connectingUuid: ""
  property string disconnectingUuid: ""
  property string lastError: ""
  property bool refreshPending: false
  property bool importing: false
  property bool deleting: false
  property bool initialLoadDone: false

  readonly property var activeConnections: {
    const result = [];
    const map = connections;
    for (const key in map) {
      const conn = map[key];
      if (conn && conn.active) {
        result.push(conn);
      }
    }
    return result;
  }

  readonly property var inactiveConnections: {
    const result = [];
    const map = connections;
    for (const key in map) {
      const conn = map[key];
      if (conn && !conn.active) {
        result.push(conn);
      }
    }
    return result;
  }

  readonly property bool hasActiveConnection: activeConnections.length > 0

  Timer {
    id: refreshTimer
    interval: 5000
    running: true
    repeat: true
    onTriggered: refresh()
  }

  Timer {
    id: delayedRefreshTimer
    interval: 1000
    repeat: false
    onTriggered: refresh()
  }

  Component.onCompleted: {
    Logger.i("VPN", "Service started");
    refresh();
  }

  function refresh() {
    if (refreshing) {
      refreshPending = true;
      return;
    }
    refreshing = true;
    lastError = "";
    refreshProcess.running = true;
  }

  function connect(uuid) {
    if (connecting || !uuid) {
      return;
    }
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    connecting = true;
    connectingUuid = uuid;
    lastError = "";
    connectProcess.uuid = uuid;
    connectProcess.name = conn.name;
    connectProcess.running = true;
  }

  function disconnect(uuid) {
    if (disconnecting || !uuid) {
      return;
    }
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    disconnecting = true;
    disconnectingUuid = uuid;
    lastError = "";
    disconnectProcess.uuid = uuid;
    disconnectProcess.name = conn.name;
    disconnectProcess.running = true;
  }

  function toggle(uuid) {
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    if (conn.active) {
      disconnect(uuid);
    } else {
      connect(uuid);
    }
  }

  function setConnection(uuid, data) {
    if (!uuid) {
      return;
    }
    const map = Object.assign({}, connections);
    if (map[uuid]) {
      map[uuid] = Object.assign({}, map[uuid], data);
      connections = map;
    }
  }

  function importConnection(filePath) {
    if (importing || !filePath) {
      return;
    }
    importing = true;
    lastError = "";
    importProcess.filePath = filePath;
    importProcess.running = true;
  }

  function deleteConnection(uuid) {
    if (deleting || !uuid) {
      return;
    }
    const conn = connections[uuid];
    if (!conn) {
      return;
    }
    deleting = true;
    lastError = "";
    deleteProcess.uuid = uuid;
    deleteProcess.name = conn.name;
    deleteProcess.running = true;
  }

  function scheduleRefresh(interval) {
    delayedRefreshTimer.interval = interval;
    delayedRefreshTimer.restart();
  }

  Process {
    id: refreshProcess
    running: false
    command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "connection", "show"]

    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n");
        const map = {};
        for (let i = 0; i < lines.length; ++i) {
          const line = lines[i].trim();
          if (!line) {
            continue;
          }
          const lastColonIdx = line.lastIndexOf(":");
          if (lastColonIdx === -1) {
            continue;
          }
          const device = line.substring(lastColonIdx + 1);
          const remaining = line.substring(0, lastColonIdx);
          const secondLastColonIdx = remaining.lastIndexOf(":");
          if (secondLastColonIdx === -1) {
            continue;
          }
          const type = remaining.substring(secondLastColonIdx + 1);
          if (type !== "vpn" && type !== "wireguard") {
            continue;
          }
          const remaining2 = remaining.substring(0, secondLastColonIdx);
          const thirdLastColonIdx = remaining2.lastIndexOf(":");
          if (thirdLastColonIdx === -1) {
            continue;
          }
          const uuid = remaining2.substring(thirdLastColonIdx + 1);
          const name = remaining2.substring(0, thirdLastColonIdx);
          if (!uuid || !name) {
            continue;
          }
          const active = device && device !== "--";
          map[uuid] = {
            "uuid": uuid,
            "name": name,
            "type": type,
            "device": device,
            "active": active
          };
        }
        connections = map;
        const pending = refreshPending;
        refreshing = false;
        refreshPending = false;
        if (!initialLoadDone)
          initialLoadDone = true;
        if (pending) {
          scheduleRefresh(200);
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const pending = refreshPending;
        refreshing = false;
        refreshPending = false;
        if (text.trim()) {
          lastError = text.split("\n")[0].trim();
          Logger.w("VPN", "Refresh error: " + text);
        }
        if (pending) {
          scheduleRefresh(2000);
        }
      }
    }
  }

  Process {
    id: connectProcess
    property string uuid: ""
    property string name: ""
    running: false
    command: ["nmcli", "connection", "up", "uuid", uuid]

    stdout: StdioCollector {
      onStreamFinished: {
        const output = text.trim();
        if (!output) {
          return;
        }
        setConnection(connectProcess.uuid, {
                        "active": true
                      });
        connecting = false;
        connectingUuid = "";
        lastError = "";
        Logger.i("VPN", "Connected to " + connectProcess.name);
        ToastService.showNotice(connectProcess.name, I18n.tr("toast.vpn.connected", {
                                                               "name": connectProcess.name
                                                             }), "shield-lock");
        scheduleRefresh(1000);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const trimmed = text.trim();
        if (trimmed) {
          lastError = trimmed.split("\n")[0].trim();
          Logger.w("VPN", "Connect error: " + trimmed);
          ToastService.showError(I18n.tr("toast.vpn.connect-failed.title", {
                                           "name": connectProcess.name
                                         }), I18n.tr("toast.vpn.connect-failed.desc", {
                                                       "error": lastError
                                                     }));
        }
        connecting = false;
        connectingUuid = "";
      }
    }
  }

  Process {
    id: disconnectProcess
    property string uuid: ""
    property string name: ""
    running: false
    command: ["nmcli", "connection", "down", "uuid", uuid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("VPN", "Disconnected from " + disconnectProcess.name);
        setConnection(disconnectProcess.uuid, {
                        "active": false,
                        "device": ""
                      });
        disconnecting = false;
        disconnectingUuid = "";
        lastError = "";
        ToastService.showNotice(disconnectProcess.name, I18n.tr("toast.vpn.disconnected", {
                                                                  "name": disconnectProcess.name
                                                                }), "shield-off");
        scheduleRefresh(1000);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const trimmed = text.trim();
        if (trimmed) {
          lastError = trimmed.split("\n")[0].trim();
          Logger.w("VPN", "Disconnect error: " + trimmed);
          ToastService.showError(I18n.tr("toast.vpn.disconnect-failed.title", {
                                           "name": disconnectProcess.name
                                         }), I18n.tr("toast.vpn.disconnect-failed.desc", {
                                                       "error": lastError
                                                     }));
        }
        disconnecting = false;
        disconnectingUuid = "";
      }
    }
  }

  Process {
    id: importProcess
    property string filePath: ""
    running: false
    command: ["nmcli", "connection", "import", "type", filePath.endsWith(".conf") ? "wireguard" : "openvpn", "file", filePath]

    stdout: StdioCollector {
      onStreamFinished: {
        const output = text.trim();
        importing = false;
        lastError = "";
        Logger.i("VPN", "Imported connection from " + importProcess.filePath);
        const fileName = importProcess.filePath.split("/").pop();
        ToastService.showNotice(fileName, I18n.tr("toast.vpn.imported", {
                                                    "name": fileName
                                                  }), "shield-plus");
        scheduleRefresh(500);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const trimmed = text.trim();
        if (trimmed) {
          lastError = trimmed.split("\n")[0].trim();
          Logger.w("VPN", "Import error: " + trimmed);
          const fileName = importProcess.filePath.split("/").pop();
          ToastService.showError(I18n.tr("toast.vpn.import-failed.title", {
                                           "name": fileName
                                         }), I18n.tr("toast.vpn.import-failed.desc", {
                                                       "error": lastError
                                                     }));
        }
        importing = false;
      }
    }
  }

  Process {
    id: deleteProcess
    property string uuid: ""
    property string name: ""
    running: false
    command: ["nmcli", "connection", "delete", "uuid", uuid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("VPN", "Deleted connection " + deleteProcess.name);
        deleting = false;
        lastError = "";
        ToastService.showNotice(deleteProcess.name, I18n.tr("toast.vpn.deleted", {
                                                             "name": deleteProcess.name
                                                           }), "shield-x");
        scheduleRefresh(500);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        const trimmed = text.trim();
        if (trimmed) {
          lastError = trimmed.split("\n")[0].trim();
          Logger.w("VPN", "Delete error: " + trimmed);
          ToastService.showError(I18n.tr("toast.vpn.delete-failed.title", {
                                           "name": deleteProcess.name
                                         }), I18n.tr("toast.vpn.delete-failed.desc", {
                                                       "error": lastError
                                                     }));
        }
        deleting = false;
      }
    }
  }
}

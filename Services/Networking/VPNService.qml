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
  readonly property bool hasConnections: Object.keys(connections).length > 0

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
    connectProcess._stderrText = "";
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
    disconnectProcess._stderrText = "";
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
    property string _stderrText: ""
    running: false
    command: ["nmcli", "connection", "up", "uuid", uuid]

    onExited: function (exitCode) {
      if (exitCode === 0) {
        setConnection(connectProcess.uuid, {
                        "active": true
                      });
        lastError = "";
        Logger.i("VPN", "Connected to " + connectProcess.name);
        ToastService.showNotice(connectProcess.name, I18n.tr("toast.vpn.connected", {
                                                                "name": connectProcess.name
                                                              }), "shield-lock");
        scheduleRefresh(1000);
      } else {
        const errText = connectProcess._stderrText.trim();
        if (errText) {
          lastError = errText.split("\n")[0].trim();
        } else {
          lastError = "Connection failed (exit code " + exitCode + ")";
        }
        Logger.w("VPN", "Connect error (exit " + exitCode + "): " + lastError);
        ToastService.showWarning(connectProcess.name, lastError);
      }
      connecting = false;
      connectingUuid = "";
    }

    stderr: StdioCollector {
      onStreamFinished: {
        connectProcess._stderrText = text;
      }
    }
  }

  Process {
    id: disconnectProcess
    property string uuid: ""
    property string name: ""
    property string _stderrText: ""
    running: false
    command: ["nmcli", "connection", "down", "uuid", uuid]

    onExited: function (exitCode) {
      if (exitCode === 0) {
        Logger.i("VPN", "Disconnected from " + disconnectProcess.name);
        setConnection(disconnectProcess.uuid, {
                        "active": false,
                        "device": ""
                      });
        lastError = "";
        ToastService.showNotice(disconnectProcess.name, I18n.tr("toast.vpn.disconnected", {
                                                                   "name": disconnectProcess.name
                                                                 }), "shield-off");
        scheduleRefresh(1000);
      } else {
        const errText = disconnectProcess._stderrText.trim();
        if (errText) {
          lastError = errText.split("\n")[0].trim();
        } else {
          lastError = "Disconnect failed (exit code " + exitCode + ")";
        }
        Logger.w("VPN", "Disconnect error (exit " + exitCode + "): " + lastError);
        ToastService.showWarning(disconnectProcess.name, lastError);
      }
      disconnecting = false;
      disconnectingUuid = "";
    }

    stderr: StdioCollector {
      onStreamFinished: {
        disconnectProcess._stderrText = text;
      }
    }
  }
}

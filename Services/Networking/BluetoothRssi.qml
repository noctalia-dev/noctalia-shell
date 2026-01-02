import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/BluetoothUtils.js" as BluetoothUtils

QtObject {
  id: root

  // Controls
  property bool enabled: false
  property int intervalMs: 10000
  property var connectedDevices: []

  // Output cache and version for bindings
  property var cache: ({}) // addr -> percent (0..100)
  property int version: 0

  // Internal rotation state
  property int _index: 0
  property string _currentAddr: ""

  // Single process reused for RSSI queries
  property Process rssiProcess: Process {
    id: proc
    running: false
    stdout: StdioCollector {
      id: out
    }
    onExited: function (exitCode, exitStatus) {
      try {
        var text = out.text || "";
        var dbm = BluetoothUtils.parseRssiOutput(text);
        if (root._currentAddr !== "" && dbm !== null) {
          var pct = BluetoothUtils.dbmToPercent(dbm);
          if (pct !== null) {
            root.cache[root._currentAddr] = pct;
            root.version++;
          }
        }
      } catch (e) {} finally {
        root._currentAddr = "";
      }
    }
  }

  // Periodic RSSI polling timer
  property Timer rssiTimer: Timer {
    interval: root.intervalMs
    repeat: true
    running: root.enabled
    onTriggered: {
      var list = root.connectedDevices || [];
      if (!list || list.length === 0)
        return;
      if (root._index >= list.length)
        root._index = 0;
      var dev = list[root._index++];
      if (!dev)
        return;
      var addr = BluetoothUtils.macFromDevice(dev);
      if (!addr || addr.length < 7)
        return;
      if (proc.running)
        return; // avoid overlap
      root._currentAddr = addr;
      proc.command = ["sh", "-c", `bluetoothctl info "${addr}"`];
      try {
        proc.running = true;
      } catch (e) {}
    }
  }
}

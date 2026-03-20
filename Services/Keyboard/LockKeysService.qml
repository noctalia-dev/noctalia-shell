pragma Singleton

import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel 2.10
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Component registration - only poll when something needs lock key state
  function registerComponent(componentId) {
    root._registered[componentId] = true;
    root._registered = Object.assign({}, root._registered);
    Logger.d("LockKeys", "Component registered:", componentId, "- total:", root._registeredCount);
  }

  function unregisterComponent(componentId) {
    delete root._registered[componentId];
    root._registered = Object.assign({}, root._registered);
    Logger.d("LockKeys", "Component unregistered:", componentId, "- total:", root._registeredCount);
  }

  property var _registered: ({})
  readonly property int _registeredCount: Object.keys(_registered).length
  readonly property bool shouldRun: _registeredCount > 0

  property bool capsLockOn: false
  property bool numLockOn: false
  property bool scrollLockOn: false

  signal capsLockChanged(bool active)
  signal numLockChanged(bool active)
  signal scrollLockChanged(bool active)

  // Flag to track if this is the initial check to avoid OSD triggers
  property bool initialCheckDone: false

  Instantiator {
    model: FolderListModel {
      id: folderModel
      folder: Qt.resolvedUrl("/sys/class/leds")
      showFiles: false
      showOnlyReadable: true
    }
    delegate: Component {
      FileView {
        id: fileView
        path: filePath + "/brightness"
        onTextChanged: () => {
          if (!this.isWanted)
            return
          if (!this.initialCheckDone) {
            this.initialCheckDone = true
            return
          }

          var state = !this.text().startsWith("0")
          switch (fileName.split("::")[1]) {
            case "numlock":
              root.numLockOn = state
              root.numLockChanged(state)
              Logger.i("LockKeysService", "Num Lock:", state, this.path);
              break
            case "capslock":
              root.capsLockOn = state
              root.capsLockChanged(state)
              Logger.i("LockKeysService", "Caps Lock:", state, this.path);
              break
            case "scrolllock":
              root.scrollLockOn = state
              root.scrollLockChanged(state)
              Logger.i("LockKeysService", "Scroll Lock:", state, this.path);
              break
          }
        }

        // FolderListModel only provides filters for file names, not folders
        property bool isWanted: {
          if (fileName.startsWith("input") && fileName.includes("::")) {
            switch (fileName.split("::")[1]) {
              case "numlock":
              case "capslock":
              case "scrolllock":
                return true
            }
          }
          Logger.i("LockKeysService", "ignoring:", this.path);
          return false
        }

        // Skip first OSD event if one fires immediately after enabling
        property bool initialCheckDone: false
        property variant connections: Connections {
          target: root
          function onShouldRunChanged() {
            if (root.shouldRun) {
              this.initialCheckDone = false
            }
          }
        }

        // sysfs does not provide change notifications
        property variant refreshTimer: Timer {
          interval: 200
          running: root.shouldRun && fileView.isWanted
          repeat: true
          onTriggered: fileView.reload()
        }
      }
    }
  }

  Component.onCompleted: {
    Logger.i("LockKeysService", "Service started (polling deferred until a consumer registers).");
  }
}

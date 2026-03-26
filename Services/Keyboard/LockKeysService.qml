pragma Singleton
import Qt.labs.folderlistmodel 2.10
import QtQml.Models

import QtQuick
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
        // sysfs brightness can fail transiently (e.g. resume); omit console spam like other sysfs FileViews.
        printErrors: false
        watchChanges: false

        function parseBrightnessLedOn(raw) {
          var t = raw.trim();
          if (t === "" || !/^[0-9]+$/.test(t))
            return null;
          return parseInt(t, 10) !== 0;
        }

        function applyLockState(kind, state, emitIfChanged) {
          switch (kind) {
          case "numlock":
            if (emitIfChanged && root.numLockOn !== state) {
              root.numLockOn = state;
              root.numLockChanged(state);
              Logger.i("LockKeysService", "Num Lock:", state, fileView.path);
            } else if (!emitIfChanged) {
              root.numLockOn = state;
            }
            break;
          case "capslock":
            if (emitIfChanged && root.capsLockOn !== state) {
              root.capsLockOn = state;
              root.capsLockChanged(state);
              Logger.i("LockKeysService", "Caps Lock:", state, fileView.path);
            } else if (!emitIfChanged) {
              root.capsLockOn = state;
            }
            break;
          case "scrolllock":
            if (emitIfChanged && root.scrollLockOn !== state) {
              root.scrollLockOn = state;
              root.scrollLockChanged(state);
              Logger.i("LockKeysService", "Scroll Lock:", state, fileView.path);
            } else if (!emitIfChanged) {
              root.scrollLockOn = state;
            }
            break;
          }
        }

        // Only apply after a successful read — failed reloads must not update UI (empty text is not "off").
        onLoaded: {
          if (!fileView.isWanted)
          return;
          var state = fileView.parseBrightnessLedOn(fileView.text());
          if (state === null)
          return;

          var kind = fileName.split("::")[1];

          // First read after polling starts: sync bar/UI from sysfs without firing
          // *Changed signals (OSD listens to those and would flash on startup).
          if (!fileView.initialCheckDone) {
            fileView.initialCheckDone = true;
            fileView.applyLockState(kind, state, false);
            return;
          }

          fileView.applyLockState(kind, state, true);
        }

        // FolderListModel only provides filters for file names, not folders
        property bool isWanted: {
          if (fileName.startsWith("input") && fileName.includes("::")) {
            switch (fileName.split("::")[1]) {
              case "numlock":
              case "capslock":
              case "scrolllock":
              return true;
            }
          }
          return false;
        }

        // After shouldRun becomes true, first brightness read updates properties only (no *Changed signals).
        property bool initialCheckDone: false
        property variant connections: Connections {
          target: root
          function onShouldRunChanged() {
            if (root.shouldRun) {
              fileView.initialCheckDone = false;
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

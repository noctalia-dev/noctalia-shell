import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Control
import qs.Services.UI

Item {
  id: root

  // Registry to store references to active custom buttons by their user-defined identifier
  property var customButtonRegistry: ({})

  Component.onCompleted: {
    Logger.i("CustomButtonIPCService", "Service started");

    // Make this service globally accessible
    if (typeof Qt !== 'undefined' && Qt && Qt.application) {
      Qt.application.customButtonIPCService = root;
    }
  }

  // Register a custom button instance
  function registerButton(button) {
    if (!button || !button.ipcIdentifier) {
      Logger.w("CustomButtonIPCService", "Cannot register button without ipcIdentifier");
      return false;
    }

    customButtonRegistry[button.ipcIdentifier] = button;
    Logger.d("CustomButtonIPCService", `Registered button with identifier: ${button.ipcIdentifier}`);
    return true;
  }

  // Unregister a custom button instance
  function unregisterButton(button) {
    if (!button || !button.ipcIdentifier) {
      return false;
    }

    if (customButtonRegistry[button.ipcIdentifier] === button) {
      delete customButtonRegistry[button.ipcIdentifier];
      Logger.d("CustomButtonIPCService", `Unregistered button with identifier: ${button.ipcIdentifier}`);
      return true;
    }
    return false;
  }

  // Find a button by identifier
  function findButton(identifier) {
    return customButtonRegistry[identifier] || null;
  }

  // IpcHandler for custom button commands using short alias 'cb'
  IpcHandler {
    target: "cb"

    // Handle left click: cb left "identifier"
    function left(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger left click if configured
      if (button.leftClickExec || button.textCommand) {
        button.onClicked();
        Logger.i("CustomButtonIPCService", `Triggered left click on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no left click action configured`);
      }
    }

    // Handle right click: cb right "identifier"
    function right(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger right click if configured
      if (button.rightClickExec) {
        button.onRightClicked();
        Logger.i("CustomButtonIPCService", `Triggered right click on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no right click action configured`);
      }
    }

    // Handle middle click: cb middle "identifier"
    function middle(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger middle click if configured
      if (button.middleClickExec) {
        button.onMiddleClicked();
        Logger.i("CustomButtonIPCService", `Triggered middle click on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no middle click action configured`);
      }
    }

    // Handle wheel up: cb up "identifier"
    function up(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger wheel up if in separate mode and configured
      if (button.wheelMode === "separate" && button.wheelUpExec) {
        button.onWheel(1);
        Logger.i("CustomButtonIPCService", `Triggered wheel up on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no separate wheel up action configured or is not in separate mode`);
      }
    }

    // Handle wheel down: cb down "identifier"
    function down(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger wheel down if in separate mode and configured
      if (button.wheelMode === "separate" && button.wheelDownExec) {
        button.onWheel(-1);
        Logger.i("CustomButtonIPCService", `Triggered wheel down on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no separate wheel down action configured or is not in separate mode`);
      }
    }

    // Handle wheel action: cb wheel "identifier"
    function wheel(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger unified wheel if in unified mode and configured
      if (button.wheelMode === "unified" && button.wheelExec) {
        button.onWheel(1);
        Logger.i("CustomButtonIPCService", `Triggered wheel action on button '${identifier}'`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no unified wheel action configured or is not in unified mode`);
      }
    }

    // Handle refresh: cb refresh "identifier"
    function refresh(identifier: string) {
      const button = findButton(identifier);
      if (!button) {
        Logger.w("CustomButtonIPCService", `Button with identifier '${identifier}' not found`);
        return;
      }

      // Trigger text command refresh if configured and not streaming
      if (button.textCommand && button.textCommand.length > 0 && !button.textStream) {
        button.runTextCommand();
        Logger.i("CustomButtonIPCService", `Triggered refresh (text command) on button '${identifier}'`);
      } else if (button.textStream) {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' uses streaming, manual refresh disabled`);
      } else {
        Logger.w("CustomButtonIPCService", `Button '${identifier}' has no text command to refresh`);
      }
    }
  }
}

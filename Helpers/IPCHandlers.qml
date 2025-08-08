import Quickshell.Io

import "./IdleInhibitor.qml"

IpcHandler {
    property var appLauncherPanel
    property var lockScreen
    property IdleInhibitor idleInhibitor
    property var notificationPopup

    target: "globalIPC"

    function toggleIdleInhibitor(): void {
        idleInhibitor.toggle()
    }

    function toggleNotificationPopup(): void {
        console.log("[IPC] NotificationPopup toggle() called")
        // Use the global toggle function from the notification manager
        notificationPopup.togglePopup();
    }

    // Toggle Applauncher visibility
    function toggleLauncher(): void {
        if (!appLauncherPanel) {
            console.warn("AppLauncherIpcHandler: appLauncherPanel not set!");
            return;
        }
        if (appLauncherPanel.visible) {
            appLauncherPanel.hidePanel();
        } else {
            console.log("[IPC] Applauncher show() called");
            appLauncherPanel.showAt();
        }
    }

    // Toggle LockScreen
    function toggleLock(): void {
        if (!lockScreen) {
            console.warn("LockScreenIpcHandler: lockScreen not set!");
            return;
        }
        console.log("[IPC] LockScreen show() called");
        lockScreen.locked = true;
    }
}
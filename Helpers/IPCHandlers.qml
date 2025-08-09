import QtQuick
import Quickshell.Io
import qs.Bar.Modules
import qs.Helpers
import qs.Widgets.LockScreen
import qs.Widgets.Notification

Item {
    id: root

    property Applauncher appLauncherPanel
    property LockScreen lockScreen
    property IdleInhibitor idleInhibitor
    property NotificationPopup notificationPopup

    IpcHandler {
        target: "globalIPC"

        function toggleIdleInhibitor(): bool {
            root.idleInhibitor.toggle()
            return root.idleInhibitor.isRunning
        }

        function toggleNotificationPopup(): void {
            console.log("[IPC] NotificationPopup toggle() called")
            // Use the global toggle function from the notification manager
            root.notificationPopup.togglePopup();
        }

        // Toggle Applauncher visibility
        function toggleLauncher(): void {
            if (!root.appLauncherPanel) {
                console.warn("AppLauncherIpcHandler: appLauncherPanel not set!");
                return;
            }
            if (root.appLauncherPanel.visible) {
                root.appLauncherPanel.hidePanel();
            } else {
                console.log("[IPC] Applauncher show() called");
                root.appLauncherPanel.showAt();
            }
        }

        // Toggle LockScreen
        function toggleLock(): void {
            if (!root.lockScreen) {
                console.warn("LockScreenIpcHandler: lockScreen not set!");
                return;
            }
            console.log("[IPC] LockScreen show() called");
            root.lockScreen.locked = true;
        }
    }
}


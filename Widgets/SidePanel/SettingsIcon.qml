import QtQuick 
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Settings
import qs.Services
import qs.Widgets.SettingsWindow
import qs.Components

PanelWindow {
    id: settingsModal
    implicitWidth: 480 * Theme.scale(Screen)
    implicitHeight: 780 * Theme.scale(Screen)
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.right: true
    margins.right: 0
    margins.top: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Signal to request weather refresh
    signal weatherRefreshRequested()

    // Property to track the settings window instance
    property var settingsWindow: null

    // Function to open the modal and initialize temp values
    function openSettings(initialTabIndex) {        
        if (!settingsWindow) {
            // Create new window
            settingsWindow = settingsComponent.createObject(null); // No parent to avoid dependency issues
            if (settingsWindow) {
                // Set the initial tab if provided
                if (typeof initialTabIndex === 'number' && initialTabIndex >= 0 && initialTabIndex <= 8) {
                    settingsWindow.activeTabIndex = initialTabIndex;
                }
                settingsWindow.visible = true;
                
                // Show wallpaper selector if opening wallpaper tab (after window is visible)
                if (typeof initialTabIndex === 'number' && initialTabIndex === 6) {
                    Qt.callLater(function() {
                        if (settingsWindow && settingsWindow.showWallpaperSelector) {
                            settingsWindow.showWallpaperSelector();
                        }
                    }, 100); // Small delay to ensure window is fully loaded
                }
                // Handle window closure
                settingsWindow.visibleChanged.connect(function() {
                    if (settingsWindow && !settingsWindow.visible) {
                        // Trigger weather refresh when settings close
                        weatherRefreshRequested();
                        var windowToDestroy = settingsWindow;
                        settingsWindow = null;
                        windowToDestroy.destroy();
                    }
                });
            }
            sidebarPopup.dismiss();
        } else if (settingsWindow.visible) {
            // Close and destroy window
            var windowToDestroy = settingsWindow;
            settingsWindow = null;
            windowToDestroy.visible = false;
            windowToDestroy.destroy();
        }
    }

    // Function to close the modal and release focus
    function closeSettings() {
        if (settingsWindow) {
            var windowToDestroy = settingsWindow;
            settingsWindow = null;
            windowToDestroy.visible = false;
            windowToDestroy.destroy();
        }
    }

    Component {
        id: settingsComponent
        SettingsWindow {}
    }

    // Clean up on destruction
    Component.onDestruction: {
        if (settingsWindow) {
            var windowToDestroy = settingsWindow;
            settingsWindow = null;
            windowToDestroy.destroy();
        }
    }

}

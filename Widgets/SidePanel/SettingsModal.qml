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

    // Property to track the settings window instance
    property var settingsWindow: null

    // Function to open the modal and initialize temp values
    function openSettings() {        
        if (!settingsWindow) {
            // Create new window
            settingsWindow = settingsComponent.createObject(null); // No parent to avoid dependency issues
            if (settingsWindow) {
                settingsWindow.visible = true;
                // Handle window closure
                settingsWindow.visibleChanged.connect(function() {
                    if (settingsWindow && !settingsWindow.visible) {
                        var windowToDestroy = settingsWindow;
                        settingsWindow = null;
                        windowToDestroy.destroy();
                    }
                });
            }
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

    // Refresh weather data when hidden
    onVisibleChanged: {
        if (!visible && typeof weather !== 'undefined' && weather !== null && weather.fetchCityWeather) {
            weather.fetchCityWeather();
        }
    }
}

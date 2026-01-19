import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    // Logic to determine if we are in Dark Mode
    readonly property bool isDarkMode: {
        if (Settings.data.appearance && Settings.data.appearance.darkMode !== undefined)
            return Settings.data.appearance.darkMode;
        if (Settings.data.general && Settings.data.general.darkMode !== undefined)
            return Settings.data.general.darkMode;
        return true;
    }

    // The process that runs the KDE commands
    Process {
        id: plasmaThemeProcess

        // Command logic: Switch to Breeze -> Wait -> Switch to Noctalia
        // This 'blink' ensures the theme applies correctly even if KDE thinks it's already active
        command: root.isDarkMode
        ? ["sh", "-c", "plasma-apply-colorscheme BreezeDark; sleep 0.5; plasma-apply-colorscheme noctalia"]
        : ["sh", "-c", "plasma-apply-colorscheme BreezeLight; sleep 0.5; plasma-apply-colorscheme noctalia"]

        stdout: StdioCollector {
            onTextChanged: {
                if (text.trim() !== "") console.log("[ThemeSync] " + text.trim())
            }
        }

        stderr: StdioCollector {
            onTextChanged: {
                if (text.trim() !== "") console.warn("[ThemeSync Error] " + text.trim())
            }
        }
    }

    // Listen for Wallpaper changes from the service
    Connections {
        target: WallpaperService

        function onWallpaperChanged(screen, path) {
            // Avoid spamming the process if it's already running
            if (!plasmaThemeProcess.running) {
                console.log("[ThemeSync] Wallpaper changed, syncing Plasma theme...");
                plasmaThemeProcess.running = true;
            }
        }
    }

    // Also sync if the user manually toggles Dark Mode in settings
    onIsDarkModeChanged: {
        if (!plasmaThemeProcess.running) {
            console.log("[ThemeSync] Dark mode changed, syncing Plasma theme...");
            plasmaThemeProcess.running = true;
        }
    }
}

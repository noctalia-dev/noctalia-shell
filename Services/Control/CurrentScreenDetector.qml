import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

/**
* Detects which screen the cursor is currently on by creating a temporary
* invisible PanelWindow. Use withCurrentScreen() to get the screen asynchronously.
*
* Usage:
*   CurrentScreenDetector {
*     id: screenDetector
*   }
*
*   function doSomething() {
*     screenDetector.withCurrentScreen(function(screen) {
*       // screen is the ShellScreen where cursor is
*     })
*   }
*/
Item {
  id: root

  // Pending callback to execute once screen is detected
  property var pendingCallback: null

  // Detected screen
  property var detectedScreen: null

  // Signal emitted when screen is detected from the PanelWindow
  signal screenDetected(var detectedScreen)

  onScreenDetected: function (detectedScreen) {
    root.detectedScreen = detectedScreen;
    screenDetectorDebounce.restart();
  }

  /**
  * Execute callback with the screen where the cursor currently is.
  * On single-monitor setups, executes immediately.
  * On multi-monitor setups, briefly opens an invisible window to detect the screen.
  */
  function withCurrentScreen(callback: var): void {
  if (root.pendingCallback) {
    Logger.w("CurrentScreenDetector", "Another detection is pending, ignoring new call");
    return;
  }

    // Single monitor setup can execute immediately
    if (Quickshell.screens.length === 1) {
      callback(Quickshell.screens[0]);
    } else {
        // Multi-monitor setup needs async detection
        root.detectedScreen = null;
        root.pendingCallback = callback;
        screenDetectorLoader.active = true;
      }
      }

        Timer {
          id: screenDetectorDebounce
          running: false
          interval: 40
          onTriggered: {
            Logger.d("CurrentScreenDetector", "Screen debounced to:", root.detectedScreen?.name || "null");

            // Execute pending callback if any
            if (root.pendingCallback) {
              if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
                // If we explicitly disabled panels on screen without bar, check if bar is configured
                // for this screen, and fallback to primary screen if necessary
                var monitors = Settings.data.bar.monitors || [];
                const hasBar = monitors.length === 0 || monitors.includes(root.detectedScreen?.name);
                if (!hasBar) {
                  root.detectedScreen = Quickshell.screens[0];
                }
              }

              Logger.d("CurrentScreenDetector", "Executing callback on screen:", root.detectedScreen.name);
              // Store callback locally and clear pendingCallback first to prevent deadlock
              // if the callback throws an error
              var callback = root.pendingCallback;
              root.pendingCallback = null;
              try {
                callback(root.detectedScreen);
              } catch (e) {
                Logger.e("CurrentScreenDetector", "Callback failed:", e);
              }
            }

            // Clean up
            screenDetectorLoader.active = false;
          }
        }

        // Invisible dummy PanelWindow to detect which screen should receive the action
        Loader {
          id: screenDetectorLoader
          active: false

          sourceComponent: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "noctalia-screen-detector"
            mask: Region {}

            onScreenChanged: root.screenDetected(screen)
          }
        }
      }

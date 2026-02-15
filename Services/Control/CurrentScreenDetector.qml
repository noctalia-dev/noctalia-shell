import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor

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
  property bool pendingSkipBarCheck: false

  // Detected screen
  property var detectedScreen: null

  // Signal emitted when screen is detected from the PanelWindow
  signal screenDetected(var detectedScreen)

  onScreenDetected: function (detectedScreen) {
    root.detectedScreen = detectedScreen;
    screenDetectorDebounce.restart();
  }

  /**
  * Find a fallback screen that has a bar configured.
  * Prioritizes the screen at position 0x0 (likely the primary screen).
  */
  function findScreenWithBar(): var {
  const monitors = Settings.data.bar.monitors || [];
  let primaryCandidate = null;
  let firstWithBar = null;

  for (let i = 0; i < Quickshell.screens.length; i++) {
    const s = Quickshell.screens[i];
    const hasBar = monitors.length === 0 || monitors.includes(s.name);

    if (hasBar) {
      // Check if this is at 0x0 (primary position)
      if (s.x === 0 && s.y === 0) {
        primaryCandidate = s;
      }
        // Track first screen with bar as fallback
        if (!firstWithBar) {
          firstWithBar = s;
        }
        }
        }

          // Prefer primary (0x0), then first with bar, then just first screen
          return primaryCandidate || firstWithBar || Quickshell.screens[0];
        }

          /**
          * Execute callback with the screen where the cursor currently is.
          * On single-monitor setups, executes immediately.
          * On multi-monitor setups, briefly opens an invisible window to detect the screen.
          */
          function withCurrentScreen(callback: var, skipBarCheck: bool) {
          if (root.pendingCallback) {
            Logger.w("CurrentScreenDetector", "Another detection is pending, ignoring new call");
            return;
          }

            // Single monitor setup can execute immediately
            if (Quickshell.screens.length === 1) {
              callback(Quickshell.screens[0]);
              return;
            }

              // Try compositor-specific focused monitor detection first
              let screen = CompositorService.getFocusedScreen();

              if (screen) {
                // Apply the bar check if configured (skip for overlay launcher etc.)
                if (!skipBarCheck && !Settings.data.general.allowPanelsOnScreenWithoutBar) {
                  const monitors = Settings.data.bar.monitors || [];
                  const hasBar = monitors.length === 0 || monitors.includes(screen.name);
                  if (!hasBar) {
                    screen = findScreenWithBar();
                  }
                  }
                    Logger.d("CurrentScreenDetector", "Using compositor-detected screen:", screen.name);
                    callback(screen);
                    return;
                  }

                    // Fallback: Multi-monitor setup needs async detection via invisible PanelWindow
                    root.detectedScreen = null;
                    root.pendingCallback = callback;
                    root.pendingSkipBarCheck = !!skipBarCheck;
                    screenDetectorLoader.active = true;
                  }

                    Timer {
                      id: screenDetectorDebounce
                      running: false
                      interval: 40
                      onTriggered: {
                        Logger.d("CurrentScreenDetector", "Screen debounced to:", root.detectedScreen?.name || "null");

                        // Execute pending callback if any
                        if (root.pendingCallback) {
                          if (!root.pendingSkipBarCheck && !Settings.data.general.allowPanelsOnScreenWithoutBar) {
                            // If we explicitly disabled panels on screen without bar, check if bar is configured
                            // for this screen, and fallback to primary screen if necessary
                            var monitors = Settings.data.bar.monitors || [];
                            const hasBar = monitors.length === 0 || monitors.includes(root.detectedScreen?.name);
                            if (!hasBar) {
                              root.detectedScreen = findScreenWithBar();
                            }
                          }

                          Logger.d("CurrentScreenDetector", "Executing callback on screen:", root.detectedScreen.name);
                          // Store callback locally and clear pendingCallback first to prevent deadlock
                          // if the callback throws an error
                          var callback = root.pendingCallback;
                          root.pendingCallback = null;
                          root.pendingSkipBarCheck = false;
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

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons

Singleton {
    id: root

    property bool ready: false
    property var cache: ({})
    property var pending: ({})
    property var requestQueue: []  // Queue of icon names waiting for response
    property bool initialized: false
    property string currentTheme: ""  // Track current icon theme
    property bool isRestarting: false  // True when intentionally restarting (vs unexpected crash)
    
    // Signal emitted when resolver restarts (e.g., on theme change)
    signal resolverRestarted()

    Component.onCompleted: {
        // Ensure objects are initialized synchronously
        root.cache = {}
        root.pending = {}
        root.requestQueue = []
        root.initialized = true
        Logger.i("IconResolver", "Singleton created/loaded")
        
        // Get initial theme value
        root.getInitialTheme();
    }

    // Get initial icon theme from GSettings
    function getInitialTheme() {
        var initialThemeProcess = Qt.createQmlObject(`
            import QtQuick
            import Quickshell.Io
            Process {
                command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
                stdout: StdioCollector {}
            }
        `, root, "InitialThemeProcess");
        
        initialThemeProcess.exited.connect(function(exitCode) {
            if (exitCode === 0 && initialThemeProcess.stdout.text) {
                var match = initialThemeProcess.stdout.text.match(/'([^']+)'/);
                if (match && match.length > 1) {
                    root.currentTheme = match[1];
                    Logger.i("IconResolver", "Initial icon theme:", root.currentTheme);
                    // Start resolver with initial theme
                    root.startResolver();
                } else {
                    // Fallback if parsing fails
                    Logger.w("IconResolver", "Failed to parse initial theme, using default");
                    root.currentTheme = "Papirus-Dark";
                    root.startResolver();
                }
            } else {
                // Fallback if gsettings fails
                Logger.w("IconResolver", "Failed to get initial theme, using default");
                root.currentTheme = "Papirus-Dark";
                root.startResolver();
            }
            initialThemeProcess.destroy();
        });
        
        initialThemeProcess.running = true;
    }

    // GSettings monitor for icon theme changes
    property Process themeMonitorProcess: Process {
        id: themeMonitorProcess
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "icon-theme"]
        running: root.initialized
        
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!line || line.trim() === "") return
                
                // Parse: "icon-theme: 'Papirus-Dark'"
                var match = line.match(/icon-theme:\s*'([^']+)'/);
                if (match && match.length > 1) {
                    var newTheme = match[1];
                    if (newTheme !== root.currentTheme) {
                        Logger.i("IconResolver", "Icon theme changed:", root.currentTheme, "→", newTheme);
                        root.currentTheme = newTheme;
                        root.restartResolver();
                    }
                }
            }
        }
        
        onExited: {
            Logger.w("IconResolver", "Theme monitor process exited, restarting...");
            // Restart the monitor if it exits unexpectedly
            Qt.callLater(() => {
                if (themeMonitorProcess && root.initialized) {
                    themeMonitorProcess.running = true;
                }
            });
        }
    }

    // Start the resolver process with current theme
    function startResolver() {
        if (!root.currentTheme) {
            root.currentTheme = "Papirus-Dark"; // Fallback
        }
        
        // Build command with explicit QT_ICON_THEME env var
        var resolverPath = Quickshell.shellPath("Services/Icons/icon-resolver/target/release/icon-resolver");
        iconResolverProcess.command = ["sh", "-c", "env QT_ICON_THEME='" + root.currentTheme + "' " + resolverPath];
        iconResolverProcess.running = true;
    }

    // Restart resolver when theme changes
    function restartResolver() {
        Logger.i("IconResolver", "Restarting icon resolver due to theme change");
        
        // Set restarting flag so onExited knows this is intentional
        root.isRestarting = true;
        
        // Clear all JS-side caches
        root.cache = {};
        root.pending = {};
        root.requestQueue = [];
        root.ready = false;
        
        // Clear AppSearch's icon path cache as well
        if (typeof AppSearch !== 'undefined' && AppSearch.clearIconCache) {
            AppSearch.clearIconCache();
        }
        
        // Emit signal for components that need to refresh (e.g., dock)
        root.resolverRestarted();
        
        // Stop the resolver process - restart will happen in onExited
        if (iconResolverProcess && iconResolverProcess.running) {
            iconResolverProcess.running = false;
        } else {
            // Process not running, start immediately
            root.isRestarting = false;
            root.startResolver();
        }
    }

    // Helper to ensure path has file:// prefix for QML Image components
    function ensureFileUrl(path) {
        if (!path || path.length === 0) return ""
        if (path.startsWith("file://")) return path
        if (path.startsWith("/")) return "file://" + path
        return path
    }

    property Process iconResolverProcess: Process {
        id: iconResolverProcess
        // Command will be set by startResolver() with explicit QT_ICON_THEME
        running: false  // Start manually after getting initial theme
        
        Component.onCompleted: {
            Logger.i("IconResolver", "Icon resolver process component ready")
        }
        
        onStarted: {
            // Send reload request when process starts to get ready signal
            Logger.d("IconResolver", "Process started, sending reload request")
            var request = JSON.stringify({ type: "reload" });
            iconResolverProcess.write(request + "\n");
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (!data || data.trim() === "") return
                
                // Silently ignore if not initialized yet (early responses before Component.onCompleted)
                if (!root || !root.initialized) return
                try {
                    if (typeof root.cache !== "object" || root.cache === null) return
                    if (typeof root.pending !== "object" || root.pending === null) return
                    if (!Array.isArray(root.requestQueue)) return
                } catch (e) {
                    // Properties not ready yet, silently ignore
                    return
                }

                try {
                    var response = JSON.parse(data.trim())
                    if (!response) return
                    
                    if (response.path !== undefined && response.name !== undefined) {
                        // Resolve response - match by icon name from response (not queue order)
                        // This prevents mismatches when responses come back out of order
                        var iconName = response.name
                        
                        if (iconName && typeof iconName === "string") {
                            try {
                                // Remove from request queue if present (for cleanup, but not required for matching)
                                if (root.requestQueue && root.requestQueue.length > 0) {
                                    var index = root.requestQueue.indexOf(iconName)
                                    if (index !== -1) {
                                        root.requestQueue.splice(index, 1)
                                    }
                                }
                                
                                // Store in cache (store without file:// prefix)
                                root.cache[iconName] = response.path
                                Logger.d("IconResolver", "Resolved", iconName, "→", response.path)
                                
                                // Call pending callbacks with file:// prefix
                                if (root.pending[iconName] && Array.isArray(root.pending[iconName])) {
                                    var callbacks = root.pending[iconName]
                                    delete root.pending[iconName]
                                    
                                    var fileUrl = ensureFileUrl(response.path)
                                    for (var i = 0; i < callbacks.length; i++) {
                                        if (callbacks[i] && typeof callbacks[i] === "function") {
                                            callbacks[i](fileUrl)
                                        }
                                    }
                                }
                            } catch (e) {
                                // Silently ignore property access errors during initialization
                            }
                        }
                        
                        if (root && !root.ready) {
                            root.ready = true
                            Logger.i("IconResolver", "Icon resolver ready!")
                            // Process any queued requests that were waiting
                            root.processQueuedRequests()
                        }
                    } else if (response.status === "ok") {
                        // Reload response
                        var count = response.count || 0
                        Logger.i("IconResolver", "Cache reloaded, " + count + " icons cached")
                        if (root && !root.ready) {
                            root.ready = true
                            Logger.i("IconResolver", "Icon resolver ready!")
                            // Process any queued requests that were waiting
                            root.processQueuedRequests()
                        }
                    }
                } catch (e) {
                    // Silently ignore parsing/processing errors during early initialization
                    // Only log if we're past initialization phase
                    if (root && root.initialized) {
                        Logger.e("IconResolver", "Error parsing response:", e, "data:", data)
                    }
                }
            }
        }

        onExited: {
            if (root.isRestarting) {
                Logger.i("IconResolver", "Process stopped for restart")
                root.isRestarting = false
                // Restart with new theme
                Qt.callLater(() => {
                    if (iconResolverProcess) {
                        root.startResolver();
                    }
                });
            } else {
                // Unexpected exit - log error
                Logger.e("IconResolver", "Process exited unexpectedly")
                root.ready = false
            }
        }
    }

    // Resolves an icon name to a file path asynchronously
    // Parameters: iconName (string) - The icon name (e.g., "com.mitchellh.ghostty")
    //             callback (function) - Function called with the resolved path (or empty string if not found)
    function resolveIcon(iconName, callback) {
        if (!iconName || iconName.length === 0) {
            if (typeof callback === "function") {
                callback("")
            }
            return
        }

        // If in cache, return immediately (including absolute paths that were validated before)
        if (root.cache.hasOwnProperty(iconName)) {
            if (typeof callback === "function") {
                callback(ensureFileUrl(root.cache[iconName]))
            }
            return
        }

        // For absolute paths, send to Rust resolver to validate existence
        // (Rust resolver will check if file exists and return path or empty string)
        // For icon names, send to Rust resolver for theme-based lookup

        // Add callback to pending
        if (!root.pending[iconName]) {
            root.pending[iconName] = []
            // Add to request queue (only once per icon name)
            root.requestQueue.push(iconName)
            
            // Only send request if process is running and not restarting
            if (iconResolverProcess && iconResolverProcess.running && !root.isRestarting) {
                Logger.d("IconResolver", "Requesting icon:", iconName)
                var request = JSON.stringify({ type: "resolve", name: iconName })
                iconResolverProcess.write(request + "\n")
            } else {
                Logger.d("IconResolver", "Process not ready, queuing icon:", iconName)
                // Request will be sent when process becomes ready (handled in onReadyChanged or processQueuedRequests)
            }
        }
        if (callback && typeof callback === "function") {
            root.pending[iconName].push(callback)
        }
    }

    // Process queued requests that were waiting for the process to be ready
    function processQueuedRequests() {
        if (!iconResolverProcess || !iconResolverProcess.running) return
        
        // Send all pending requests
        var iconNames = Object.keys(root.pending)
        for (var i = 0; i < iconNames.length; i++) {
            var iconName = iconNames[i]
            if (iconName && !root.cache.hasOwnProperty(iconName)) {
                Logger.d("IconResolver", "Processing queued icon request:", iconName)
                var request = JSON.stringify({ type: "resolve", name: iconName })
                iconResolverProcess.write(request + "\n")
            }
        }
    }

    // Reloads the icon cache
    function reload() {
        if (!iconResolverProcess || !iconResolverProcess.running) {
            Logger.w("IconResolver", "Cannot reload: process not running")
            return
        }
        var request = JSON.stringify({ type: "reload" })
        iconResolverProcess.write(request + "\n")
    }

    // Gets cached path for an icon name (synchronous, returns empty if not cached)
    function getCachedPath(iconName) {
        if (!iconName || iconName.length === 0) return ""
        if (iconName.startsWith("/")) {
            if (iconName.startsWith("file://")) return iconName
            return "file://" + iconName
        }
        var cached = root.cache[iconName] || ""
        if (cached && cached.startsWith("/")) {
            return "file://" + cached
        }
        return cached
    }
}


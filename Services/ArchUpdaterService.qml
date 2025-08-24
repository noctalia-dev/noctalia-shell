pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io

Singleton {
    id: updateService
    
    // Core properties
    readonly property bool busy: checkupdatesProcess.running
    readonly property int updates: updatePackages.length
    property var updatePackages: []
    property var selectedPackages: []
    property int selectedPackagesCount: 0
    property bool updateInProgress: false
    
    // Process for checking updates
    Process {
        id: checkupdatesProcess
        command: ["checkupdates"]
        onExited: function(exitCode) {
            if (exitCode !== 0 && exitCode !== 2) {
                console.warn("[UpdateService] checkupdates failed (code:", exitCode, ")");
                updatePackages = [];
                return;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                parseCheckupdatesOutput(text);
            }
        }
    }
    
    // Parse checkupdates output
    function parseCheckupdatesOutput(output) {
        const lines = output.trim().split('\n').filter(line => line.trim());
        const packages = [];
        
        for (const line of lines) {
            const m = line.match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/);
            if (m) {
                packages.push({
                    name: m[1],
                    oldVersion: m[2],
                    newVersion: m[3],
                    description: `${m[1]} ${m[2]} -> ${m[3]}`
                });
            }
        }
        
        updatePackages = packages;
    }
    
    // Check for updates
    function doPoll() {
        if (busy) return;
        checkupdatesProcess.running = true;
    }
    
    // Update all packages
    function runUpdate() {
        if (updates === 0) {
            doPoll();
            return;
        }
        
        updateInProgress = true;
        Quickshell.execDetached(["pkexec", "pacman", "-Syu", "--noconfirm"]);
        
        // Refresh after updates with multiple attempts
        refreshAfterUpdate();
    }
    
    // Update selected packages
    function runSelectiveUpdate() {
        if (selectedPackages.length === 0) return;
        
        updateInProgress = true;
        const command = ["pkexec", "pacman", "-S", "--noconfirm"].concat(selectedPackages);
        Quickshell.execDetached(command);
        
        // Clear selection and refresh
        selectedPackages = [];
        selectedPackagesCount = 0;
        refreshAfterUpdate();
    }
    
    // Package selection functions
    function togglePackageSelection(packageName) {
        const index = selectedPackages.indexOf(packageName);
        if (index > -1) {
            selectedPackages.splice(index, 1);
        } else {
            selectedPackages.push(packageName);
        }
        selectedPackagesCount = selectedPackages.length;
    }
    
    function selectAllPackages() {
        selectedPackages = updatePackages.map(pkg => pkg.name);
        selectedPackagesCount = selectedPackages.length;
    }
    
    function deselectAllPackages() {
        selectedPackages = [];
        selectedPackagesCount = 0;
    }
    
    function isPackageSelected(packageName) {
        return selectedPackages.indexOf(packageName) > -1;
    }
    
    // Robust refresh after updates
    function refreshAfterUpdate() {
        // First refresh attempt after 3 seconds
        Qt.callLater(() => {
            doPoll();
        }, 3000);
        
        // Second refresh attempt after 8 seconds
        Qt.callLater(() => {
            doPoll();
        }, 8000);
        
        // Third refresh attempt after 15 seconds
        Qt.callLater(() => {
            doPoll();
            updateInProgress = false;
        }, 15000);
        
        // Final refresh attempt after 30 seconds
        Qt.callLater(() => {
            doPoll();
        }, 30000);
    }
    
    // Notification helper
    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "UpdateService", "-i", "system-software-update", title, body]);
    }
    
    // Auto-poll every 15 minutes
    Timer {
        interval: 15 * 60 * 1000 // 15 minutes
        repeat: true
        running: true
        onTriggered: doPoll()
    }
    
    // Initial check
    Component.onCompleted: doPoll()
}

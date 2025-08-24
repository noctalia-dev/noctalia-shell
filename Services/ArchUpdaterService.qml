pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io

Singleton {
    id: updateService
    property bool isArchBased: false
    property bool checkupdatesAvailable: false
    readonly property bool ready: isArchBased && checkupdatesAvailable
    readonly property bool busy: pkgProc.running
    readonly property int updates: updatePackages.length
    property var updatePackages: []
    property double lastSync: 0
    property bool lastWasFull: false
    property int failureCount: 0
    readonly property int failureThreshold: 5
    readonly property int quickTimeoutMs: 12 * 1000
    readonly property int minuteMs: 60 * 1000
    readonly property int pollInterval: 1 * minuteMs
    readonly property int syncInterval: 15 * minuteMs
    property int lastNotifiedUpdates: 0

    property var updateCommand: ["xdg-terminal-exec", "--title=System Updates", "-e", "sh", "-c", "sudo pacman -Syu; printf '\n\nUpdate finished. Press Enter to exit...'; read _"]

    PersistentProperties {
        id: cache
        reloadableId: "ArchCheckerCache"

        property string cachedUpdatePackagesJson: "[]"
        property double cachedLastSync: 0
    }

    Component.onCompleted: {
        const persisted = JSON.parse(cache.cachedUpdatePackagesJson || "[]");
        if (persisted.length)
            updatePackages = _clonePackageList(persisted);
        if (cache.cachedLastSync > 0)
            lastSync = cache.cachedLastSync;
    }

    function runUpdate() {
        if (updates > 0) {
            Quickshell.execDetached(updateCommand);
        } else {
            doPoll(true);
        }
    }

    function doPoll(forceFull = false) {
        if (busy)
            return;
        const full = forceFull || (Date.now() - lastSync > syncInterval);
        lastWasFull = full;

        pkgProc.command = full ? ["checkupdates", "--nocolor"] : ["checkupdates", "--nosync", "--nocolor"];
        pkgProc.running = true;
        killTimer.restart();
    }

    Process {
        id: pacmanCheck
        running: true
        command: ["sh", "-c", "p=$(command -v pacman >/dev/null && echo yes || echo no); c=$(command -v checkupdates >/dev/null && echo yes || echo no); echo \"$p $c\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").trim().split(/\s+/);
                updateService.isArchBased = (parts[0] === "yes");
                updateService.checkupdatesAvailable = (parts[1] === "yes");
                if (updateService.ready) {
                    updateService.doPoll();
                    pollTimer.start();
                }
            }
        }
    }

    Process {
        id: pkgProc
        onExited: function () {
            var exitCode = arguments[0];
            killTimer.stop();
            if (exitCode !== 0 && exitCode !== 2) {
                updateService.failureCount++;
                console.warn("[UpdateService] checkupdates failed (code:", exitCode, ")");
                if (updateService.failureCount >= updateService.failureThreshold) {
                    Quickshell.execDetached(["notify-send", "-a", "UpdateService", "-i", "system-software-update", String(qsTr("Update check failed")), String(qsTr(`Exit code: ${exitCode} (failed ${updateService.failureCount} times)`))]);
                    updateService.failureCount = 0;
                }
                updateService.updatePackages = [];
                return;
            }

            updateService.failureCount = 0;
            const parsed = updateService._parseUpdateOutput(out.text);
            updateService.updatePackages = parsed.pkgs;

            if (updateService.lastWasFull) {
                updateService.lastSync = Date.now();
            }

            cache.cachedUpdatePackagesJson = JSON.stringify(updateService._clonePackageList(updateService.updatePackages));
            cache.cachedLastSync = updateService.lastSync;
            updateService._summarizeAndNotify();
        }

        stdout: StdioCollector {
            id: out
        }
    }

    function _clonePackageList(list) {
        const src = Array.isArray(list) ? list : [];
        return src.map(p => ({
                    name: String(p.name || ""),
                    oldVersion: String(p.oldVersion || ""),
                    newVersion: String(p.newVersion || "")
                }));
    }

    function _parseUpdateOutput(rawText) {
        const raw = (rawText || "").trim();
        const lines = raw ? raw.split(/\r?\n/) : [];
        const pkgs = [];
        for (let i = 0; i < lines.length; ++i) {
            const m = lines[i].match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/);
            if (m) {
                pkgs.push({
                    name: m[1],
                    oldVersion: m[2],
                    newVersion: m[3]
                });
            }
        }
        return {
            raw,
            pkgs
        };
    }

    function _summarizeAndNotify() {
        if (updates === 0) {
            lastNotifiedUpdates = 0;
            return;
        }
        if (updates <= lastNotifiedUpdates)
            return;
        const added = updates - lastNotifiedUpdates;
        const msg = added === 1 ? qsTr("One new package can be upgraded (") + updates + qsTr(")") : `${added} ${qsTr("new packages can be upgraded (")} ${updates} ${qsTr(")")}`;
        if (!notifyProc.running) {
            notifyProc.command = [
                "notify-send",
                "-a", "UpdateService",
                "-i", "system-software-update",
                "-u", "normal",
                "-t", "10000",
                "-e",
                "-c", "system;updates",
                "-A", "update=Update now",
                String(qsTr("Updates Available")),
                String(msg)
            ];
            notifyProc.running = true;
        }
        lastNotifiedUpdates = updates;
    }

    Timer {
        id: pollTimer
        interval: updateService.pollInterval
        repeat: true
        onTriggered: {
            if (!updateService.ready)
                return;
            updateService.doPoll();
        }
    }

    Timer {
        id: killTimer
        interval: updateService.lastWasFull ? updateService.minuteMs : updateService.quickTimeoutMs
        repeat: false
        onTriggered: {
            if (pkgProc.running) {
                console.error("[UpdateService] Update check killed (timeout)");
                Quickshell.execDetached(["notify-send", "-a", "UpdateService", "-i", "system-software-update", String(qsTr("Update check killed")), String(qsTr("Process took too long"))]);
            }
        }
    }

    // Handles actionable notifications for updates
    Process {
        id: notifyProc
        stdout: StdioCollector {
            onStreamFinished: {
                const action = (text || "").trim();
                if (action === "update") {
                    Quickshell.execDetached(updateService.updateCommand);
                }
            }
        }
    }
}

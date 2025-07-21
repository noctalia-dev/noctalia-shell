pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Settings

Singleton {
    id: manager

    property string updateInterval: "2s"
    property string cpuUsageStr: ""
    property string cpuTempStr: ""
    property string memoryUsageStr: ""
    property string memoryUsagePerStr: ""
    property real cpuUsage: 0
    property real memoryUsage: 0
    property real cpuTemp: 0
    property real diskUsage: 0
    property real memoryUsagePer: 0
    property string diskUsageStr: ""

    Process {
        id: zigstatProcess
        running: true
        command: [Quickshell.configDir + "/Programs/zigstat", updateInterval]
        stdout: SplitParser {
            onRead: function (line) {
                try {
                    const data = JSON.parse(line);
                    cpuUsage = +data.cpu;
                    cpuTemp = +data.cputemp;
                    memoryUsage = +data.mem;
                    memoryUsagePer = +data.memper;
                    diskUsage = +data.diskper;
                    cpuUsageStr = data.cpu + "%";
                    cpuTempStr = data.cputemp + "°C";
                    memoryUsageStr = data.mem + "G";
                    memoryUsagePerStr = data.memper + "%";
                    diskUsageStr = data.diskper + "%";
                } catch (e) {
                    console.error("Failed to parse zigstat output:", e);
                }
            }
        }
    }
}
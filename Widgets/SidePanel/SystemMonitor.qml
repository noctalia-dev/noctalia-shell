import QtQuick 
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Components
import qs.Services
import qs.Settings

Rectangle {
    id: systemMonitor
    color: "transparent"

    // Track visibility state for panel integration
    property bool isVisible: false
    // Propagate screen context for Theme.scale usage
    property var screen
    readonly property real scale: Theme.scale(screen)
    readonly property int margin: Math.round(8 * scale)
    readonly property int rowSpacing: Math.round(12 * scale)
    readonly property int circleSize: Math.round(50 * scale)

    // Constrain size to keep content within card at small scales
    implicitWidth: Math.max(72, Math.round(80 * scale))
    implicitHeight: Math.max(margin * 2 + circleSize * 4 + rowSpacing * 3, Math.round(200 * scale))

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.surface
        radius: 18 * Theme.scale(screen)

        Column {
            id: gauges
            width: circleSize
            height: circleSize * 4 + rowSpacing * 3
            anchors.centerIn: parent
            spacing: rowSpacing

    
            // CPU usage indicator with circular progress bar
            Item {
                width: circleSize
                height: circleSize
                CircularProgressBar {
                    id: cpuBar
                    progress: Sysinfo.cpuUsage / 100
                    size: circleSize
                    strokeWidth: Math.max(2, Math.round(4 * scale))
                    hasNotch: true
                    notchIcon: "speed"
                    notchIconSize: Math.max(10, Math.round(14 * scale))
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: cpuBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: cpuTooltip.tooltipVisible = true
                    onExited: cpuTooltip.tooltipVisible = false
                }
                StyledTooltip {
                    id: cpuTooltip
                    text: 'CPU Usage: ' + Sysinfo.cpuUsage + '%'
                    tooltipVisible: false
                    targetItem: cpuBar
                    delay: 200
                }
            }

    
            // CPU temperature indicator with circular progress bar
            Item {
                width: circleSize; height: circleSize
                CircularProgressBar {
                    id: tempBar
                    progress: Sysinfo.cpuTemp / 100
                    size: circleSize
                    strokeWidth: Math.max(2, Math.round(4 * scale))
                    hasNotch: true
                    units: "°C"
                    notchIcon: "thermometer"
                    notchIconSize: Math.max(10, Math.round(14 * scale))
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: tempBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: tempTooltip.tooltipVisible = true
                    onExited: tempTooltip.tooltipVisible = false
                }
                StyledTooltip {
                    id: tempTooltip
                    text: 'CPU Temp: ' + Sysinfo.cpuTemp + '°C'
                    tooltipVisible: false
                    targetItem: tempBar
                    delay: 200
                }
            }

    
            // Memory usage indicator with circular progress bar
            Item {
                width: circleSize; height: circleSize
                CircularProgressBar {
                    id: memBar
                    progress: Sysinfo.memoryUsagePer / 100
                    size: circleSize
                    strokeWidth: Math.max(2, Math.round(4 * scale))
                    hasNotch: true
                    notchIcon: "memory"
                    notchIconSize: Math.max(10, Math.round(14 * scale))
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: memBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: memTooltip.tooltipVisible = true
                    onExited: memTooltip.tooltipVisible = false
                }
                StyledTooltip {
                    id: memTooltip
                    text: 'Memory Usage: ' + Sysinfo.memoryUsagePer + '% (' + Sysinfo.memoryUsageStr + ' used)'
                    tooltipVisible: false
                    targetItem: memBar
                    delay: 200
                }
            }

    
            // Disk usage indicator with circular progress bar
            Item {
                width: circleSize; height: circleSize
                CircularProgressBar {
                    id: diskBar
                    progress: Sysinfo.diskUsage / 100
                    size: circleSize
                    strokeWidth: Math.max(2, Math.round(4 * scale))
                    hasNotch: true
                    notchIcon: "storage"
                    notchIconSize: Math.max(10, Math.round(14 * scale))
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: diskBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: diskTooltip.tooltipVisible = true
                    onExited: diskTooltip.tooltipVisible = false
                }
                StyledTooltip {
                    id: diskTooltip
                    text: 'Disk Usage: ' + Sysinfo.diskUsage + '%'
                    tooltipVisible: false
                    targetItem: diskBar
                    delay: 200
                }
            }
        }
    }
} 
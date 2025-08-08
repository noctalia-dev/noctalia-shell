import QtQuick 
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Components
import qs.Services
import qs.Settings

Rectangle {
    id: systemMonitor
    width: 70 * Theme.scale(Screen)
    height: 250 * Theme.scale(Screen)
    color: "transparent"

    // Track visibility state for panel integration
    property bool isVisible: false

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.surface
        radius: 18 * Theme.scale(Screen)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8 * Theme.scale(Screen)
            spacing: 12 * Theme.scale(Screen)
            Layout.alignment: Qt.AlignVCenter

    
            // CPU usage indicator with circular progress bar
            Item {
                width: 50 * Theme.scale(Screen); height: 50 * Theme.scale(Screen)
                CircularProgressBar {
                    id: cpuBar
                    progress: Sysinfo.cpuUsage / 100
                    size: 50 * Theme.scale(Screen)
                    strokeWidth: 4 * Theme.scale(Screen)
                    hasNotch: true
                    notchIcon: "speed"
                    notchIconSize: 14 * Theme.scale(Screen)
                    Layout.alignment: Qt.AlignHCenter
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
                width: 50 * Theme.scale(Screen); height: 50 * Theme.scale(Screen)
                CircularProgressBar {
                    id: tempBar
                    progress: Sysinfo.cpuTemp / 100
                    size: 50 * Theme.scale(Screen)
                    strokeWidth: 4 * Theme.scale(Screen)
                    hasNotch: true
                    units: "°C"
                    notchIcon: "thermometer"
                    notchIconSize: 14 * Theme.scale(Screen)
                    Layout.alignment: Qt.AlignHCenter
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
                width: 50 * Theme.scale(Screen); height: 50 * Theme.scale(Screen)
                CircularProgressBar {
                    id: memBar
                    progress: Sysinfo.memoryUsagePer / 100
                    size: 50 * Theme.scale(Screen)
                    strokeWidth: 4 * Theme.scale(Screen)
                    hasNotch: true
                    notchIcon: "memory"
                    notchIconSize: 14 * Theme.scale(Screen)
                    Layout.alignment: Qt.AlignHCenter
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
                width: 50 * Theme.scale(Screen); height: 50 * Theme.scale(Screen)
                CircularProgressBar {
                    id: diskBar
                    progress: Sysinfo.diskUsage / 100
                    size: 50 * Theme.scale(Screen)
                    strokeWidth: 4 * Theme.scale(Screen)
                    hasNotch: true
                    notchIcon: "storage"
                    notchIconSize: 14 * Theme.scale(Screen)
                    Layout.alignment: Qt.AlignHCenter
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
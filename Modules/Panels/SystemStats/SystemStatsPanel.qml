import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  panelContent: Item {
    id: content
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    // Get diskPath from bar's SystemMonitor widget if available, otherwise use "/"
    readonly property string diskPath: {
      const sysMonWidget = BarService.lookupWidget("SystemMonitor");
      if (sysMonWidget && sysMonWidget.diskPath) {
        return sysMonWidget.diskPath;
      }
      return "/";
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: "device-analytics"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("system-monitor.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      // Stats Grid + Bottom section
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: statsContainer.implicitHeight + (Style.marginM * 2)

        ColumnLayout {
          id: statsContainer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Top row: 5 NCircleStat gauges
          RowLayout {
            id: topRow
            Layout.fillWidth: true
            spacing: Style.marginS

            // CPU Usage
            NCircleStat {
              id: cpuGauge
              ratio: SystemStatService.cpuUsage / 100
              icon: "cpu-usage"
              suffix: "%"
              fillColor: SystemStatService.cpuColor
              tooltipText: I18n.tr("system-monitor.cpu-usage") + `: ${Math.round(SystemStatService.cpuUsage)}%`
              Layout.fillWidth: true
            }

            // CPU Temperature
            NCircleStat {
              ratio: SystemStatService.cpuTemp / 100
              icon: "cpu-temperature"
              suffix: "\u00B0"
              fillColor: SystemStatService.tempColor
              tooltipText: I18n.tr("system-monitor.cpu-temp") + `: ${Math.round(SystemStatService.cpuTemp)}°C`
              Layout.fillWidth: true
            }

            // GPU Temperature
            NCircleStat {
              ratio: SystemStatService.gpuTemp / 100
              icon: "gpu-temperature"
              suffix: "\u00B0"
              fillColor: SystemStatService.gpuColor
              visible: SystemStatService.gpuAvailable
              tooltipText: I18n.tr("system-monitor.gpu-temp") + `: ${Math.round(SystemStatService.gpuTemp)}°C`
              Layout.fillWidth: true
            }

            // Memory Usage
            NCircleStat {
              ratio: SystemStatService.memPercent / 100
              icon: "memory"
              suffix: "%"
              fillColor: SystemStatService.memColor
              tooltipText: I18n.tr("system-monitor.memory") + `: ${Math.round(SystemStatService.memPercent)}%`
              Layout.fillWidth: true
            }

            // Disk Usage
            NCircleStat {
              ratio: (SystemStatService.diskPercents[content.diskPath] ?? 0) / 100
              icon: "storage"
              suffix: "%"
              fillColor: SystemStatService.getDiskColor(content.diskPath)
              tooltipText: I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[content.diskPath] || 0}%\n${content.diskPath}`
              Layout.fillWidth: true
            }
          }

          // Divider
          NDivider {
            Layout.fillWidth: true
          }

          // Bottom row: 2 NCircleStat (download/upload) + Detailed Stats
          RowLayout {
            id: bottomRow
            Layout.fillWidth: true
            spacing: Style.marginS

            // Download gauge (width bound to CPU gauge for alignment)
            NCircleStat {
              ratio: SystemStatService.rxRatio
              icon: "download-speed"
              suffix: "%"
              fillColor: Color.mPrimary
              tooltipText: I18n.tr("system-monitor.download") + `: ${SystemStatService.formatSpeed(SystemStatService.rxSpeed)}`
              Layout.preferredWidth: cpuGauge.width
            }

            // Upload gauge (width bound to CPU gauge for alignment)
            NCircleStat {
              ratio: SystemStatService.txRatio
              icon: "upload-speed"
              suffix: "%"
              fillColor: Color.mPrimary
              tooltipText: I18n.tr("system-monitor.upload") + `: ${SystemStatService.formatSpeed(SystemStatService.txSpeed)}`
              Layout.preferredWidth: cpuGauge.width
            }

            // Detailed Stats column
            ColumnLayout {
              id: detailsColumn
              Layout.fillWidth: true
              spacing: Style.marginS

              // Download speed
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "download-speed"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.download") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed) + "/s"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Upload speed
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "upload-speed"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.upload") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed) + "/s"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Memory details
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "memory"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.memory") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatMemoryGb(SystemStatService.memGb)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Disk details
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "storage"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.disk") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: {
                    const usedGb = SystemStatService.diskUsedGb[content.diskPath] || 0;
                    const sizeGb = SystemStatService.diskSizeGb[content.diskPath] || 0;
                    return `${usedGb.toFixed(1)}G / ${sizeGb.toFixed(1)}G`;
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }
            }
          }
        }
      }
    }
  }
}

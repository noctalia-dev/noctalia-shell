import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  readonly property real scaling: ScalingService.scale(screen)
  readonly property string tabIcon: "monitor"
  readonly property string tabLabel: "Display"
  readonly property int tabIndex: 5
  Layout.fillWidth: true
  Layout.fillHeight: true

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice()
    if (!arr.includes(name))
      arr.push(name)
    return arr
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name
    })
  }

  ScrollView {
    anchors.fill: parent
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
    contentWidth: parent.width

    ColumnLayout {
      id: contentColumn
      width: Math.max(parent.width, 300) // Minimum reasonable width without scaling

      ColumnLayout {
        spacing: Style.marginL * scaling
        Layout.margins: Style.marginL * scaling
        Layout.fillWidth: true

        NText {
          text: "Per‑monitor configuration"
          font.pointSize: Style.fontSizeXXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        NText {
          text: "By default, bars and notifications are shown on all displays. Select one or more below to narrow your view."
          font.pointSize: Style.fontSize * scaling
          color: Color.mOnSurfaceVariant
        }

        Repeater {
          model: Quickshell.screens || []
          delegate: Rectangle {
            Layout.fillWidth: true
            // Remove the scaling-based minimum width that causes issues at low scaling
            // Layout.minimumWidth: 400 * scaling
            radius: Style.radiusM * scaling
            color: Color.mSurface
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderS * scaling)
            implicitHeight: contentCol.implicitHeight + Style.marginXL * 2 * scaling

            ColumnLayout {
              id: contentCol
              anchors.fill: parent
              anchors.margins: Style.marginL * scaling
              spacing: Style.marginXXS * scaling
              Layout.minimumWidth: 0

              NText {
                text: (modelData.name || "Unknown")
                font.pointSize: Style.fontSizeXL * scaling
                font.weight: Style.fontWeightBold
                color: Color.mSecondary
              }

              NText {
                text: `Resolution: ${modelData.width}x${modelData.height} - Position: (${modelData.x}, ${modelData.y})`
                font.pointSize: Style.fontSizeXS * scaling
                color: Color.mOnSurfaceVariant
              }

              ColumnLayout {
                spacing: Style.marginL * scaling
                Layout.minimumWidth: 0
                Layout.fillWidth: true

                NToggle {
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  label: "Bar"
                  description: "Enable the bar on this monitor."
                  checked: (Settings.data.bar.monitors || []).indexOf(modelData.name) !== -1
                  onToggled: checked => {
                               if (checked) {
                                 Settings.data.bar.monitors = addMonitor(Settings.data.bar.monitors, modelData.name)
                               } else {
                                 Settings.data.bar.monitors = removeMonitor(Settings.data.bar.monitors, modelData.name)
                               }
                             }
                }

                NToggle {
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  label: "Notifications"
                  description: "Enable notifications on this monitor."
                  checked: (Settings.data.notifications.monitors || []).indexOf(modelData.name) !== -1
                  onToggled: checked => {
                               if (checked) {
                                 Settings.data.notifications.monitors = addMonitor(
                                   Settings.data.notifications.monitors, modelData.name)
                               } else {
                                 Settings.data.notifications.monitors = removeMonitor(
                                   Settings.data.notifications.monitors, modelData.name)
                               }
                             }
                }

                NToggle {
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  label: "Dock"
                  description: "Enable the dock on this monitor."
                  checked: (Settings.data.dock.monitors || []).indexOf(modelData.name) !== -1
                  onToggled: checked => {
                               if (checked) {
                                 Settings.data.dock.monitors = addMonitor(Settings.data.dock.monitors, modelData.name)
                               } else {
                                 Settings.data.dock.monitors = removeMonitor(Settings.data.dock.monitors,
                                                                             modelData.name)
                               }
                             }
                }

                ColumnLayout {
                  spacing: Style.marginL * scaling
                  Layout.fillWidth: true

                  RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                      spacing: Style.marginXXS * scaling
                      Layout.fillWidth: true
                      Layout.minimumWidth: 0

                      NText {
                        text: "Scale"
                        font.pointSize: Style.fontSizeM * scaling
                        font.weight: Style.fontWeightBold
                        color: Color.mOnSurface
                      }
                      NText {
                        text: "Scale the user interface on this monitor."
                        font.pointSize: Style.fontSizeS * scaling
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                      }
                    }

                    NText {
                      text: `${Math.round(ScalingService.scaleByName(modelData.name) * 100)}%`
                      Layout.alignment: Qt.AlignVCenter
                      Layout.minimumWidth: implicitWidth
                    }
                  }

                  RowLayout {
                    spacing: Style.marginS * scaling
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    NSlider {
                      id: scaleSlider
                      from: 0.6
                      to: 1.8
                      stepSize: 0.01
                      value: ScalingService.scaleByName(modelData.name)
                      onPressedChanged: {
                        var data = Settings.data.monitorsScaling || {}
                        data[modelData.name] = value
                        Settings.data.monitorsScaling = data
                      }
                      Layout.fillWidth: true
                      Layout.minimumWidth: 50 // Ensure minimum slider width
                    }

                    NIconButton {
                      icon: "refresh"
                      tooltipText: "Reset Scaling"
                      fontPointSize: Style.fontSizeL * scaling
                      Layout.preferredWidth: implicitWidth
                      Layout.minimumWidth: implicitWidth
                      onClicked: {
                        var data = Settings.data.monitorsScaling || {}
                        data[modelData.name] = 1.0
                        Settings.data.monitorsScaling = data
                      }
                    }
                  }
                }
              }
            }
          }
        }
        Item {
          Layout.fillHeight: true
        }
      }
    }
  }
}

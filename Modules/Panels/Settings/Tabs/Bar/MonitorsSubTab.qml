import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../Bar" as BarSettings
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var addMonitor
  property var removeMonitor

  NText {
    text: I18n.tr("panels.bar.monitors-desc-new")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Monitor cards
  Repeater {
    model: Quickshell.screens || []
    delegate: NBox {
      id: monitorCard
      Layout.fillWidth: true
      implicitHeight: cardContent.implicitHeight + Style.marginL * 2
      color: Color.mSurface

      required property var modelData
      readonly property string screenName: modelData.name || "Unknown"
      readonly property bool barEnabled: (Settings.data.bar.monitors || []).indexOf(screenName) !== -1
      readonly property bool hasOverride: Settings.hasScreenOverride(screenName)

      // Track if override is enabled (controls both visibility AND whether overrides are applied)
      readonly property bool overrideEnabled: Settings.isScreenOverrideEnabled(screenName)

      // Get effective values for this screen
      readonly property string effectivePosition: Settings.getBarPositionForScreen(screenName)
      readonly property string effectiveDensity: Settings.getBarDensityForScreen(screenName)

      ColumnLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true

          // Header: Monitor name and specs
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS

            NText {
              Layout.fillWidth: true
              text: monitorCard.screenName
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: {
                const compositorScale = CompositorService.getDisplayScale(monitorCard.screenName);
                return I18n.tr("system.monitor-description", {
                                 "model": monitorCard.modelData.model || I18n.tr("common.unknown"),
                                 "width": Math.round(monitorCard.modelData.width * compositorScale),
                                 "height": Math.round(monitorCard.modelData.height * compositorScale),
                                 "scale": compositorScale
                               });
              }
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          // Enable bar toggle
          NToggle {
            Layout.fillWidth: true
            checked: monitorCard.barEnabled
            onToggled: checked => {
                         if (checked) {
                           Settings.data.bar.monitors = root.addMonitor(Settings.data.bar.monitors, monitorCard.screenName);
                         } else {
                           Settings.data.bar.monitors = root.removeMonitor(Settings.data.bar.monitors, monitorCard.screenName);
                         }
                       }
          }
        }

        NDivider {
          Layout.fillWidth: true
          visible: Settings.data.bar.monitors.includes(monitorCard.screenName)
        }

        // Override section (only visible when bar is enabled)
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginS
          visible: monitorCard.barEnabled

          // Override toggle
          NToggle {
            Layout.fillWidth: true
            label: I18n.tr("panels.bar.monitor-override-settings")
            description: I18n.tr("panels.bar.monitor-override-settings-description")
            checked: monitorCard.overrideEnabled
            onToggled: checked => {
                         Settings.setScreenOverride(monitorCard.screenName, "enabled", checked);
                         BarService.widgetsRevision++;
                       }
          }

          // Override controls (only visible when override toggle is on)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: monitorCard.overrideEnabled

            // Position override
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NComboBox {
                Layout.fillWidth: true
                label: I18n.tr("panels.bar.appearance-position-label")
                description: I18n.tr("panels.bar.appearance-position-description")
                model: [
                  {
                    "key": "top",
                    "name": I18n.tr("positions.top")
                  },
                  {
                    "key": "bottom",
                    "name": I18n.tr("positions.bottom")
                  },
                  {
                    "key": "left",
                    "name": I18n.tr("positions.left")
                  },
                  {
                    "key": "right",
                    "name": I18n.tr("positions.right")
                  }
                ]
                currentKey: monitorCard.effectivePosition
                onSelected: key => Settings.setScreenOverride(monitorCard.screenName, "position", key)
              }
            }

            // Density override
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NComboBox {
                Layout.fillWidth: true
                label: I18n.tr("panels.bar.appearance-density-label")
                description: I18n.tr("panels.bar.appearance-density-description")
                model: [
                  {
                    "key": "mini",
                    "name": I18n.tr("options.bar.density-mini")
                  },
                  {
                    "key": "compact",
                    "name": I18n.tr("options.bar.density-compact")
                  },
                  {
                    "key": "default",
                    "name": I18n.tr("options.bar.density-default")
                  },
                  {
                    "key": "comfortable",
                    "name": I18n.tr("options.bar.density-comfortable")
                  },
                  {
                    "key": "spacious",
                    "name": I18n.tr("options.bar.density-spacious")
                  }
                ]
                currentKey: monitorCard.effectiveDensity
                onSelected: key => Settings.setScreenOverride(monitorCard.screenName, "density", key)
              }
            }

            // DisplayMode override
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NComboBox {
                Layout.fillWidth: true
                label: I18n.tr("common.display-mode")
                description: I18n.tr("panels.bar.appearance-display-mode-description")
                model: [
                  {
                    "key": "always_visible",
                    "name": I18n.tr("hide-modes.visible")
                  },
                  {
                    "key": "non_exclusive",
                    "name": I18n.tr("hide-modes.non-exclusive")
                  },
                  {
                    "key": "auto_hide",
                    "name": I18n.tr("hide-modes.auto-hide")
                  }
                ]
                currentKey: Settings.getBarDisplayModeForScreen(monitorCard.screenName)
                onSelected: key => Settings.setScreenOverride(monitorCard.screenName, "displayMode", key)
              }
            }

            // Widgets configuration button and Reset all
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NButton {
                id: widgetConfigButton
                property bool expanded: false
                Layout.fillWidth: true
                fontSize: Style.fontSizeS
                text: I18n.tr("panels.bar.monitor-configure-widgets")
                icon: expanded ? "chevron-up" : "layout-grid"
                onClicked: expanded = !expanded
              }

              NButton {
                visible: Settings.hasScreenOverride(monitorCard.screenName, "widgets")
                Layout.fillWidth: true
                fontSize: Style.fontSizeS
                text: I18n.tr("panels.bar.use-global-widgets")
                icon: "refresh"
                onClicked: {
                  Settings.clearScreenOverride(monitorCard.screenName, "widgets");
                  BarService.widgetsRevision++;
                }
              }

              NButton {
                Layout.fillWidth: true
                fontSize: Style.fontSizeS
                text: I18n.tr("panels.bar.monitor-reset-all")
                icon: "restore"
                onClicked: {
                  Settings.clearScreenOverride(monitorCard.screenName);
                  BarService.widgetsRevision++;
                }
              }
            }

            // Inline widget configuration
            BarSettings.MonitorWidgetsConfig {
              visible: widgetConfigButton.expanded
              screen: monitorCard.modelData
              Layout.fillWidth: true
              Layout.topMargin: Style.marginS
            }
          }
        }
      }
    }
  }
}

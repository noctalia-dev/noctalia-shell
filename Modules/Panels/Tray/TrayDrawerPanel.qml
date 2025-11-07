import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.MainScreen

// A compact grid panel listing all tray items, opened from the Tray widget
SmartPanel {
  id: root

  // Widget info for menu functionality
  property string widgetSection: ""
  property int widgetIndex: -1

  // Trigger refresh when settings change
  property int settingsVersion: 0

  // Read widget settings for reactivity
  readonly property var widgetSettings: {
    // Reference settingsVersion to force recalculation when it changes
    var _ = root.settingsVersion
    if (widgetSection === "" || widgetIndex < 0)
      return {}
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length)
      return {}
    var settings = widgets[widgetIndex]
    if (!settings || settings.id !== "Tray")
      return {}
    return settings
  }

  // Read favorites directly from settings for reactivity
  readonly property var favoritesList: widgetSettings.favorites || []

  function wildCardMatch(str, rule) {
    if (!str || !rule)
      return false
    let escaped = rule.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    let pattern = '^' + escaped.replace(/\\\*/g, '.*') + '$'
    try {
      return new RegExp(pattern, 'i').test(str)
    } catch (e) {
      return false
    }
  }

  function isFavorite(item) {
    if (!favoritesList || favoritesList.length === 0)
      return false
    const title = item?.tooltipTitle || item?.name || item?.id || ""
    for (var i = 0; i < favoritesList.length; i++) {
      if (wildCardMatch(title, favoritesList[i]))
        return true
    }
    return false
  }

  // Dynamic sizing based on item count
  // Show items that are NOT favorites (unpinned items go to drawer)
  readonly property var trayValuesAll: (SystemTray.items && SystemTray.items.values) ? SystemTray.items.values : []
  readonly property var trayValues: trayValuesAll.filter(function (it) {
    return !root.isFavorite(it)
  })
  readonly property int itemCount: trayValues.length
  readonly property int maxColumns: 8
  readonly property real cellSize: Math.round(Style.capsuleHeight * 0.65)
  readonly property real outerPadding: Style.marginM
  readonly property real innerSpacing: Style.marginM
  readonly property int columns: Math.max(1, Math.min(maxColumns, itemCount))
  readonly property int rows: Math.max(1, Math.ceil(itemCount / Math.max(1, columns)))

  // Add 2*gap margins around the grid
  preferredWidth: (columns * cellSize) + ((columns - 1) * innerSpacing) + (2 * outerPadding)
  preferredHeight: (rows * cellSize) + ((rows - 1) * innerSpacing) + (2 * outerPadding)

  // Positioning is handled automatically by SmartPanel when toggle(buttonItem) is called

  // Watch for settings changes to refresh the dropdown
  Connections {
    target: Settings
    function onSettingsSaved() {
      // Force refresh by incrementing settingsVersion, which triggers recalculation of favoritesList
      root.settingsVersion++
    }
  }

  panelContent: Item {
    id: content

    Grid {
      id: grid
      anchors.fill: parent
      anchors.margins: outerPadding
      spacing: innerSpacing
      columns: root.columns
      rowSpacing: innerSpacing
      columnSpacing: innerSpacing

      Repeater {
        id: repeater
        model: root.trayValues

        delegate: Item {
          width: root.cellSize
          height: root.cellSize

          IconImage {
            id: trayIcon
            anchors.fill: parent
            asynchronous: true
            backer.fillMode: Image.PreserveAspectFit
            source: {
              let icon = modelData?.icon || ""
              if (!icon)
                return ""
              if (icon.includes("?path=")) {
                const chunks = icon.split("?path=")
                const name = chunks[0]
                const path = chunks[1]
                const fileName = name.substring(name.lastIndexOf("/") + 1)
                return `file://${path}/${fileName}`
              }
              return icon
            }

            layer.enabled: root.widgetSettings.colorizeIcons !== false
            layer.effect: ShaderEffect {
              property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
              property real colorizeMode: 1.0
              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

              onClicked: mouse => {
                           if (!modelData)
                           return
                           if (mouse.button === Qt.RightButton && modelData.hasMenu && modelData.menu) {
                             const panel = PanelService.getPanel("trayMenuPanel", root.screen)
                             if (panel) {
                               panel.menu = modelData.menu
                               panel.trayItem = modelData
                               panel.widgetSection = root.widgetSection
                               panel.widgetIndex = root.widgetIndex
                               panel.openAt(trayIcon)
                             }
                           } else if (mouse.button === Qt.LeftButton) {
                             modelData.activate()
                             // Close the drawer after activation
                             PanelService.getPanel("trayDrawerPanel", root.screen)?.close()
                           } else if (mouse.button === Qt.MiddleButton) {
                             modelData.secondaryActivate()
                             PanelService.getPanel("trayDrawerPanel", root.screen)?.close()
                           }
                         }

              onWheel: wheel => {
                         if (wheel.angleDelta.y > 0)
                         modelData?.scrollUp()
                         else if (wheel.angleDelta.y < 0)
                         modelData?.scrollDown()
                       }

              onEntered: TooltipService.show(Screen, trayIcon, modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item", BarService.getTooltipDirection())
              onExited: TooltipService.hide()
            }
          }
        }
      }
    }
  }
}

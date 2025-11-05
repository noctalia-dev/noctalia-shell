import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property bool density: Settings.data.bar.density
  property real itemSize: Math.round(Style.capsuleHeight * 0.65)
  property list<string> blacklist: widgetSettings.blacklist || widgetMetadata.blacklist || [] // Read from settings
  property list<string> favorites: widgetSettings.favorites || widgetMetadata.favorites || []
  property var filteredItems: [] // Items to show inline (favorites)
  property var dropdownItems: [] // Items to show in dropdown (non-favorites)
  property string mode: widgetSettings.mode || widgetMetadata.mode || "inline" // New property for display mode

  function wildCardMatch(str, rule) {
    if (!str || !rule) {
      return false
    }
    //Logger.d("Tray", "wildCardMatch - Input str:", str, "rule:", rule)

    // Escape all special regex characters in the rule
    let escapedRule = rule.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    // Convert '*' to '.*' for wildcard matching
    let pattern = escapedRule.replace(/\\\*/g, '.*')
    // Add ^ and $ to match the entire string
    pattern = '^' + pattern + '$'

    //Logger.d("Tray", "wildCardMatch - Generated pattern:", pattern)
    try {
      const regex = new RegExp(pattern, 'i')
      // 'i' for case-insensitive
      //Logger.d("Tray", "wildCardMatch - Regex test result:", regex.test(str))
      return regex.test(str)
    } catch (e) {
      Logger.w("Tray", "Invalid regex pattern for wildcard match:", rule, e.message)
      return false // If regex is invalid, it won't match
    }
  }

  // Debounce timer for updateFilteredItems to prevent excessive calls
  // when multiple events (e.g., SystemTray changes, settings saves)
  // trigger it in rapid succession, reducing redundant processing.
  Timer {
    id: updateDebounceTimer
    interval: 100 // milliseconds
    running: false
    repeat: false
    onTriggered: _performFilteredItemsUpdate()
  }

  function _performFilteredItemsUpdate() {
    const allItems = (SystemTray.items && SystemTray.items.values) ? SystemTray.items.values : [];
    const currentMode = root.mode; // Use the new mode property

    if (currentMode === "dropdown") {
        // --- Dropdown Mode ---
        // Favorites are shown inline.
        // All other items go into the dropdown.
        // Blacklist is ignored in this mode.

        let fav = [];
        let nonFav = [];

        if (root.favorites && root.favorites.length > 0) {
            for (const item of allItems) {
                const title = item.tooltipTitle || item.name || item.id || "";
                let isFavorite = false;
                for (const rule of root.favorites) {
                    if (wildCardMatch(title, rule)) {
                        isFavorite = true;
                        break;
                    }
                }

                if (isFavorite) {
                    fav.push(item);
                } else {
                    nonFav.push(item);
                }
            }
        } else {
            // No favorites, so everything goes in the dropdown
            nonFav = allItems;
        }

        root.filteredItems = fav; // Items to show on the bar (the "pinned" favorites)
        root.dropdownItems = nonFav; // Items for the dropdown menu

    } else { // currentMode === "inline"
        // --- Inline Mode (Default) ---
        // All non-blacklisted items are shown inline.
        // Favorites list is ignored in this mode.

        let newItems = [];
        if (root.blacklist && root.blacklist.length > 0) {
            for (const item of allItems) {
                const title = item.tooltipTitle || item.name || item.id || "";
                let isBlacklisted = false;
                for (const rule of root.blacklist) {
                    if (wildCardMatch(title, rule)) {
                        isBlacklisted = true;
                        break;
                    }
                }
                if (!isBlacklisted) {
                    newItems.push(item);
                }
            }
        } else {
            // No blacklist, so show everything
            newItems = allItems;
        }

        root.filteredItems = newItems; // All non-blacklisted items shown on the bar
        root.dropdownItems = []; // No dropdown in this mode
    }
  }

  function updateFilteredItems() {
    updateDebounceTimer.restart()
  }

  function onLoaded() {// Widget initialization
  }

  Connections {
    target: SystemTray.items
    function onValuesChanged() {
      root.updateFilteredItems()
    }
  }

  Connections {
    target: Settings
    function onSettingsSaved() {
      root.updateFilteredItems()
    }
  }

  Component.onCompleted: {
    root.updateFilteredItems() // Initial update
  }

  visible: filteredItems.length > 0 || (root.mode === "dropdown" && dropdownItems.length > 0)
  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(trayFlow.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(trayFlow.implicitHeight + Style.marginM * 2) : Style.capsuleHeight
  radius: Style.radiusM
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  Layout.alignment: Qt.AlignVCenter

  Flow {
    id: trayFlow
    anchors.centerIn: parent
    spacing: Style.marginM
    flow: isVertical ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      id: repeater
      model: root.filteredItems

      delegate: Item {
        width: itemSize
        height: itemSize
        visible: modelData

        IconImage {
          id: trayIcon

          property ShellScreen screen: root.screen

          anchors.fill: parent
          asynchronous: true
          backer.fillMode: Image.PreserveAspectFit
          source: {
            let icon = modelData?.icon || ""
            if (!icon) {
              return ""
            }

            // Process icon path
            if (icon.includes("?path=")) {
              const chunks = icon.split("?path=")
              const name = chunks[0]
              const path = chunks[1]
              const fileName = name.substring(name.lastIndexOf("/") + 1)
              return `file://${path}/${fileName}`
            }
            return icon
          }
          opacity: status === Image.Ready ? 1 : 0

          layer.enabled: widgetSettings.colorizeIcons !== false
          layer.effect: ShaderEffect {
            property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
            property real colorizeMode: 1.0

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                         if (!modelData) {
                           return
                         }

                         if (mouse.button === Qt.LeftButton) {
                           // Close any open menu first
                           trayPanel.close()

                           if (!modelData.onlyMenu) {
                             modelData.activate()
                           }
                         } else if (mouse.button === Qt.MiddleButton) {
                           // Close any open menu first
                           trayPanel.close()

                           modelData.secondaryActivate && modelData.secondaryActivate()
                         } else if (mouse.button === Qt.RightButton) {
                           TooltipService.hideImmediately()

                           // Close the menu if it was visible
                           if (trayPanel && trayPanel.visible) {
                             trayPanel.close()
                             return
                           }

                           if (modelData.hasMenu && modelData.menu) {
                             const panel = PanelService.getPanel("trayMenu", root.screen)
                             if (panel) {
                               panel.menu = modelData.menu
                               panel.trayItem = modelData
                               panel.widgetSection = root.section
                               panel.widgetIndex = root.sectionWidgetIndex
                               panel.openAt(parent)
                             } else {
                               Logger.i("Tray", "TrayMenu not available")
                             }
                           } else {
                             Logger.i("Tray", "No menu available for", modelData.id, "or trayMenu not set")
                           }
                         }
                       }
            onEntered: {
              trayPanel.close()
              TooltipService.show(Screen, trayIcon, modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item", BarService.getTooltipDirection())
            }
            onExited: TooltipService.hide()
          }
        }
      }
    }

    // Dropdown opener - simple icon with hover effect
    Item {
      id: dropdownButton
      visible: root.mode === "dropdown" && dropdownItems.length > 0
      width: itemSize
      height: itemSize

      property bool hovered: false

      NIcon {
        id: chevronIcon
        anchors.centerIn: parent
        icon: {
          if (barPosition === "top")
            return "caret-down"
          else if (barPosition === "bottom")
            return "caret-up"
          else if (barPosition === "left")
            return "caret-right"
          else if (barPosition === "right")
            return "caret-left"
          else
            return "caret-down" // default fallback
        }
        pointSize: Math.round(itemSize * 0.65)
        color: dropdownButton.hovered ? Color.mPrimary : Color.mOnSurface

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutQuad
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
          dropdownButton.hovered = true
          TooltipService.show(Screen, dropdownButton, I18n.tr("tooltips.open-tray-dropdown"), BarService.getTooltipDirection())
        }
        onExited: {
          dropdownButton.hovered = false
          TooltipService.hide()
        }
        onClicked: {
          TooltipService.hideImmediately()
          const panel = PanelService.getPanel("trayDropdownPanel", root.screen)
          if (panel) {
            panel.widgetSection = root.section
            panel.widgetIndex = root.sectionWidgetIndex
            panel.toggle(dropdownButton)
          }
        }
      }
    }
  }

  PanelWindow {
    id: trayPanel
    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    visible: false
    color: Color.transparent
    screen: screen

    function open() {
      visible = true
    }

    function close() {
      visible = false
    }

    // Clicking outside of the rectangle to close
    MouseArea {
      anchors.fill: parent
      onClicked: trayPanel.close()
    }
  }
}

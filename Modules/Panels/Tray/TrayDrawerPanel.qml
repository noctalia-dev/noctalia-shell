import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.UI
import qs.Widgets

// A compact grid panel listing all tray items, opened from the Tray widget
SmartPanel {
  id: root

  // Do not give exclusive focus to the TrayDrawer or it will prevent the dropdown menu to request it.
  exclusiveKeyboard: false

  // Widget info for menu functionality (set by Tray widget when opening)
  property string widgetSection: ""
  property int widgetIndex: -1

  // Sizing properties must stay at root for preferredWidth/Height
  readonly property int maxColumns: 8
  readonly property real cellSize: Math.round(Style.capsuleHeight * 0.65)
  readonly property real outerPadding: Style.marginM
  readonly property real innerSpacing: Style.marginM

  // All tray items from SystemTray
  readonly property var trayValuesAll: (SystemTray.items && SystemTray.items.values) ? SystemTray.items.values : []

  // Filtered items - computed in panelContent where isPinned is available
  property var trayValues: []

  readonly property int itemCount: trayValues.length
  readonly property int columns: Math.max(1, Math.min(maxColumns, itemCount))
  readonly property int rows: Math.max(1, Math.ceil(itemCount / Math.max(1, columns)))

  preferredWidth: (columns * cellSize) + ((columns - 1) * innerSpacing) + (2 * outerPadding)
  preferredHeight: (rows * cellSize) + ((rows - 1) * innerSpacing) + (2 * outerPadding)

  // Auto-close drawer when all items are pinned (drawer becomes empty)
  onTrayValuesChanged: {
    if (visible && trayValues.length === 0) {
      close();
    }
  }

  // Force refresh panelContent settings when drawer opens
  onOpened: {
    if (panelContent && panelContent.settingsVersion !== undefined) {
      panelContent.settingsVersion++;
    }
  }

  panelContent: Item {
    id: panelContent

    // Settings state (lazy-loaded with panelContent)
    property int settingsVersion: 0

    readonly property var widgetSettings: {
      // Reference settingsVersion to force recalculation when it changes
      void (settingsVersion);
      if (root.widgetSection === "" || root.widgetIndex < 0)
        return {};
      var widgets = Settings.getBarWidgetsForScreen(root.screen?.name)[root.widgetSection];
      if (!widgets || root.widgetIndex >= widgets.length)
        return {};
      var settings = widgets[root.widgetIndex];
      if (!settings || settings.id !== "Tray")
        return {};
      return settings;
    }

    readonly property var pinnedList: widgetSettings.pinned || []
    readonly property bool hidePassive: widgetSettings.hidePassive !== undefined ? widgetSettings.hidePassive : true

    // Filter tray items - this runs in panelContent context where isPinned is available
    function updateFilteredItems() {
      var filtered = [];
      for (var i = 0; i < root.trayValuesAll.length; i++) {
        var item = root.trayValuesAll[i];
        if (!item)
          continue;

        // Filter out passive items if hidePassive is enabled
        if (hidePassive && item.status !== undefined && (item.status === SystemTray.Passive || item.status === 0)) {
          continue;
        }

        // Filter out pinned items
        if (isPinned(item)) {
          continue;
        }

        filtered.push(item);
      }
      root.trayValues = filtered;
    }

    // Update filtered items when dependencies change
    Component.onCompleted: updateFilteredItems()
    onPinnedListChanged: updateFilteredItems()
    onHidePassiveChanged: updateFilteredItems()

    Connections {
      target: root
      function onTrayValuesAllChanged() {
        panelContent.updateFilteredItems();
      }
    }

    // Helper functions (lazy-loaded with panelContent)
    function wildCardMatch(str, rule) {
      if (!str || !rule)
        return false;
      const placeholder = '\uE000';
      let processedRule = rule.replace(/\*/g, placeholder);
      let escaped = processedRule.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
      let pattern = '^' + escaped.replace(new RegExp(placeholder, 'g'), '.*') + '$';
      try {
        return new RegExp(pattern, 'i').test(str);
      } catch (e) {
        return false;
      }
    }

    function isPinned(item) {
      if (!pinnedList || pinnedList.length === 0)
        return false;
      const title = item?.tooltipTitle || item?.name || item?.id || "";
      for (var i = 0; i < pinnedList.length; i++) {
        if (wildCardMatch(title, pinnedList[i]))
          return true;
      }
      return false;
    }

    // Popup menu state (lazy-loaded with panelContent)
    property int popupMenuUpdateTrigger: 0

    readonly property var popupMenuWindow: {
      void (popupMenuUpdateTrigger);
      return PanelService.getPopupMenuWindow(screen);
    }

    readonly property var trayMenu: popupMenuWindow ? popupMenuWindow.trayMenuLoader : null

    // Dynamic content sizing
    property real contentPreferredWidth: (root.columns * root.cellSize) + ((root.columns - 1) * root.innerSpacing) + (2 * root.outerPadding)
    property real contentPreferredHeight: (root.rows * root.cellSize) + ((root.rows - 1) * root.innerSpacing) + (2 * root.outerPadding)

    // Connections (lazy-loaded with panelContent)
    Connections {
      target: Settings
      function onSettingsSaved() {
        panelContent.settingsVersion++;
      }
    }

    Connections {
      target: PanelService
      function onPopupMenuWindowRegistered(registeredScreen) {
        if (registeredScreen === screen) {
          panelContent.popupMenuUpdateTrigger++;
        }
      }
    }

    Grid {
      id: grid
      anchors.fill: parent
      anchors.margins: root.outerPadding
      spacing: root.innerSpacing
      columns: root.columns
      rowSpacing: root.innerSpacing
      columnSpacing: root.innerSpacing

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
              let icon = modelData?.icon || "";
              if (!icon)
                return "";
              if (icon.includes("?path=")) {
                const chunks = icon.split("?path=");
                const name = chunks[0];
                const path = chunks[1];
                const fileName = name.substring(name.lastIndexOf("/") + 1);
                return `file://${path}/${fileName}`;
              }
              return icon;
            }

            layer.enabled: panelContent.widgetSettings.colorizeIcons !== false
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
                           return;
                           if (mouse.button === Qt.LeftButton) {
                             if (!modelData.onlyMenu) {
                               modelData.activate();
                             }
                             if ((PanelService.openedPanel !== null) && !PanelService.openedPanel.isClosing) {
                               PanelService.openedPanel.close();
                             }
                           } else if (mouse.button === Qt.MiddleButton) {
                             modelData.secondaryActivate && modelData.secondaryActivate();
                             if ((PanelService.openedPanel !== null) && !PanelService.openedPanel.isClosing) {
                               PanelService.openedPanel.close();
                             }
                           } else if (mouse.button === Qt.RightButton) {
                             TooltipService.hideImmediately();

                             if (panelContent.popupMenuWindow && panelContent.popupMenuWindow.visible) {
                               panelContent.popupMenuWindow.close();
                               return;
                             }

                             if (modelData.hasMenu && modelData.menu && panelContent.trayMenu && panelContent.trayMenu.item) {
                               const barPosition = Settings.getBarPositionForScreen(root.screen?.name);
                               // Increased spacing for better alignment with other context menus
                               let menuX, menuY;

                               if (barPosition === "left") {
                                 menuX = trayIcon.width + Style.marginL;
                                 menuY = 0;
                               } else if (barPosition === "right") {
                                 menuX = -panelContent.trayMenu.item.width - Style.marginL;
                                 menuY = 0;
                               } else if (barPosition === "bottom") {
                                 // For bottom bar: let TrayMenu handle positioning by passing anchorY >= 0
                                 // TrayMenu will position above the anchor item
                                 menuX = (trayIcon.width / 2) - (panelContent.trayMenu.item.width / 2);
                                 menuY = trayIcon.height + Style.marginL;
                               } else {
                                 // For top bar: position menu below the icon with more spacing
                                 menuX = (trayIcon.width / 2) - (panelContent.trayMenu.item.width / 2);
                                 menuY = trayIcon.height + Style.marginL;
                               }

                               PanelService.showTrayMenu(root.screen, modelData, panelContent.trayMenu.item, trayIcon, menuX, menuY, root.widgetSection, root.widgetIndex);
                             }
                           }
                         }

              onWheel: wheel => {
                         if (wheel.angleDelta.y > 0)
                         modelData?.scrollUp();
                         else if (wheel.angleDelta.y < 0)
                         modelData?.scrollDown();
                       }

              onEntered: {
                if (panelContent.popupMenuWindow) {
                  panelContent.popupMenuWindow.close();
                }
                TooltipService.show(trayIcon, modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item", BarService.getTooltipDirection(root.screen?.name));
              }
              onExited: TooltipService.hide()
            }
          }
        }
      }
    }
  }
}

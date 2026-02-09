import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Trigger re-evaluation when window is registered
  property int popupMenuUpdateTrigger: 0

  // Get shared popup menu window from PanelService (reactive to trigger changes)
  readonly property var popupMenuWindow: {
    // Reference trigger to force re-evaluation
    var popupMenuUpdateTriggerRef = popupMenuUpdateTrigger;
    return PanelService.getPopupMenuWindow(screen);
  }

  readonly property var trayMenu: popupMenuWindow ? popupMenuWindow.trayMenuLoader : null

  Connections {
    target: PanelService
    function onPopupMenuWindowRegistered(registeredScreen) {
      if (registeredScreen === screen) {
        root.popupMenuUpdateTrigger++;
      }
    }
  }

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property bool density: Settings.data.bar.density
  readonly property int iconSize: Style.toOdd(capsuleHeight * 0.65)

  property var blacklist: widgetSettings.blacklist || widgetMetadata.blacklist || [] // Read from settings
  property var pinned: widgetSettings.pinned || widgetMetadata.pinned || [] // Pinned items (shown inline)
  property bool drawerEnabled: widgetSettings.drawerEnabled !== undefined ? widgetSettings.drawerEnabled : (widgetMetadata.drawerEnabled !== undefined ? widgetMetadata.drawerEnabled : true) // Enable drawer panel
  property bool hidePassive: widgetSettings.hidePassive !== undefined ? widgetSettings.hidePassive : true // Hide passive status items
  readonly property string chevronColorKey: widgetSettings.chevronColor !== undefined ? widgetSettings.chevronColor : widgetMetadata.chevronColor
  readonly property color chevronColor: Color.resolveColorKey(chevronColorKey)
  property var filteredItems: [] // Items to show inline (pinned)
  property var dropdownItems: [] // Items to show in drawer (unpinned)
  property int hoveredItemIndex: -1 // Track hovered item for dot indicator

  Timer {
    id: updateDebounceTimer
    interval: 100 // milliseconds
    running: false
    repeat: false
    onTriggered: _performFilteredItemsUpdate()
  }

  readonly property var statusSignature: {
    if (!SystemTray.items || !SystemTray.items.values) {
      return "";
    }
    var sig = "";
    var items = SystemTray.items.values;
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      if (item) {
        // Direct property access creates reactive binding
        var s = item.status;
        sig += (item.id || i) + ":" + (s !== undefined ? s : -1);
      }
    }
    // Trigger update when signature changes (status changed)
    if (root.hidePassive) {
      Qt.callLater(root.updateFilteredItems);
    }
    return sig;
  }
  Repeater {
    id: statusConnectionsRepeater
    model: SystemTray.items && SystemTray.items.values ? SystemTray.items.values : []

    delegate: Item {
      Connections {
        target: modelData
        enabled: modelData !== null && modelData !== undefined
        function onStatusChanged() {
          if (root.hidePassive) {
            root.updateFilteredItems();
          }
        }
      }
    }
  }

  function _performFilteredItemsUpdate() {
    // Force a fresh read of settings to ensure we have the latest blacklist
    var currentSettings = {};
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var w = Settings.getBarWidgetsForScreen(screenName)[section];
      if (w && sectionWidgetIndex < w.length) {
        currentSettings = w[sectionWidgetIndex];
      }
    }

    // Update local properties with fresh data
    if (currentSettings.blacklist !== undefined)
      root.blacklist = currentSettings.blacklist;
    if (currentSettings.pinned !== undefined)
      root.pinned = currentSettings.pinned;

    let newItems = [];
    if (SystemTray.items && SystemTray.items.values) {
      const trayItems = SystemTray.items.values;
      for (var i = 0; i < trayItems.length; i++) {
        const item = trayItems[i];
        if (!item) {
          continue;
        }

        const title = item.tooltipTitle || item.name || item.id || "";

        // Skip passive items if hidePassive is enabled
        if (root.hidePassive && item.status !== undefined && (item.status === SystemTray.Passive || item.status === 0)) {
          continue;
        }

        // Check if blacklisted
        let isBlacklisted = false;
        if (root.blacklist && root.blacklist.length > 0) {
          for (var j = 0; j < root.blacklist.length; j++) {
            const rule = root.blacklist[j];
            if (wildCardMatch(title, rule)) {
              isBlacklisted = true;
              break;
            }
          }
        }

        if (!isBlacklisted) {
          newItems.push(item);
        }
      }
    }

    // If drawer is disabled, show all items inline
    if (!root.drawerEnabled) {
      filteredItems = newItems;
      dropdownItems = [];
    } else {
      // Build inline (pinned) and drawer (unpinned) lists
      // If pinned list is empty, all items go to drawer (none inline)
      // If pinned list has items, pinned items are inline, rest go to drawer
      if (pinned && pinned.length > 0) {
        let pinnedItems = [];
        for (var k = 0; k < newItems.length; k++) {
          const item2 = newItems[k];
          const title2 = item2.tooltipTitle || item2.name || item2.id || "";
          for (var m = 0; m < pinned.length; m++) {
            const rule2 = pinned[m];
            if (wildCardMatch(title2, rule2)) {
              pinnedItems.push(item2);
              break;
            }
          }
        }
        filteredItems = pinnedItems;

        // Unpinned items go to drawer
        let unpinnedItems = [];
        for (var v = 0; v < newItems.length; v++) {
          const cand = newItems[v];
          let isPinned = false;
          for (var f = 0; f < filteredItems.length; f++) {
            if (filteredItems[f] === cand) {
              isPinned = true;
              break;
            }
          }
          if (!isPinned)
            unpinnedItems.push(cand);
        }
        dropdownItems = unpinnedItems;
      } else {
        // No pinned items: all items go to drawer (none inline)
        filteredItems = [];
        dropdownItems = newItems;
      }
    }
  }

  function updateFilteredItems() {
    updateDebounceTimer.restart();
  }

  function wildCardMatch(str, rule) {
    if (!str || !rule) {
      return false;
    }

    // First, convert '*' to a placeholder to preserve it, then escape other special regex characters
    // Use a unique placeholder that won't appear in normal strings
    const placeholder = '\uE000'; // Private use character
    let processedRule = rule.replace(/\*/g, placeholder);
    // Escape all special regex characters (but placeholder won't match this)
    let escapedRule = processedRule.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
    // Convert placeholder back to '.*' for wildcard matching
    let pattern = escapedRule.replace(new RegExp(placeholder, 'g'), '.*');
    // Add ^ and $ to match the entire string
    pattern = '^' + pattern + '$';

    try {
      const regex = new RegExp(pattern, 'i');
      // 'i' for case-insensitive
      return regex.test(str);
    } catch (e) {
      Logger.w("Tray", "Invalid regex pattern for wildcard match:", rule, e.message);
      return false; // If regex is invalid, it won't match
    }
  }

  function toggleDrawer(button) {
    TooltipService.hideImmediately();

    // Close the popup menu if it's open
    if (popupMenuWindow && popupMenuWindow.visible) {
      popupMenuWindow.close();
    }

    const panel = PanelService.getPanel("trayDrawerPanel", root.screen);
    if (panel) {
      panel.widgetSection = root.section;
      panel.widgetIndex = root.sectionWidgetIndex;
      panel.toggle(this);
    }
  }

  function onLoaded() {
    // When the widget is fully initialized with its props set the screen for the trayMenu
    if (trayMenu && trayMenu.item) {
      trayMenu.item.screen = screen;
    }
  }

  Connections {
    target: SystemTray.items
    function onValuesChanged() {
      root.updateFilteredItems();
      // Repeater will automatically update when items change
    }
  }

  Connections {
    target: Settings
    function onSettingsSaved() {
      root.updateFilteredItems();
    }
  }

  // Watch for hidePassive changes to update filtering immediately
  onHidePassiveChanged: {
    root.updateFilteredItems();
  }

  Component.onCompleted: {
    root.updateFilteredItems(); // Initial update
  }

  // Content dimensions for implicit sizing
  readonly property int visibleItemCount: (root.drawerEnabled && dropdownItems.length > 0 ? 1 : 0) + filteredItems.length
  readonly property real capsulePadding: 0
  readonly property real capsuleWidth: isVertical ? capsuleHeight : Math.round(trayFlow.implicitWidth + capsulePadding * 2)
  readonly property real capsuleContentHeight: isVertical ? Math.round(trayFlow.implicitHeight + capsulePadding * 2) : capsuleHeight

  implicitWidth: isVertical ? barHeight : Math.round(trayFlow.implicitWidth + capsulePadding * 2)
  implicitHeight: isVertical ? Math.round(trayFlow.implicitHeight + capsulePadding * 2) : barHeight
  visible: filteredItems.length > 0 || dropdownItems.length > 0
  opacity: (filteredItems.length > 0 || dropdownItems.length > 0) ? 1.0 : 0.0

  // Visual capsule centered in parent
  Rectangle {
    id: visualCapsule
    width: capsuleWidth
    height: capsuleContentHeight
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth
  }

  NPopupContextMenu {
    id: chevronContextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   chevronContextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  Flow {
    id: trayFlow
    spacing: 0
    flow: isVertical ? Flow.TopToBottom : Flow.LeftToRight

    // Position centered in capsule
    anchors.centerIn: visualCapsule

    // Drawer opener (before items if opposite direction)
    NIconButton {
      id: chevronIconBefore
      visible: root.drawerEnabled && dropdownItems.length > 0 && BarService.getPillDirection(root)
      width: isVertical ? barHeight : capsuleHeight
      height: isVertical ? capsuleHeight : barHeight
      tooltipText: I18n.tr("tooltips.open-tray-dropdown")
      tooltipDirection: BarService.getTooltipDirection(root.screen?.name)
      baseSize: capsuleHeight
      applyUiScale: false
      customRadius: Style.radiusL
      colorBg: "transparent"
      colorFg: root.chevronColor
      colorBorder: "transparent"
      colorBorderHover: "transparent"
      icon: {
        switch (barPosition) {
        case "bottom":
          return "caret-up";
        case "left":
          return "caret-right";
        case "right":
          return "caret-left";
        case "top":
        default:
          return "caret-down";
        }
      }
      onClicked: toggleDrawer(this)
      onRightClicked: PanelService.showContextMenu(chevronContextMenu, this, screen)
    }

    // Pinned items
    Repeater {
      id: repeater
      model: root.filteredItems

      delegate: Item {
        id: trayDelegate
        required property var modelData
        required property int index
        width: isVertical ? barHeight : capsuleHeight
        height: isVertical ? capsuleHeight : barHeight
        visible: modelData
        readonly property bool isHovered: root.hoveredItemIndex === index

        // Tooltip anchor representing the visual area (for proper tooltip positioning)
        Item {
          id: tooltipAnchor
          width: capsuleHeight
          height: capsuleHeight
          x: Style.pixelAlignCenter(parent.width, width)
          y: Style.pixelAlignCenter(parent.height, height)
        }

        IconImage {
          id: trayIcon
          width: iconSize
          height: iconSize
          x: Style.pixelAlignCenter(parent.width, width)
          y: Style.pixelAlignCenter(parent.height, height)
          asynchronous: true
          backer.fillMode: Image.PreserveAspectFit

          source: {
            let icon = modelData?.icon || "";
            if (!icon) {
              return "";
            }

            // Process icon path
            if (icon.includes("?path=")) {
              const chunks = icon.split("?path=");
              const name = chunks[0];
              const path = chunks[1];
              const fileName = name.substring(name.lastIndexOf("/") + 1);
              return `file://${path}/${fileName}`;
            }
            return icon;
          }
          opacity: status === Image.Ready ? 1 : 0

          layer.enabled: widgetSettings.colorizeIcons !== false
          layer.effect: ShaderEffect {
            property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
            property real colorizeMode: 1.0

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }
        }

        Rectangle {
          id: hoverIndicator
          anchors.bottom: trayIcon.bottom
          anchors.bottomMargin: -2
          anchors.horizontalCenter: trayIcon.horizontalCenter
          width: Style.toOdd(iconSize * 0.25)
          height: 4
          color: trayDelegate.isHovered ? Color.mHover : "transparent"
          radius: Math.min(Style.radiusXXS, width / 2)

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Style.easingTypeDefault
            }
          }
        }

        MouseArea {
          id: itemMouseArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onContainsMouseChanged: {
            if (containsMouse) {
              if (popupMenuWindow) {
                popupMenuWindow.close();
              }
              root.hoveredItemIndex = trayDelegate.index;
              TooltipService.show(tooltipAnchor, modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item", BarService.getTooltipDirection(root.screen?.name));
            } else if (root.hoveredItemIndex === trayDelegate.index) {
              root.hoveredItemIndex = -1;
              TooltipService.hide(tooltipAnchor);
            }
          }
          onClicked: mouse => {
                       if (!modelData) {
                         return;
                       }

                       if (mouse.button === Qt.LeftButton) {
                         // Close any open menu first
                         if (popupMenuWindow) {
                           popupMenuWindow.close();
                         }

                         if (!modelData.onlyMenu) {
                           modelData.activate();
                         }
                       } else if (mouse.button === Qt.MiddleButton) {
                         // Close the menu if it was visible
                         if (popupMenuWindow && popupMenuWindow.visible) {
                           popupMenuWindow.close();
                           return;
                         }
                         modelData.secondaryActivate && modelData.secondaryActivate();
                       } else if (mouse.button === Qt.RightButton) {
                         TooltipService.hideImmediately();

                         // Close the menu if it was visible
                         if (popupMenuWindow && popupMenuWindow.visible) {
                           popupMenuWindow.close();
                           return;
                         }

                         // Close any opened panel
                         if ((PanelService.openedPanel !== null) && !PanelService.openedPanel.isClosing) {
                           PanelService.openedPanel.close();
                         }

                         if (modelData.hasMenu && modelData.menu && trayMenu && trayMenu.item) {
                           // Calculate menu position after ensuring menu is loaded
                           const calculateAndShow = () => {
                             // Position menu based on bar position, using tooltipAnchor for proper positioning
                             // Increased spacing for better alignment with other context menus
                             let menuX, menuY;
                             if (barPosition === "left") {
                               // For left bar: position menu to the right of the visual area
                               menuX = tooltipAnchor.width + Style.marginL;
                               menuY = 0;
                             } else if (barPosition === "right") {
                               // For right bar: position menu to the left of the visual area
                               menuX = -trayMenu.item.implicitWidth - Style.marginL;
                               menuY = 0;
                             } else {
                               // For horizontal bars: center horizontally and position below visual area
                               menuX = (tooltipAnchor.width / 2) - (trayMenu.item.implicitWidth / 2);
                               menuY = tooltipAnchor.height + Style.marginS;
                             }

                             PanelService.showTrayMenu(root.screen, modelData, trayMenu.item, tooltipAnchor, menuX, menuY, root.section, root.sectionWidgetIndex);
                           };

                           // Use Qt.callLater to ensure menu dimensions are calculated
                           Qt.callLater(calculateAndShow);
                         } else {
                           Logger.d("Tray", "No menu available for", modelData.id, "or trayMenu not set");
                         }
                       }
                     }
        }
      }
    }

    // Drawer opener (after items if normal direction)
    NIconButton {
      id: chevronIconAfter
      visible: root.drawerEnabled && dropdownItems.length > 0 && !BarService.getPillDirection(root)
      width: isVertical ? barHeight : capsuleHeight
      height: isVertical ? capsuleHeight : barHeight
      tooltipText: I18n.tr("tooltips.open-tray-dropdown")
      tooltipDirection: BarService.getTooltipDirection(root.screen?.name)
      baseSize: capsuleHeight
      applyUiScale: false
      customRadius: Style.radiusL
      colorBg: "transparent"
      colorFg: root.chevronColor
      colorBorder: "transparent"
      colorBorderHover: "transparent"
      icon: {
        switch (barPosition) {
        case "bottom":
          return "caret-up";
        case "left":
          return "caret-right";
        case "right":
          return "caret-left";
        case "top":
        default:
          return "caret-down";
        }
      }
      onClicked: toggleDrawer(this)
      onRightClicked: PanelService.showContextMenu(chevronContextMenu, this, screen)
    }
  } // closes Flow
}

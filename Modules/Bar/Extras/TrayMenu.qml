import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

PopupWindow {
  id: root

  property ShellScreen screen

  property var trayItem: null
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property string widgetSection: ""
  property int widgetIndex: -1

  // Derive menu from trayItem (only used for non-submenus)
  readonly property QsMenuHandle menu: isSubMenu ? null : (trayItem ? trayItem.menu : null)

  // Compute if current tray item is pinned
  readonly property bool isPinned: {
    if (!trayItem || widgetSection === "" || widgetIndex < 0)
      return false;
    var widgets = Settings.data.bar.widgets[widgetSection];
    if (!widgets || widgetIndex >= widgets.length)
      return false;
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray")
      return false;
    var pinnedList = widgetSettings.pinned || [];
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] === itemName)
        return true;
    }
    return false;
  }

  readonly property int menuWidth: 220

  implicitWidth: menuWidth

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(screen?.height * 0.9, flickable.contentHeight + (Style.marginS * 2))
  visible: false
  color: Color.transparent
  anchor.item: anchorItem
  anchor.rect.x: {
    if (anchorItem && screen) {
      let baseX = anchorX;

      // Calculate position relative to current screen
      let menuScreenX;
      if (isSubMenu && anchorItem.Window && anchorItem.Window.window) {
        const posInPopup = anchorItem.mapToItem(null, 0, 0);
        const parentWindow = anchorItem.Window.window;
        const windowXOnScreen = parentWindow.x - screen.x;
        menuScreenX = windowXOnScreen + posInPopup.x + baseX;
      } else {
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        menuScreenX = anchorGlobalPos.x + baseX;
      }

      const menuRight = menuScreenX + implicitWidth;
      const screenRight = screen.width;

      // Adjust if menu would clip on the right
      if (menuRight > screenRight) {
        const overflow = menuRight - screenRight;
        return baseX - overflow - Style.marginM;
      }
      // Adjust if menu would clip on the left
      if (menuScreenX < 0) {
        return baseX - menuScreenX + Style.marginM;
      }
      return baseX;
    }
    return anchorX;
  }
  anchor.rect.y: {
    if (anchorItem && screen) {
      const barPosition = Settings.data.bar.position;

      // Calculate base Y offset (relative to anchor item)
      let baseY = anchorY;
      if (!isSubMenu && barPosition === "bottom") {
        // For bottom bar, position menu above the anchor with margin (adjusted to match widget menu positioning)
        baseY = -(implicitHeight + Style.marginL + 2);
      }

      // Calculate position relative to current screen (not global coordinates)
      let menuScreenY;
      if (isSubMenu && anchorItem.Window && anchorItem.Window.window) {
        // Submenu: anchor is inside parent PopupWindow
        const posInPopup = anchorItem.mapToItem(null, 0, 0);
        const parentWindow = anchorItem.Window.window;
        // Convert global window Y to screen-relative Y by subtracting screen offset
        const windowYOnScreen = parentWindow.y - screen.y;
        menuScreenY = windowYOnScreen + posInPopup.y + baseY;
      } else if (!isSubMenu && barPosition === "bottom") {
        // Bottom bar main menu: subtract baseY to position above anchor
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        menuScreenY = anchorGlobalPos.y - baseY;
      } else {
        // Main menu for other positions: add baseY
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        menuScreenY = anchorGlobalPos.y + baseY;
      }

      const menuBottom = menuScreenY + implicitHeight;
      const screenBottom = screen.height;

      // Adjust baseY if menu would clip
      if (menuBottom > screenBottom) {
        // Clip at bottom - shift up by the overflow amount
        const overflow = menuBottom - screenBottom;
        if (!isSubMenu && barPosition === "bottom") {
          return baseY + overflow + Style.marginM;
        }
        return baseY - overflow - Style.marginM;
      }
      if (menuScreenY < 0) {
        // Clip at top - shift down
        if (!isSubMenu && barPosition === "bottom") {
          return baseY + menuScreenY - Style.marginM;
        }
        return baseY - menuScreenY + Style.marginM;
      }
      return baseY;
    }

    // Fallback if no anchor/screen
    if (isSubMenu) {
      return anchorY;
    }
    return anchorY + (Settings.data.bar.position === "bottom" ? -implicitHeight : Style.barHeight);
  }

  function showAt(item, x, y) {
    if (!item) {
      Logger.w("TrayMenu", "anchorItem is undefined, won't show menu.");
      return;
    }

    if (!opener.children || opener.children.values.length === 0) {
      //Logger.w("TrayMenu", "Menu not ready, delaying show")
      Qt.callLater(() => showAt(item, x, y));
      return;
    }

    anchorItem = item;
    anchorX = x;
    anchorY = y;

    visible = true;
    forceActiveFocus();

    // Force update after showing.
    Qt.callLater(() => {
                   root.anchor.updateAnchor();
                 });
  }

  function hideMenu() {
    visible = false;

    // Clean up all submenus recursively
    for (var i = 0; i < columnLayout.children.length; i++) {
      const child = columnLayout.children[i];
      if (child?.subMenu) {
        child.subMenu.hideMenu();
        child.subMenu.destroy();
        child.subMenu = null;
      }
    }
  }

  Item {
    anchors.fill: parent
    Keys.onEscapePressed: root.hideMenu()
  }

  QsMenuOpener {
    id: opener
    menu: root.menu
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS)
    radius: Style.radiusM

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }

    // Use a ColumnLayout to handle menu item arrangement
    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        model: opener.children ? [...opener.children.values] : []

        delegate: Rectangle {
          id: entry
          required property var modelData

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: {
            if (modelData?.isSeparator) {
              return 8;
            } else {
              // Calculate based on text content
              const textHeight = text.contentHeight || (Style.fontSizeS * 1.2);
              return Math.max(28, textHeight + (Style.marginS * 2));
            }
          }

          color: Color.transparent
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - (Style.marginM * 2)
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mHover : Color.transparent
            radius: Style.radiusS
            visible: !(modelData?.isSeparator ?? false)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginS

              NText {
                id: text
                Layout.fillWidth: true
                color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface) : Color.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                pointSize: Style.fontSizeS
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
              }

              Image {
                Layout.preferredWidth: Style.marginL
                Layout.preferredHeight: Style.marginL
                source: modelData?.icon ?? ""
                visible: (modelData?.icon ?? "") !== ""
                fillMode: Image.PreserveAspectFit
              }

              NIcon {
                icon: modelData?.hasChildren ? "menu" : ""
                pointSize: Style.fontSizeS
                applyUiScale: false
                verticalAlignment: Text.AlignVCenter
                visible: modelData?.hasChildren ?? false
                color: (mouseArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false) && root.visible
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                           if (modelData && !modelData.isSeparator) {
                             if (modelData.hasChildren) {
                               // Click on items with children toggles submenu
                               if (entry.subMenu) {
                                 // Close existing submenu
                                 entry.subMenu.hideMenu();
                                 entry.subMenu.destroy();
                                 entry.subMenu = null;
                               } else {
                                 // Close any other open submenus first
                                 for (var i = 0; i < columnLayout.children.length; i++) {
                                   const sibling = columnLayout.children[i];
                                   if (sibling !== entry && sibling.subMenu) {
                                     sibling.subMenu.hideMenu();
                                     sibling.subMenu.destroy();
                                     sibling.subMenu = null;
                                   }
                                 }

                                 // Determine submenu opening direction
                                 let openLeft = false;
                                 const barPosition = Settings.data.bar.position;
                                 const globalPos = entry.mapToItem(null, 0, 0);

                                 if (barPosition === "right") {
                                   openLeft = true;
                                 } else if (barPosition === "left") {
                                   openLeft = false;
                                 } else {
                                   openLeft = (root.widgetSection === "right");
                                 }

                                 // Open new submenu
                                 entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                                   "menu": modelData,
                                                                                                   "isSubMenu": true,
                                                                                                   "screen": root.screen
                                                                                                 });

                                 if (entry.subMenu) {
                                   const overlap = 60;
                                   entry.subMenu.anchorItem = entry;
                                   entry.subMenu.anchorX = openLeft ? -overlap : overlap;
                                   entry.subMenu.anchorY = 0;
                                   entry.subMenu.visible = true;
                                   // Force anchor update with new position
                                   Qt.callLater(() => {
                                                  entry.subMenu.anchor.updateAnchor();
                                                });
                                 }
                               }
                             } else {
                               // Click on regular items triggers them
                               modelData.triggered();
                               root.hideMenu();

                               // Close the drawer if it's open
                               if (root.screen) {
                                 const panel = PanelService.getPanel("trayDrawerPanel", root.screen);
                                 if (panel && panel.visible) {
                                   panel.close();
                                 }
                               }
                             }
                           }
                         }
            }
          }

          Component.onDestruction: {
            if (subMenu) {
              subMenu.destroy();
              subMenu = null;
            }
          }
        }
      }

      // PIN / UNPIN
      Rectangle {
        visible: {
          if (widgetSection === "" || widgetIndex < 0)
            return false;
          var widgets = Settings.data.bar.widgets[widgetSection];
          if (!widgets || widgetIndex >= widgets.length)
            return false;
          var widgetSettings = widgets[widgetIndex];
          if (!widgetSettings)
            return false;
          return widgetSettings.drawerEnabled ?? false;
        }
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: 28
        color: pinUnpinMouseArea.containsMouse ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Qt.alpha(Color.mPrimary, pinUnpinMouseArea.containsMouse ? 0.4 : 0.2)
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: root.isPinned ? "unpin" : "pin"
            pointSize: Style.fontSizeS
            applyUiScale: false
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }

          NText {
            Layout.fillWidth: true
            color: Color.mPrimary
            text: root.isPinned ? I18n.tr("settings.bar.tray.unpin-application") : I18n.tr("settings.bar.tray.pin-application")
            pointSize: Style.fontSizeS
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: pinUnpinMouseArea
          anchors.fill: parent
          hoverEnabled: true

          onClicked: {
            if (root.isPinned) {
              root.removeFromPinned();
            } else {
              root.addToPinned();
            }
          }
        }
      }
    }
  }

  function addToPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot pin: missing tray item or widget info");
      return;
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot pin: tray item has no name");
      return;
    }
    var widgets = Settings.data.bar.widgets[widgetSection];
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot pin: invalid widget index");
      return;
    }
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot pin: widget is not a Tray widget");
      return;
    }
    var pinnedList = widgetSettings.pinned || [];
    var newPinned = pinnedList.slice();
    newPinned.push(itemName);
    var newSettings = Object.assign({}, widgetSettings);
    newSettings.pinned = newPinned;
    widgets[widgetIndex] = newSettings;
    Settings.data.bar.widgets[widgetSection] = widgets;
    Settings.saveImmediate();

    // Close drawer when pinning (drawer needs to resize)
    if (screen) {
      const panel = PanelService.getPanel("trayDrawerPanel", screen);
      if (panel)
        panel.close();
    }
  }

  function removeFromPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot unpin: missing tray item or widget info");
      return;
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot unpin: tray item has no name");
      return;
    }
    var widgets = Settings.data.bar.widgets[widgetSection];
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot unpin: invalid widget index");
      return;
    }
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot unpin: widget is not a Tray widget");
      return;
    }
    var pinnedList = widgetSettings.pinned || [];
    var newPinned = [];
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] !== itemName) {
        newPinned.push(pinnedList[i]);
      }
    }
    var newSettings = Object.assign({}, widgetSettings);
    newSettings.pinned = newPinned;
    widgets[widgetIndex] = newSettings;
    Settings.data.bar.widgets[widgetSection] = widgets;
    Settings.saveImmediate();
  }
}
